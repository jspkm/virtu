import UIKit
import UIKit.UIGestureRecognizerSubclass
import PencilKit

/// Purely observational pencil tracker: never leaves `.possible`, so it can't
/// interfere with PencilKit's drawing recognizer — it just watches the same
/// touches to feed the live wet-ink layer the OS no longer draws.
final class PencilObserverRecognizer: UIGestureRecognizer {
    var onBegan: ((CGPoint) -> Void)?
    var onMoved: (([CGPoint]) -> Void)?
    var onEnded: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        onBegan?(touch.location(in: view))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view else { return }
        let coalesced = event.coalescedTouches(for: touch) ?? [touch]
        onMoved?(coalesced.map { $0.location(in: view) })
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        onEnded?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        onEnded?()
    }
}

/// PencilKit hangs a text-style edit menu ("Select All / Insert Space") off
/// its canvas, and re-adds the interaction after init — so removing it once at
/// setup does not hold. Over a score that menu is never the right answer, and
/// in Perform, where the pencil is inert, it is actively hostile: a player
/// gets a text menu across the music they are reading. This canvas refuses the
/// interaction outright and answers no to every editing action.
final class ScoreCanvasView: PKCanvasView {
    /// Fingers never draw (PRD 0.2), so the canvas has no business receiving
    /// them — and refusing them is the only reliable way to stop the menu.
    /// Blocking the interaction on this view was not enough: PencilKit
    /// presents "Select All / Insert Space" from an interaction on its own
    /// internal content view, which we do not own and cannot subclass. A
    /// finger that never reaches the canvas cannot summon it.
    ///
    /// This also helps navigation: the turn, mode and undo gestures all live
    /// on the parent, and now get the finger touches unobstructed.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let event, let touch = event.allTouches?.first, touch.type != .pencil {
            return nil
        }
        return super.hitTest(point, with: event)
    }

    override func addInteraction(_ interaction: UIInteraction) {
        guard !(interaction is UIEditMenuInteraction) else { return }
        super.addInteraction(interaction)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        false
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        // Contribute nothing; deliberately does not call super.
    }
}

/// One rendered score page with its annotation canvas.
///
/// The canvas is a plain, constraint-pinned subview — no view transforms,
/// which PencilKit's internal renderer does not tolerate. Instead the
/// *drawing data* is scaled: the master drawing lives in PDF-point space
/// (journal, export, and M1 compatibility), and is transformed to display
/// space when shown. Hand-drawn changes are transformed back on save.
final class ReadingPageView: UIView {

    let imageView = UIImageView()
    /// Persisted ink, rendered as an image. PKCanvasView's internal renderer
    /// does not reliably display programmatically-set drawings (simulator at
    /// minimum), so the canvas is the live *input* surface and this layer is
    /// the durable *display* surface.
    let inkView = UIImageView()
    /// Recreated at each display handoff — see rebuildCanvas().
    private(set) var canvas = ScoreCanvasView()

    private(set) var pageIndex: Int = -1
    private var partID: UUID?
    private(set) var pdfSize = CGSize(width: 595, height: 842)

    /// Master ink in PDF-point space, one drawing per layer.
    ///
    /// The canvas is handed *only* the active layer. That is what makes erase,
    /// lasso and undo unable to reach the others: the scoping is structural,
    /// not policed — PencilKit is never given the ink it must not touch.
    private var layerDrawings: [Int: PKDrawing] = [:]
    private(set) var activeLayer: Int = AnnotationLayers.first
    private(set) var visibleLayers: [Int] = [AnnotationLayers.first]

    private var activeDrawing: PKDrawing {
        get { layerDrawings[activeLayer] ?? PKDrawing() }
        set { layerDrawings[activeLayer] = newValue }
    }

    /// Visible ink, bottom-up: layer 1 at the bottom.
    private var visibleDrawings: [PKDrawing] {
        visibleLayers.sorted().compactMap { layerDrawings[$0] }
    }
    private var appliedScale: CGFloat = 0
    private var isApplying = false
    private let journal = StrokeJournal.shared

    /// Called when the user begins drawing on this page's canvas.
    var onCanvasUsed: ((ReadingPageView) -> Void)?

    // Live wet ink: iPadOS 26.x's PencilKit shows nothing while drawing, so a
    // shape layer previews the stroke under the tip; the pressure-rendered
    // commit replaces it at pen-up.
    private let wetLayer = CAShapeLayer()
    private let wetPath = UIBezierPath()
    private var wetStyleColor: UIColor = .black
    private var wetStyleWidth: CGFloat = 3
    private var wetActive = false

