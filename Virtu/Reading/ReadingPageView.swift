import UIKit
import UIKit.UIGestureRecognizerSubclass
import PencilKit

/// Purely observational pencil tracker: never leaves `.possible`, so it can't
/// interfere with PencilKit's drawing recognizer — it just watches the same
/// touches to feed the live wet-ink layer the OS no longer draws.
final class PencilObserverRecognizer: UIGestureRecognizer {
    /// A live sample: location plus normalized force (1 on devices that
    /// report none, so the simulator draws at full nib width).
    typealias Sample = (location: CGPoint, force: CGFloat)

    var onBegan: (([Sample]) -> Void)?
    var onMoved: ((_ real: [Sample], _ predicted: [Sample]) -> Void)?
    var onEnded: (() -> Void)?
    var onCancelled: (() -> Void)?

    private func sample(_ touch: UITouch) -> Sample {
        let norm = touch.maximumPossibleForce > 0
            ? touch.force / touch.maximumPossibleForce
            : 0.6   // the factor curve maps 0.6 to exactly the nib width
        return (touch.location(in: view), norm)
    }

    // Nothing prevents this recognizer and it prevents nothing: when
    // PencilKit's drawing recognizer claims the gesture, UIKit fails every
    // recognizer it can — a failed recognizer stops receiving touches, and
    // the wet preview starved to nothing mid-stroke on device.
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        onBegan?([sample(touch)])
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, view != nil else { return }
        let coalesced = event.coalescedTouches(for: touch) ?? [touch]
        // Predicted touches keep the ink under the tip: drawn this frame,
        // replaced by the real samples the next.
        let predicted = event.predictedTouches(for: touch) ?? []
        onMoved?(coalesced.map { sample($0) }, predicted.map { sample($0) })
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        onEnded?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        // A cancelled touch is the system taking the gesture back — paper
        // keeps no mark from a pencil that never truly landed.
        onCancelled?()
    }
}

/// PencilKit hangs a text-style edit menu ("Select All / Insert Space") off
/// its canvas, and re-adds the interaction after init — so removing it once at
/// setup does not hold. Over a score that menu is never the right answer, and
/// in Perform, where the pencil is inert, it is actively hostile: a player
/// gets a text menu across the music they are reading. This canvas refuses the
/// interaction outright and answers no to every editing action.
final class ScoreCanvasView: PKCanvasView {
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

    /// PencilKit builds its content views lazily and hangs the edit-menu
    /// interaction off them, not off the canvas — so catch each one as it
    /// arrives. (Refusing touches in hitTest was tried and is a trap:
    /// `event.allTouches` is an unordered set, so testing `.first` rejects
    /// pencil touches at random. Strokes died mid-mark and the escaped
    /// touches panned the score instead.)
    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        subview.stripEditMenuInteractions()
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

    /// -1 used to mean "not configured yet" — which is now the left margin's
    /// own index, so an unconfigured page would have been mistaken for it.
    static let unconfiguredPage = Int.min
    private(set) var pageIndex: Int = ReadingPageView.unconfiguredPage
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

    // Live wet ink. Drawn by InkRenderer ITSELF — the stroke under the tip
    // and the committed stroke are one code path, so what you write is the
    // chosen style from the first millimetre and pen-up has nothing to snap.
    private let wetView = WetStrokeView()
    private var wetInk = PKInk(.pencil, color: .black)
    private var wetBaseWidth: CGFloat = 3
    private var wetActive = false
    /// The inking tool currently armed, nil for eraser/lasso. While an inking
    /// tool is armed, PencilKit's drawing recognizer is OFF: the pencil
    /// pipeline is ours end to end — observe, render, commit — so the points
    /// drawn under the tip are, identically, the points that persist. That is
    /// what makes pen-up change nothing: there is only one stroke, ever.
    private var armedInking: PKInkingTool?

    // MARK: - Copy mode (lasso > Copy)
    //
    // The marquee never goes near PencilKit: while copy is armed the canvas's
    // drawing recognizer is off and the pencil observer feeds a dashed
    // rectangle instead of wet ink. What gets copied is what is on screen —
    // engraving and committed ink together.
    var copyModeArmed = false {
        didSet {
            guard copyModeArmed != oldValue else { return }
            applyInputGate()
            if !copyModeArmed { clearMarquee() }
            // The ink layer carries the clippings, so copy mode must keep it
            // lit. Entering copy while a lasso display session is up ends the
            // session; leaving copy with the lasso still armed re-enters it.
            syncLassoSession()
        }
    }
    /// The finished marquee, handed up with its snapshot. View-space rect.
    var onRegionCopied: ((ReadingPageView, CGRect, UIImage) -> Void)?
    /// Pencil touched this page while copy mode is armed — the controller
    /// uses it to drop any floating copy that is still up.
    var onCopyPencilDown: (() -> Void)?
    /// A placed clipping was long-pressed back off the page: image and its
    /// current rect in view space, ready to float again.
    var onClippingLifted: ((ReadingPageView, UIImage, CGRect) -> Void)?
    private var marqueeStart: CGPoint?
    private var marqueeCurrent: CGPoint?
    private let marqueeLayer = CAShapeLayer()
    /// Long-press tracking: a stationary hold over a placed clipping lifts
    /// it for another move.
    private var copyHoldItem: DispatchWorkItem?
    private var copyDidLift = false

    // MARK: - Area eraser (ours)
    //
    // PencilKit's bitmap eraser erases against what PencilKit has RENDERED —
    // and on iPadOS 26.x it does not reliably render programmatically-set
    // drawings, so on hardware the tool rubbed against a blank layer and
    // erased nothing. The same OS bug that made the ink pipeline ours makes
    // the area eraser ours: pencil samples in, stroke segments within the
    // tip's radius out, live, through the same renderer as everything else.
    var areaEraserArmed = false {
        didSet {
            guard areaEraserArmed != oldValue else { return }
            applyInputGate()
        }
    }
    /// The visible tip, in view points. Small — precision is the entire
    /// reason to reach for the area eraser.
    static let areaEraseTipRadius: CGFloat = 6
    private var eraseSessionBefore: PKDrawing?
    private var eraseSessionChanged = false