    private var displayScale: CGFloat {
        guard bounds.width > 0, pdfSize.width > 0 else { return 0 }
        return bounds.width / pdfSize.width
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = UIColor(hex: 0xFFFDF8)
        layer.borderWidth = 1
        layer.borderColor = UIColor(hex: 0xE0DBD1).cgColor
        layer.cornerRadius = 4
        clipsToBounds = true

        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        inkView.contentMode = .scaleToFill
        inkView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(inkView)

        configureAndAttachCanvas(canvas)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),

            inkView.topAnchor.constraint(equalTo: topAnchor),
            inkView.bottomAnchor.constraint(equalTo: bottomAnchor),
            inkView.leadingAnchor.constraint(equalTo: leadingAnchor),
            inkView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        wetLayer.fillColor = nil
        wetLayer.lineCap = .round
        wetLayer.lineJoin = .round
        layer.addSublayer(wetLayer)

        let observer = PencilObserverRecognizer()
        observer.cancelsTouchesInView = false
        observer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        // The observer only feeds the wet preview; pencil-up truth comes from
        // PencilKit's drawing recognizer (see drawingGestureChanged).
        observer.onBegan = { [weak self] point in self?.wetBegan(at: point) }
        observer.onMoved = { [weak self] points in self?.wetMoved(through: points) }
        observer.onEnded = { [weak self] in self?.wetEnded() }
        addGestureRecognizer(observer)
    }

    /// Shared canvas configuration — used at init and every rebirth, so a
    /// fresh canvas can never regress the inset/offset guarantees.
    private func configureAndAttachCanvas(_ c: ScoreCanvasView) {
        c.drawingPolicy = .pencilOnly
        c.backgroundColor = .clear
        c.isOpaque = false
        c.delegate = self
        // PKCanvasView is a scroll view: any content inset/offset shifts
        // recorded strokes away from the pencil tip. Fixed, inset-free surface.
        c.contentInsetAdjustmentBehavior = .never
        c.isScrollEnabled = false
        // Belt to ScoreCanvasView's braces: strip any edit-menu interaction
        // PencilKit attached before we could refuse it — on the canvas and on
        // every internal view it has built so far.
        c.stripEditMenuInteractions()
        c.translatesAutoresizingMaskIntoConstraints = false
        addSubview(c)
        NSLayoutConstraint.activate([
            c.topAnchor.constraint(equalTo: topAnchor),
            c.bottomAnchor.constraint(equalTo: bottomAnchor),
            c.leadingAnchor.constraint(equalTo: leadingAnchor),
            c.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        // Authoritative pencil-up detection: our passive observer's touch-ends
        // are not reliably delivered once PencilKit's recognizer claims the
        // gesture (verified on hardware — the flag stuck forever). PencilKit's
        // own drawing recognizer always knows.
        c.drawingGestureRecognizer.addTarget(self, action: #selector(drawingGestureChanged(_:)))
    }

    @objc private func drawingGestureChanged(_ gesture: UIGestureRecognizer) {
        switch gesture.state {
        case .began:
            setPencilDown(true)
        case .ended, .cancelled, .failed:
            setPencilDown(false)
            wetEnded()
        default:
            break
        }
    }

    /// The nuclear display handoff: PencilKit gives no way to blank its
    /// interactive render layer (re-setting an equal drawing is a no-op, and
    /// the empty-then-set trick proved insufficient on hardware), so the old
    /// canvas — and whatever its layer still shows — is destroyed outright.
    /// The fresh canvas gets the master programmatically (which renders
    /// blank per the OS bug), leaving the ink layer as sole display owner.
    private func rebuildCanvas() {
        let old = canvas
        old.removeFromSuperview()

        canvas = ScoreCanvasView()
        configureAndAttachCanvas(canvas)
        canvas.drawingGestureRecognizer.isEnabled = annotationEnabled && canInk
        if let tool = lastAppliedTool {
            canvas.tool = tool
        }
        applyDrawingToCanvas()
    }

    // MARK: - Display ownership
    //
    // Two renderers can show ink: PencilKit's canvas layer (interactive
    // content — live strokes, floating lasso selections) and our inkView
    // (the committed master). If both stay lit they can disagree — a moved
    // selection shows at its new position while the ink layer still shows the
    // old one, reading as a duplicate. Policy: PencilKit owns the display
    // DURING a gesture/lasso session; the ink layer owns it BETWEEN them.
    // Handing off = programmatically re-setting canvas.drawing, which blanks
    // PencilKit's layer — done only when no pencil is down and never during a
    // lasso session, so selections are never destroyed mid-flight.

    private(set) var pencilDown = false
    private(set) var canvasNormalizations = 0
    private var normalizeWork: DispatchWorkItem?
    private var isLassoSession = false

    func setPencilDown(_ down: Bool) {
        pencilDown = down
        if !down {
            scheduleCanvasNormalization()
        }
    }

    private func scheduleCanvasNormalization(after delay: TimeInterval = 0.25) {
        guard !isLassoSession else { return }
        normalizeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.pencilDown, !self.isLassoSession else { return }
            self.rebuildCanvas()
            self.canvasNormalizations += 1
        }
        normalizeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Wet ink

    private func wetBegan(at point: CGPoint) {
        guard annotationEnabled, wetActive else { return }
        wetPath.removeAllPoints()
        wetPath.move(to: point)
        wetLayer.strokeColor = wetStyleColor.cgColor
        wetLayer.lineWidth = wetStyleWidth
        wetLayer.path = wetPath.cgPath
    }

    private func wetMoved(through points: [CGPoint]) {
        guard annotationEnabled, wetActive, !wetPath.isEmpty else { return }
        for point in points {
            wetPath.addLine(to: point)
        }
        wetLayer.path = wetPath.cgPath
    }

    private func wetEnded() {
        // The committed render lands via canvasViewDrawingDidChange; give it
        // one runloop turn before lifting the preview so ink never blinks.
        DispatchQueue.main.async { [weak self] in
            self?.clearWet()
        }
    }

    private func clearWet() {
        wetPath.removeAllPoints()
        wetLayer.path = nil
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(partID: UUID?, pageIndex: Int, pdfSize: CGSize) {
        self.pdfSize = pdfSize

        guard partID != self.partID || pageIndex != self.pageIndex else { return }
        self.partID = partID
        self.pageIndex = pageIndex

        layerDrawings = [:]
        if let partID {
            for layer in AnnotationLayers.first...AnnotationLayers.max {
                if let saved = journal.load(partID: partID, pageIndex: pageIndex, layer: layer) {
                    layerDrawings[layer] = saved
                }
            }
        }
        appliedScale = 0
        applyDrawingToCanvas()
    }

    /// Push the part's layer state in. Idempotent, because this runs on every
    /// state sync: only a genuine change costs a re-render.
    func setLayers(active: Int, visible: [Int]) {
        guard active != activeLayer || visible != visibleLayers else { return }
        activeLayer = active
        visibleLayers = visible

        // EVERY layer change goes through the nuclear handoff, visibility
        // included. Re-rendering only our ink layer was not enough: PencilKit
        // is still lighting the strokes it drew interactively, so hiding a
        // layer cleared the older marks (which lived only in our layer) and
        // left the freshly-written ones on screen. Destroy the canvas so the
        // ink layer is once again the sole display owner.
        rebuildCanvas()
        canvasNormalizations += 1
    }

    /// A hidden active layer accepts no ink. Reachable only by hiding every
    /// layer — at which point the musician has asked for a clean score, and
    /// writing into something invisible is never what that meant.
    private var canInk: Bool {
        visibleLayers.contains(activeLayer)
    }

    var annotationEnabled: Bool = false {
        didSet {
            canvas.drawingGestureRecognizer.isEnabled = annotationEnabled && canInk
        }
    }

    private(set) var toolAssignments = 0
    private var appliedToolKey = ""
    private var lastAppliedTool: PKTool?

    func apply(tool: PKTool) {
        // Idempotent: reassigning canvas.tool mid-gesture (e.g. from a UI
        // timer triggering a state sync) cancels PencilKit's in-flight stroke
        // or selection. Only assign when the tool genuinely changed.
        let key = Self.toolKey(for: tool)
        guard key != appliedToolKey else { return }
        appliedToolKey = key
        toolAssignments += 1
        lastAppliedTool = tool
        canvas.tool = tool

        let enteringLasso = tool is PKLassoTool
        if enteringLasso != isLassoSession {
            isLassoSession = enteringLasso
            // Lasso session: PencilKit's layer owns display (it renders the
            // selection and drag live); hide the ink layer so old positions
            // can't ghost. Leaving lasso: normalize and hand back.
            inkView.isHidden = enteringLasso
            if !enteringLasso {
                rebuildCanvas()
                canvasNormalizations += 1
            }
        }

        if let inking = tool as? PKInkingTool {
            wetStyleColor = inking.color
            wetStyleWidth = inking.width
            wetActive = true
        } else {
            // Eraser and lasso get no wet preview.
            wetActive = false
            clearWet()
        }
    }

    private static func toolKey(for tool: PKTool) -> String {
        if let inking = tool as? PKInkingTool {
            return "ink-\(inking.inkType.rawValue)-\(inking.width)-\(inking.color.description)"
        }
        if let eraser = tool as? PKEraserTool {
            return "eraser-\(String(describing: eraser.eraserType))"
        }
        if tool is PKLassoTool {
            return "lasso"
        }
        return String(describing: type(of: tool))
    }

    /// Convert a point in this view's coordinate space to PDF-point space.
    func pdfPoint(fromPagePoint point: CGPoint) -> CGPoint {
        let scale = displayScale
        guard scale > 0 else { return point }
        return CGPoint(x: point.x / scale, y: point.y / scale)
    }

    // MARK: - Programmatic edits (stamps, scoped erase)

    /// Append strokes (in PDF-point space) to the active layer.
    func addStrokes(_ strokes: [PKStroke]) {
        guard !strokes.isEmpty else { return }
        var next = activeDrawing
        next.strokes.append(contentsOf: strokes)
        setMaster(next, registerUndo: true)
    }

    /// Remove strokes matching the predicate (evaluated in PDF space) from the
    /// active layer. Hidden layers are never candidates — a mark you cannot
    /// see can never be destroyed by a swipe you did not aim at it.
    func removeStrokes(where shouldRemove: (PKStroke) -> Bool) {
        var next = activeDrawing
        let before = next.strokes.count
        next.strokes.removeAll(where: shouldRemove)
        guard next.strokes.count != before else { return }
        setMaster(next, registerUndo: true)
    }

    private func setMaster(_ drawing: PKDrawing, registerUndo: Bool, layer: Int? = nil) {
        // Undo must land on the layer the edit was made on, even if the
        // musician has since switched layers.
        let target = layer ?? activeLayer
        let before = layerDrawings[target] ?? PKDrawing()
        layerDrawings[target] = drawing
        if target == activeLayer {
            applyDrawingToCanvas()
        } else {
            renderInkFallback()
        }
        persist(layer: target)

        if registerUndo {
            canvas.undoManager?.registerUndo(withTarget: self) { page in
                page.setMaster(before, registerUndo: true, layer: target)
            }
        }
    }

    func saveDrawingIfNeeded() {
        persist(layer: activeLayer)
    }

    private func persist(layer: Int) {
        guard let partID, pageIndex >= 0 else { return }
        journal.save(
            layerDrawings[layer] ?? PKDrawing(),
            partID: partID,
            pageIndex: pageIndex,
            layer: layer,
            pageSize: pdfSize
        )
    }

    // MARK: - Display

    private func applyDrawingToCanvas() {
        let scale = displayScale
        guard scale > 0 else { return }
        isApplying = true
        // Force the reset through an empty drawing: assigning a drawing EQUAL
        // to the canvas's current one is a no-op inside PencilKit, which
        // leaves its interactive render layer lit — the committed ink layer
        // then double-renders every fresh stroke.
        canvas.drawing = PKDrawing()
        if canInk {
            canvas.drawing = activeDrawing.transformed(using: CGAffineTransform(scaleX: scale, y: scale))
        }
        isApplying = false
        appliedScale = scale
        renderInkFallback()
    }

    /// PencilKit's renderer does not display programmatically-set drawings on
    /// iPadOS 26.x — verified on both simulator and hardware (strokes journal
    /// correctly but never appear). InkRenderer is the display path everywhere.
    private func renderInkFallback() {
        inkView.image = InkRenderer.image(
            for: visibleDrawings, pdfSize: pdfSize, displayScale: displayScale)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // PencilKit builds its content views lazily, so an interaction can
        // appear long after setup.
        canvas.stripEditMenuInteractions()
        if canvas.contentOffset != .zero {
            canvas.contentOffset = .zero
        }
        if abs(displayScale - appliedScale) > 0.001 {
            applyDrawingToCanvas()
        }
    }
}

extension ReadingPageView: PKCanvasViewDelegate {
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isApplying else { return }
        let scale = displayScale
        guard scale > 0, let partID, pageIndex >= 0 else { return }
        activeDrawing = canvasView.drawing.transformed(
            using: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale)
        )
        journal.save(
            activeDrawing,
            partID: partID,
            pageIndex: pageIndex,
            layer: activeLayer,
            pageSize: pdfSize
        )
        renderInkFallback()
        // Never re-set canvas.drawing HERE — this delegate fires mid-gesture,
        // and a reset destroys PencilKit's in-flight state (a floating lasso
        // selection drops as a duplicate). Normalization is deferred to a
        // safe moment by the display-ownership machinery.
        scheduleCanvasNormalization()
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        onCanvasUsed?(self)
    }
}

extension UIView {
    /// Remove every edit-menu interaction in this view's tree.
    func stripEditMenuInteractions() {
        interactions
            .filter { $0 is UIEditMenuInteraction }
            .forEach(removeInteraction)
        subviews.forEach { $0.stripEditMenuInteractions() }
    }
}