    private var displayScale: CGFloat {
        guard bounds.width > 0, pdfSize.width > 0 else { return 0 }
        return bounds.width / pdfSize.width
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = UIColor(hex: 0xFFFDF8)
        // Score pages draw no border of their own: an engraved page already
        // has margins, and a drawn frame around it stacked into a nest of
        // lines at every screen edge. Only the Right Page keeps an edge (see
        // isMarginSurface) — it floats beside the score as a distinct sheet.
        layer.borderWidth = 0
        layer.borderColor = UIColor(hex: 0xE0DBD1).cgColor
        layer.cornerRadius = 0
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

        wetView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(wetView)
        NSLayoutConstraint.activate([
            wetView.topAnchor.constraint(equalTo: topAnchor),
            wetView.bottomAnchor.constraint(equalTo: bottomAnchor),
            wetView.leadingAnchor.constraint(equalTo: leadingAnchor),
            wetView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        marqueeLayer.fillColor = UIColor(hex: 0xB33F26).withAlphaComponent(0.06).cgColor
        marqueeLayer.strokeColor = UIColor(hex: 0xB33F26).cgColor
        marqueeLayer.lineWidth = 1.5
        marqueeLayer.lineDashPattern = [5, 4]
        marqueeLayer.isHidden = true
        layer.addSublayer(marqueeLayer)

        let observer = PencilObserverRecognizer()
        observer.cancelsTouchesInView = false
        observer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        // The observer only feeds the wet preview; pencil-up truth comes from
        // PencilKit's drawing recognizer (see drawingGestureChanged).
        observer.onBegan = { [weak self] samples in self?.inkGestureBegan(samples) }
        observer.onMoved = { [weak self] real, predicted in self?.inkGestureMoved(real, predicted: predicted) }
        observer.onEnded = { [weak self] in self?.inkGestureEnded() }
        observer.onCancelled = { [weak self] in self?.pencilGestureCancelled() }
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
            beginLassoInteractionIfNeeded()
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
        bringSubviewToFront(wetView)
        applyInputGate()
        canvas.alpha = canvasAlphaForTool
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

    // MARK: - The ink gesture (ours, not PencilKit's)

    func inkGestureBegan(_ samples: [PencilObserverRecognizer.Sample]) {
        // Any pencil landing on a page dismisses whatever tool panel is out.
        NotificationCenter.default.post(name: .virtuPencilOnPage, object: nil)
        if areaEraserArmed {
            guard annotationEnabled, canInk else { return }
            eraseSessionBefore = activeDrawing
            eraseSessionChanged = false
            eraseArea(at: samples.map(\.location))
            return
        }
        if copyModeArmed {
            guard annotationEnabled, let point = samples.last?.location else { return }
            // Any floating copy gets PLACED by this touch — never lost.
            onCopyPencilDown?()
            marqueeStart = point
            marqueeCurrent = point
            copyDidLift = false
            // Long-press a placed clipping and it lifts off the page for
            // another move.
            if clippingHit(at: point) != nil {
                let item = DispatchWorkItem { [weak self] in self?.performLift(at: point) }
                copyHoldItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: item)
            }
            updateMarquee()
            return
        }
        guard annotationEnabled, wetActive, armedInking != nil else { return }
        onCanvasUsed?(self)
        wetView.begin(ink: wetInk, baseWidth: wetBaseWidth, samples: samples)
    }

    func inkGestureMoved(_ samples: [PencilObserverRecognizer.Sample], predicted: [PencilObserverRecognizer.Sample] = []) {
        if areaEraserArmed {
            guard eraseSessionBefore != nil else { return }
            eraseArea(at: samples.map(\.location))
            return
        }
        if copyModeArmed {
            guard !copyDidLift, let start = marqueeStart,
                  let point = samples.last?.location else { return }
            let moved = hypot(point.x - start.x, point.y - start.y)
            if moved > 8 {
                // It is a marquee, not a long-press.
                copyHoldItem?.cancel()
                copyHoldItem = nil
            }
            marqueeCurrent = point
            updateMarquee()
            return
        }
        guard annotationEnabled, wetActive, armedInking != nil else { return }
        wetView.append(samples: samples, predicted: predicted)
    }

    /// Pen-up: the stroke that was on screen becomes the stroke that persists.
    /// Same points, same renderer — the swap is pixel-identical, so there is
    /// no blink and nothing to snap.
    func inkGestureEnded() {
        if areaEraserArmed {
            finishAreaErase()
            return
        }
        if copyModeArmed {
            defer { clearMarquee() }
            copyHoldItem?.cancel()
            copyHoldItem = nil
            guard !copyDidLift, let start = marqueeStart, let end = marqueeCurrent else { return }
            let rect = CGRect(
                x: min(start.x, end.x), y: min(start.y, end.y),
                width: abs(end.x - start.x), height: abs(end.y - start.y)
            ).intersection(bounds)
            // A tap is just a tap: placing and lifting are the explicit
            // operations, so nothing destructive hides behind a small touch.
            guard rect.width >= 8, rect.height >= 8 else { return }
            let image = snapshot(of: rect)
            onRegionCopied?(self, rect, image)
            return
        }
        defer { clearWet() }
        guard annotationEnabled, wetActive, armedInking != nil else { return }
        let scale = displayScale
        let live = wetView.strokePoints
        guard scale > 0, live.count > 1 else { return }

        let pdfPoints = live.map { p in
            PKStrokePoint(
                location: CGPoint(x: p.location.x / scale, y: p.location.y / scale),
                timeOffset: p.timeOffset,
                size: CGSize(width: p.size.width / scale, height: p.size.height / scale),
                opacity: p.opacity, force: p.force, azimuth: p.azimuth, altitude: p.altitude
            )
        }
        addStrokes([PKStroke(
            ink: wetInk,
            path: PKStrokePath(controlPoints: pdfPoints, creationDate: Date())
        )])
    }

    /// Defensive only — the eraser/lasso path can still call this.
    private func wetEnded() {
        DispatchQueue.main.async { [weak self] in
            self?.clearWet()
        }
    }

    private func clearWet() {
        wetView.clear()
    }

    /// The system took the touch back (notification pull, palm cancel).
    /// Every mode must land in a consistent state: a half-done rub becomes
    /// one committed, undoable edit rather than an unpersisted mutation; a
    /// marquee and any pending lift simply stop.
    private func pencilGestureCancelled() {
        clearWet()
        copyHoldItem?.cancel()
        copyHoldItem = nil
        clearMarquee()
        if eraseSessionBefore != nil {
            finishAreaErase()
        }
    }

    private func updateMarquee() {
        guard let start = marqueeStart, let current = marqueeCurrent else { return }
        let rect = CGRect(
            x: min(start.x, current.x), y: min(start.y, current.y),
            width: abs(current.x - start.x), height: abs(current.y - start.y)
        )
        marqueeLayer.isHidden = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        marqueeLayer.path = UIBezierPath(rect: rect).cgPath
        CATransaction.commit()
    }

    private func clearMarquee() {
        marqueeStart = nil
        marqueeCurrent = nil
        marqueeLayer.isHidden = true
        marqueeLayer.path = nil
    }

    /// What is on screen inside the rect: paper, engraving, committed ink.
    /// Composed from the two image layers directly, so the marquee itself and
    /// PencilKit's (near-invisible) canvas never leak into the copy.
    private func snapshot(of rect: CGRect) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        return renderer.image { ctx in
            UIColor(hex: 0xFFFDF8).setFill()
            ctx.fill(CGRect(origin: .zero, size: rect.size))
            ctx.cgContext.translateBy(x: -rect.origin.x, y: -rect.origin.y)
            if !imageView.isHidden, let page = imageView.image {
                page.draw(in: bounds)
            }
            if let ink = inkView.image {
                ink.draw(in: bounds)
            }
        }
    }

    /// Re-composites committed ink and clippings. Called after a drop lands
    /// on this page or a clipping is removed from it.
    func refreshClippings() {
        renderInkFallback()
    }

    /// The placed clipping under a view-space point, topmost first.
    func clippingHit(at point: CGPoint) -> Clipping? {
        let scale = displayScale
        guard scale > 0, let partID, pageIndex != Self.unconfiguredPage else { return nil }
        let pdfPoint = CGPoint(x: point.x / scale, y: point.y / scale)
        return ClippingStore.shared.clippings(partID: partID, pageIndex: pageIndex)
            .last { $0.rect.contains(pdfPoint) }
    }

    /// The long-press landed: the clipping comes off the page and floats again.
    private func performLift(at point: CGPoint) {
        copyHoldItem = nil
        guard let partID, let hit = clippingHit(at: point),
              let image = ClippingStore.shared.image(for: hit) else { return }
        copyDidLift = true
        clearMarquee()
        let scale = displayScale
        let viewRect = CGRect(
            x: hit.x * scale, y: hit.y * scale,
            width: hit.width * scale, height: hit.height * scale)
        ClippingStore.shared.remove(partID: partID, clippingID: hit.id)
        renderInkFallback()
        Haptics.medium()
        onClippingLifted?(self, image, viewRect)
    }

    /// Rub out only what the tip touches. Each pencil sample removes the
    /// stroke segments within the tip's radius; what survives is rebuilt as
    /// strokes of the same ink, so a line can be split in the middle exactly
    /// the way a real eraser splits graphite. Live — the ink disappears
    /// under the tip, not at pen-up.
    private func eraseArea(at viewPoints: [CGPoint]) {
        let scale = displayScale
        guard scale > 0, !viewPoints.isEmpty else { return }
        let pts = viewPoints.map { CGPoint(x: $0.x / scale, y: $0.y / scale) }
        let radius = Self.areaEraseTipRadius / scale

        var result: [PKStroke] = []
        var changed = false
        for stroke in activeDrawing.strokes {
            let reach = stroke.renderBounds.insetBy(dx: -radius, dy: -radius)
            guard pts.contains(where: { reach.contains($0) }) else {
                result.append(stroke)
                continue
            }
            // A lasso-moved stroke lives at path ⊗ transform — the path alone
            // is its PRE-move position. Hit-test in transformed space and
            // BAKE the transform into anything rebuilt, or a nicked stroke's
            // survivors snap back to where it was before the move (and a
            // moved stroke can be impossible to erase at all).
            let transform = stroke.transform
            // Dense samples so the cut lands where the tip is, not at the
            // nearest sparse control point.
            let sampled = Array(stroke.path.interpolatedPoints(by: .distance(1.5)))
            var runs: [[PKStrokePoint]] = []
            var run: [PKStrokePoint] = []
            var strokeTouched = false
            for p in sampled {
                let where_ = p.location.applying(transform)
                let hit = pts.contains {
                    hypot($0.x - where_.x, $0.y - where_.y)
                        <= radius + p.size.width / 2
                }
                if hit {
                    strokeTouched = true
                    if run.count > 1 { runs.append(run) }
                    run = []
                } else {
                    run.append(p)
                }
            }
            if run.count > 1 { runs.append(run) }

            guard strokeTouched else {
                result.append(stroke)
                continue
            }
            changed = true
            for seg in runs {
                let baked = seg.map { p in
                    PKStrokePoint(
                        location: p.location.applying(transform),
                        timeOffset: p.timeOffset, size: p.size,
                        opacity: p.opacity, force: p.force,
                        azimuth: p.azimuth, altitude: p.altitude)
                }
                result.append(PKStroke(
                    ink: stroke.ink,
                    path: PKStrokePath(controlPoints: baked, creationDate: Date())))
            }
        }
        guard changed else { return }
        eraseSessionChanged = true
        // Mid-rub: mutate and re-render only. Undo and the journal get ONE
        // entry for the whole rub, at pen-up.
        layerDrawings[activeLayer] = PKDrawing(strokes: result)
        renderInkFallback()
    }

    private func finishAreaErase() {
        defer {
            eraseSessionBefore = nil
            eraseSessionChanged = false
        }
        guard eraseSessionChanged, let before = eraseSessionBefore else { return }
        let final = activeDrawing
        // setMaster registers undo against what it finds — hand it the
        // pre-rub drawing so one undo restores the whole rub.
        layerDrawings[activeLayer] = before
        setMaster(final, registerUndo: true)
    }

    #if DEBUG
    var testActiveDrawing: PKDrawing { activeDrawing }
    /// Test hook: one complete rub, began through pen-up.
    func testAreaErase(at viewPoints: [CGPoint]) {
        eraseSessionBefore = activeDrawing
        eraseSessionChanged = false
        eraseArea(at: viewPoints)
        finishAreaErase()
    }
    #endif

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(partID: UUID?, pageIndex: Int, pdfSize: CGSize) {
        self.pdfSize = pdfSize

        guard partID != self.partID || pageIndex != self.pageIndex else { return }
        // A page turn mid-lasso-session would otherwise strand the new page
        // with its ink layer hidden and a blank PencilKit canvas on top.
        endLassoSession()
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

        // A layer change ends any lasso session first — the rebuild below
        // must hand display back to the ink layer, not to a blank canvas.
        endLassoSession()
        // EVERY layer change goes through the nuclear handoff, visibility
        // included. Re-rendering only our ink layer was not enough: PencilKit
        // is still lighting the strokes it drew interactively, so hiding a
        // layer cleared the older marks (which lived only in our layer) and
        // left the freshly-written ones on screen. Destroy the canvas so the
        // ink layer is once again the sole display owner.
        rebuildCanvas()
        canvasNormalizations += 1
        applyInputGate()
    }

    /// A hidden active layer accepts no ink. Reachable only by hiding every
    /// layer — at which point the musician has asked for a clean score, and
    /// writing into something invisible is never what that meant.
    private var canInk: Bool {
        visibleLayers.contains(activeLayer)
    }

    /// Margins carry no page image and read as the desk, not as more page.
    var isMarginSurface = false {
        didSet {
            imageView.isHidden = isMarginSurface
            layer.cornerRadius = isMarginSurface ? 2 : 0
            layer.borderWidth = isMarginSurface ? 1 : 0
        }
    }

    var annotationEnabled: Bool = false {
        didSet { applyInputGate() }
    }

    /// In Perform the canvas is inert *and untouchable*: with no touches
    /// reaching it there is no long press, and so no "Select All / Insert
    /// Space" over music somebody is reading.
    private func applyInputGate() {
        let live = annotationEnabled && canInk
        // PencilKit draws nothing of ours any more: its recognizer runs only
        // for the tools whose interaction it still owns (eraser, lasso).
        canvas.drawingGestureRecognizer.isEnabled =
            live && armedInking == nil && !copyModeArmed && !areaEraserArmed
        canvas.isUserInteractionEnabled = live && !copyModeArmed && !areaEraserArmed
    }

    /// A lasso DISPLAY session runs only for Move-mode lasso, and only once a
    /// lasso gesture has actually begun. Merely ARMING the lasso must change
    /// nothing on screen: the session swaps display to PencilKit's layer,
    /// which renders carrier ink types literally — dotted marks turned solid
    /// the moment the tool was picked up, before it had touched anything.
    /// Copy mode is lasso-armed but PencilKit never sees it — the ink layer
    /// (which also carries the clippings) must stay lit.
    private var lassoInteracted = false

    private func syncLassoSession() {
        let shouldRun = lastAppliedTool is PKLassoTool && !copyModeArmed && lassoInteracted
        guard shouldRun != isLassoSession else { return }
        isLassoSession = shouldRun
        // Session: hide the ink layer so old positions can't ghost under
        // PencilKit's live drag. Leaving: normalize and hand back.
        inkView.isHidden = shouldRun
        // The canvas is visible ONLY inside the session. It used to go
        // opaque the moment the lasso was ARMED — and on hardware PencilKit
        // does paint programmatically-set strokes, so its rendering sat at
        // full strength over ours and every marking shifted slightly the
        // instant the tool was picked up.
        canvasAlphaForTool = shouldRun ? 1 : 0.02
        canvas.alpha = canvasAlphaForTool
        if !shouldRun {
            lassoInteracted = false
            rebuildCanvas()
            canvasNormalizations += 1
        }
    }

    #if DEBUG
    /// Test hook for the session-entry path a real lasso gesture takes.
    func testBeginLassoInteraction() {
        beginLassoInteractionIfNeeded()
    }
    #endif

    /// Force-exit: used where continuing the session would strand a hidden
    /// ink layer (page re-key, layer change, gesture cancel).
    private func endLassoSession() {
        guard isLassoSession else { return }
        lassoInteracted = false
        syncLassoSession()
    }

    private func beginLassoInteractionIfNeeded() {
        guard lastAppliedTool is PKLassoTool, !copyModeArmed, !lassoInteracted else { return }
        lassoInteracted = true
        syncLassoSession()
    }

    private(set) var toolAssignments = 0
    private var appliedToolKey = ""
    private var lastAppliedTool: PKTool?
    /// Near-zero for every tool except the lasso. ONE rule, deliberately not
    /// per-style: InkRenderer is the sole authority on what committed ink
    /// looks like, and any moment PencilKit's layer is visible it can flash
    /// its own opinion — which is how switching the armed style visibly
    /// changed marks that were already on the page. The canvas still receives
    /// input (above 0.01 it still hit-tests); the wet layer previews every
    /// stroke with the same geometry the commit will use. The lasso is the
    /// one tool whose feedback PencilKit itself renders, so it alone gets a
    /// visible canvas.
    private var canvasAlphaForTool: CGFloat = 1

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

        // A fresh tool starts with no lasso interaction on record; the
        // session (if the new tool is the Move lasso) begins at its first
        // gesture, not here.
        lassoInteracted = false
        syncLassoSession()

        armedInking = tool as? PKInkingTool
        if let inking = armedInking {
            wetInk = PKInk(inking.inkType, color: inking.color)
            wetBaseWidth = inking.width
            wetActive = true
        } else {
            // Eraser and lasso get no wet preview; erasing reads back through
            // the ink layer, which re-renders on every change mid-gesture.
            wetActive = false
            clearWet()
        }
        // Alpha rides with the SESSION (see syncLassoSession), never with the
        // armed tool: a lasso in the hand looks like any other tool until it
        // actually selects something.
        canvasAlphaForTool = isLassoSession ? 1 : 0.02
        canvas.alpha = canvasAlphaForTool
        applyInputGate()
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
        // Margins carry negative indices on purpose, so this cannot test for
        // a positive one.
        guard let partID, pageIndex != Self.unconfiguredPage else { return }
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
        let ink = InkRenderer.image(
            for: visibleDrawings, pdfSize: pdfSize, displayScale: displayScale)
        inkView.image = compositedWithClippings(ink)
    }

    /// Clippings sit under the ink — you can still write over the excerpt you
    /// taped in, exactly as you would over the engraving.
    private func compositedWithClippings(_ ink: UIImage?) -> UIImage? {
        guard let partID, pageIndex != Self.unconfiguredPage else { return ink }
        let clippings = ClippingStore.shared.clippings(partID: partID, pageIndex: pageIndex)
        guard !clippings.isEmpty else { return ink }
        let scale = displayScale
        guard scale > 0, bounds.width > 0, bounds.height > 0 else { return ink }
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { _ in
            for clipping in clippings {
                guard let image = ClippingStore.shared.image(for: clipping) else { continue }
                image.draw(in: CGRect(
                    x: clipping.x * scale, y: clipping.y * scale,
                    width: clipping.width * scale, height: clipping.height * scale))
            }
            ink?.draw(in: bounds)
        }
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
        guard scale > 0, let partID, pageIndex != Self.unconfiguredPage else { return }
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

/// The live stroke, rendered by InkRenderer — the same code that renders the
/// commit — so every style looks like itself from the first millimetre.
/// Point widths come from real pencil force, which is also what PencilKit
/// records, so pen-up refines the stroke rather than replacing its character.
final class WetStrokeView: UIView {
    private(set) var ink = PKInk(.pencil, color: .black)
    private var baseWidth: CGFloat = 3
    private var points: [PKStrokePoint] = []
    /// The predicted tail: drawn this frame, replaced by real samples the
    /// next. Never committed — prediction is where the ink is GOING.
    private var predictedPoints: [PKStrokePoint] = []

    /// The real samples only, for commit.
    var strokePoints: [PKStrokePoint] { points }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func begin(ink: PKInk, baseWidth: CGFloat, samples: [PencilObserverRecognizer.Sample]) {
        self.ink = ink
        self.baseWidth = baseWidth
        points = []
        predictedPoints = []
        append(samples: samples)
    }

    func append(samples: [PencilObserverRecognizer.Sample], predicted: [PencilObserverRecognizer.Sample] = []) {
        for sample in samples {
            points.append(makePoint(sample, index: points.count))
        }
        predictedPoints = predicted.enumerated().map { offset, sample in
            makePoint(sample, index: points.count + offset)
        }
        setNeedsDisplay()
    }

    private func makePoint(_ sample: PencilObserverRecognizer.Sample, index: Int) -> PKStrokePoint {
        // 0.6 normalized force — an ordinary writing pressure — maps to
        // exactly the nib width; light strokes thin, pressed ones swell.
        let width = max(baseWidth * (0.55 + 0.75 * sample.force), 0.5)
        return PKStrokePoint(
            location: sample.location,
            timeOffset: TimeInterval(index) * 0.01,
            size: CGSize(width: width, height: width),
            opacity: 1, force: sample.force, azimuth: 0, altitude: .pi / 2
        )
    }

    func clear() {
        points = []
        predictedPoints = []
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let all = points + predictedPoints
        guard all.count > 1, let ctx = UIGraphicsGetCurrentContext() else { return }
        var drawing = PKDrawing()
        drawing.strokes = [PKStroke(
            ink: ink,
            path: PKStrokePath(controlPoints: all, creationDate: Date())
        )]
        InkRenderer.draw(drawing, in: ctx)
    }
}
