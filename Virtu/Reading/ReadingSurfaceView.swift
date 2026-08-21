import SwiftUI
import PencilKit

struct ReadingSurfaceView: UIViewControllerRepresentable {
    @Environment(AppState.self) private var state

    func makeUIViewController(context: Context) -> ReadingPageViewController {
        let vc = ReadingPageViewController()
        vc.appState = state
        return vc
    }

    func updateUIViewController(_ vc: ReadingPageViewController, context: Context) {
        // Read the revision here so observation registers the dependency:
        // layer state lives on a SwiftData model, and mutating one does not by
        // itself re-run this update. Ink that ignores the layer you just chose
        // is a bug you would find at a rehearsal, not at a desk.
        _ = state.layerRevision
        vc.syncFromState()
    }
}

/// The reading surface: rendered pages, the turn engine, and every reading
/// gesture. Owns no chrome — SwiftUI overlays supply that.
///
/// Gesture vocabulary (fingers only; the pencil never navigates):
///  - tap left/right edge zone  -> turn (release under 150ms)
///  - hold right zone 150ms+    -> Corner Peek of the next page; release past
///                                 400ms commits the turn, earlier cancels
///  - fast horizontal swipe     -> turn
///  - two-finger double-tap     -> toggle Perform/Study
///  - two-finger single tap     -> undo (Study only)
///  - three-finger single tap   -> redo (Study only)
///  - center tap                -> toggle chrome (Study only; nothing in Perform)
///  - arrows/page keys/space    -> turn (Bluetooth pedals present as keyboards)
final class ReadingPageViewController: UIViewController {
    var appState: AppState!

    private let scrollView = UIScrollView()
    private let spreadContainer = UIView()
    private let leftPage = ReadingPageView()
    private let rightPage = ReadingPageView()
    /// Shared scratch space, keyed to the part rather than the page: what you
    /// write here beside page 1 is still here beside page 5.
    private let marginRightView = ReadingPageView()
    /// Not a surface. Empty space under the score so the page can be pushed up
    /// far enough to mark its lowest system without writing at the bezel. It
    /// is a bare UIView on purpose: a ReadingPageView here would take tools,
    /// layers, pencil input and a journal slot, which is what it used to do.
    private let bottomHeadroom = UIView()

    private var inkViews: [ReadingPageView] {
        [leftPage, rightPage, marginRightView]
    }
    private let gutterView = UIView()
    private let gutterWidth: CGFloat = 2

    private var renderer: PageRenderer?
    private var rendererPartID: UUID?

    private var displayedPageIndex = ReadingPageView.unconfiguredPage
    private var displayedPagesPerView = 0
    private var displayedAnnotating: Bool?
    private var displayedStage: Bool?

    /// Spans the pages only, so "does the score fit the screen?" can be asked
    /// without the margins answering for it.
    private let pagesGuide = UILayoutGuide()
    private var needsScrollToPage = true
    private var spreadHeightConstraint: NSLayoutConstraint!
    private var spreadHeightLimit: NSLayoutConstraint!
    private var spreadWidthLimit: NSLayoutConstraint!
    /// Aspect lives on the page, not the container: the container's size is
    /// now derived from the page plus its margins.
    private var aspectConstraint: NSLayoutConstraint?
    private var rightWidthEqual: NSLayoutConstraint!
    private var rightWidthZero: NSLayoutConstraint!

    private var lastDrawnPage: ReadingPageView?

    // Corner peek
    private var peekCard: UIImageView?
    private var pressStart: TimeInterval = 0
    private var pressStartPoint: CGPoint = .zero
    private var pressZone: Zone = .center
    private var peekTimer: Timer?

    private enum Zone { case left, center, right }

    #if DEBUG
    /// Test hook. The Perform-mode scroll lock is only observable on the scroll
    /// view itself, and it is the guard that keeps a turn from dragging the
    /// page off screen.
    var testScrollView: UIScrollView { scrollView }
    /// Test hook. Both halves of "headroom, not paper" are only checkable on
    /// the view itself: its type (never a writable surface) and its height.
    var testBottomHeadroom: UIView { bottomHeadroom }
    var testPage: UIView { leftPage }
    #endif

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(hex: 0xF2EFE8)

        setupScrollView()
        setupPages()
        setupGestures()

        NotificationCenter.default.addObserver(
            forName: .virtuUndo, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.appState.annotating else { return }
            (self.lastDrawnPage ?? self.leftPage).canvas.undoManager?.undo()
        }
        NotificationCenter.default.addObserver(
            forName: .virtuRedo, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.appState.annotating else { return }
            (self.lastDrawnPage ?? self.leftPage).canvas.undoManager?.redo()
        }
        NotificationCenter.default.addObserver(
            forName: .virtuClearHighlights, object: nil, queue: .main
        ) { [weak self] _ in
            self?.clearVisibleStrokes { $0.ink.inkType == .marker }
        }
        NotificationCenter.default.addObserver(
            forName: .virtuClearSpread, object: nil, queue: .main
        ) { [weak self] _ in
            self?.clearVisibleStrokes { _ in true }
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let target = view.bounds.width > view.bounds.height ? 2 : 1
        if appState.pagesPerView != target {
            appState.setPagesPerView(target)
        }
        syncFromState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        centerContent()
        if needsScrollToPage, leftPage.bounds.width > 0 {
            needsScrollToPage = false
            scrollToPage(animated: false)
        }
    }

    /// Put the page where the eye is: the margins sit right of and below it,
    /// out of frame until the paper is moved.
    private func scrollToPage(animated: Bool) {
        // The page block sits at the content origin now; the margins are
        // outboard right and below.
        let offset = CGPoint(
            x: -scrollView.contentInset.left,
            y: -scrollView.contentInset.top
        )
        scrollView.setContentOffset(offset, animated: animated)
        updateMarginVisibility()
    }

    // MARK: - Margin visibility

    /// The paper is sitting where a reader left it: not being dragged, not
    /// coasting, parked at the rest offset, unzoomed.
    private var isAtRest: Bool {
        guard !scrollView.isDragging, !scrollView.isDecelerating,
              scrollView.zoomScale <= 1.01 else { return false }
        let rest = CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top)
        return abs(scrollView.contentOffset.x - rest.x) < 2
            && abs(scrollView.contentOffset.y - rest.y) < 2
    }

    /// Margins exist only mid-gesture and while the paper is away from rest.
    /// In Perform they never appear at all; in Study the letterboxed sliver
    /// around the page stays clean until the musician drags toward them.
    private func updateMarginVisibility() {
        let visible = appState?.annotating == true && !isAtRest
        let targetAlpha: CGFloat = visible ? 1 : 0
        guard marginRightView.alpha != targetAlpha else { return }
        UIView.animate(withDuration: 0.15) {
            self.marginRightView.alpha = targetAlpha
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    // MARK: - Setup

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = false
        scrollView.bounces = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        // The pencil never navigates. Even if a pencil touch somehow misses
        // the canvas, it must not pan or pinch the score out from under the
        // mark being made — every other gesture here is already finger-only.
        scrollView.panGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        spreadContainer.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(spreadContainer)

        // The spread must size the scroll view's CONTENT, not its frame.
        // Pinned to frameLayoutGuide (as it was), contentSize stays equal to
        // the frame no matter the zoom scale — so a zoomed-in page has nowhere
        // to scroll to, and the bottom-right corner of the score cannot be
        // reached to write on. Content edges here; fit is expressed as limits.
        let content = scrollView.contentLayoutGuide

        // Fill the height, but never at the cost of overflowing the width:
        // the two limits are required, the fill is merely preferred.
        NSLayoutConstraint.activate([
            spreadContainer.topAnchor.constraint(equalTo: content.topAnchor),
            spreadContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            spreadContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            spreadContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        // The fit constraints measure the PAGE, not the container, so they are
        // built in setupPages() — the page does not exist yet here, and an
        // anchor pair with no common ancestor is a crash, not a warning.
    }

    private func setupPages() {
        for page in inkViews {
            page.translatesAutoresizingMaskIntoConstraints = false
            page.onCanvasUsed = { [weak self] used in
                self?.lastDrawnPage = used
                used.canvas.becomeFirstResponder()
            }
            spreadContainer.addSubview(page)
        }
        marginRightView.isMarginSurface = true
        // Invisible until the paper moves. The page letterboxes inside the
        // viewport, so at rest a sliver of margin would otherwise peek out
        // beside the score.
        marginRightView.alpha = 0

        // The headroom paints nothing. Paper below the score would read as
        // somewhere to write, and there is nowhere to write down there.
        bottomHeadroom.translatesAutoresizingMaskIntoConstraints = false
        bottomHeadroom.backgroundColor = .clear
        bottomHeadroom.isUserInteractionEnabled = false
        spreadContainer.addSubview(bottomHeadroom)

        gutterView.translatesAutoresizingMaskIntoConstraints = false
        gutterView.backgroundColor = UIColor(hex: 0xE0DBD1)
        spreadContainer.addSubview(gutterView)
        spreadContainer.addLayoutGuide(pagesGuide)

        rightWidthEqual = leftPage.widthAnchor.constraint(equalTo: rightPage.widthAnchor)
        rightWidthZero = rightPage.widthAnchor.constraint(equalToConstant: 0)

        // The chain runs margin -> pages -> container edge horizontally, and
        // pages -> margin -> container edge vertically, so the container sizes
        // itself from the page. Only the page carries an aspect ratio.
        NSLayoutConstraint.activate([
            // The margin is outboard of the last page, on the writing-hand
            // side. The page block starts flush at the container's leading
            // edge, so what you see at rest is only the score.
            leftPage.topAnchor.constraint(equalTo: spreadContainer.topAnchor),
            leftPage.leadingAnchor.constraint(equalTo: spreadContainer.leadingAnchor),

            marginRightView.topAnchor.constraint(equalTo: spreadContainer.topAnchor),
            marginRightView.leadingAnchor.constraint(equalTo: rightPage.trailingAnchor),
            marginRightView.trailingAnchor.constraint(equalTo: spreadContainer.trailingAnchor),
            marginRightView.bottomAnchor.constraint(equalTo: leftPage.bottomAnchor),
            marginRightView.widthAnchor.constraint(
                equalTo: leftPage.widthAnchor, multiplier: Tokens.marginWidthFraction),

            gutterView.topAnchor.constraint(equalTo: leftPage.topAnchor),
            gutterView.bottomAnchor.constraint(equalTo: leftPage.bottomAnchor),
            gutterView.leadingAnchor.constraint(equalTo: leftPage.trailingAnchor),
            gutterView.widthAnchor.constraint(equalToConstant: gutterWidth),

            rightPage.topAnchor.constraint(equalTo: leftPage.topAnchor),
            rightPage.bottomAnchor.constraint(equalTo: leftPage.bottomAnchor),
            rightPage.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor),

            bottomHeadroom.topAnchor.constraint(equalTo: leftPage.bottomAnchor),
            bottomHeadroom.leadingAnchor.constraint(equalTo: spreadContainer.leadingAnchor),
            bottomHeadroom.trailingAnchor.constraint(equalTo: spreadContainer.trailingAnchor),
            bottomHeadroom.bottomAnchor.constraint(equalTo: spreadContainer.bottomAnchor),
            bottomHeadroom.heightAnchor.constraint(equalToConstant: Tokens.bottomHeadroom),

            pagesGuide.leadingAnchor.constraint(equalTo: leftPage.leadingAnchor),
            pagesGuide.trailingAnchor.constraint(equalTo: rightPage.trailingAnchor),
            pagesGuide.topAnchor.constraint(equalTo: leftPage.topAnchor),
            pagesGuide.bottomAnchor.constraint(equalTo: leftPage.bottomAnchor),
        ])

        // Fit is measured against the PAGE, not the container. The shared
        // margins hang off the container outside the viewport, so they cost
        // the score no size at all — you reach them by moving the paper.
        // Full bleed in BOTH modes: the page is the screen, and the mode
        // switch must not resize the score. Chrome, the tool rail and the
        // scrubber all overlay it as visitors — the right margin is why that
        // costs nothing, since the score can be moved out from under them.
        spreadHeightConstraint = leftPage.heightAnchor.constraint(
            equalTo: scrollView.frameLayoutGuide.heightAnchor)
        spreadHeightConstraint.priority = .defaultHigh
        spreadHeightLimit = leftPage.heightAnchor.constraint(
            lessThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor)
        spreadWidthLimit = pagesGuide.widthAnchor.constraint(
            lessThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor)
        NSLayoutConstraint.activate([
            spreadHeightConstraint, spreadHeightLimit, spreadWidthLimit,
        ])
    }

    private func setupGestures() {
        // Press tracker: zones, instant turns, and Corner Peek in one recognizer.
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0
        press.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        press.cancelsTouchesInView = false
        press.delegate = self
        view.addGestureRecognizer(press)

        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeLeft.direction = .left
        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeRight.direction = .right
        for swipe in [swipeLeft, swipeRight] {
            swipe.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            swipe.delegate = self
            view.addGestureRecognizer(swipe)
        }

        let modeTap = UITapGestureRecognizer(target: self, action: #selector(handleModeTap))
        modeTap.numberOfTapsRequired = 2
        modeTap.numberOfTouchesRequired = 2
        modeTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        view.addGestureRecognizer(modeTap)

        let undoTap = UITapGestureRecognizer(target: self, action: #selector(handleUndoTap))
        undoTap.numberOfTapsRequired = 1
        undoTap.numberOfTouchesRequired = 2
        undoTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        undoTap.require(toFail: modeTap)
        view.addGestureRecognizer(undoTap)

        let redoTap = UITapGestureRecognizer(target: self, action: #selector(handleRedoTap))
        redoTap.numberOfTapsRequired = 1
        redoTap.numberOfTouchesRequired = 3
        redoTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        view.addGestureRecognizer(redoTap)
    }

    // MARK: - State sync

    func syncFromState() {
        guard isViewLoaded, let state = appState else { return }

        if state.currentPart?.id != rendererPartID {
            rendererPartID = state.currentPart?.id
            renderer = state.currentPart.flatMap { PageRenderer(url: $0.pdfURL) }
            displayedPageIndex = ReadingPageView.unconfiguredPage
            configureMargins(partID: state.currentPart?.id)
            needsScrollToPage = true
        }
        guard let renderer else { return }

        let annotating = state.annotating
        if annotating != displayedAnnotating {
            displayedAnnotating = annotating
            applyModeChange(annotating: annotating)
        }

        let stage = state.stageMode
        if stage != displayedStage {
            displayedStage = stage
            displayedPageIndex = ReadingPageView.unconfiguredPage   // force page image refresh
            view.backgroundColor = stage ? UIColor(hex: 0x0A0908) : UIColor(hex: 0xF2EFE8)
            gutterView.backgroundColor = stage ? UIColor(hex: 0x25211C) : UIColor(hex: 0xE0DBD1)
            for page in [leftPage, rightPage] {
                page.backgroundColor = stage ? UIColor(hex: 0x0A0908) : UIColor(hex: 0xFFFDF8)
                page.layer.borderColor = (stage ? UIColor(hex: 0x25211C) : UIColor(hex: 0xE0DBD1)).cgColor
            }
            // The same paper as the page. A margin shaded like a desk reads
            // as scenery; blank paper reads as somewhere to write, which is
            // the entire reason it is there. The bottom headroom gets none of
            // this: it is not a surface, so it stays the ground behind it.
            marginRightView.backgroundColor = stage ? UIColor(hex: 0x0A0908) : UIColor(hex: 0xFFFDF8)
            marginRightView.layer.borderColor =
                (stage ? UIColor(hex: 0x25211C) : UIColor(hex: 0xE0DBD1)).cgColor
        }

        applyToolState()
        applyInputMode()
        applyLayerState()
        updateAspect(renderer: renderer)

        if state.pageIndex != displayedPageIndex || state.pagesPerView != displayedPagesPerView {
            let direction = state.pageIndex >= displayedPageIndex ? 1 : -1
            let firstDisplay = displayedPageIndex == ReadingPageView.unconfiguredPage
                || state.pagesPerView != displayedPagesPerView
            displayedPageIndex = state.pageIndex
            displayedPagesPerView = state.pagesPerView
            updatePages(renderer: renderer, animated: !firstDisplay, direction: direction)
        }
    }

    private func applyModeChange(annotating: Bool) {
        if !annotating {
            scrollView.setZoomScale(1, animated: false)
            leftPage.canvas.resignFirstResponder()
            rightPage.canvas.resignFirstResponder()
            becomeFirstResponder()
        }
        // Re-park on EVERY mode change, after the new reserves have resolved
        // into real insets — the rest offset is derived from them, and a page
        // left where the other mode parked it sits under the Study chrome
        // (entering) or shy of full bleed (leaving).
        view.layoutIfNeeded()
        centerContent()
        scrollToPage(animated: false)
        scrollView.pinchGestureRecognizer?.isEnabled = annotating
        // Panning is Study-only: it is how you reach the shared margins, and
        // in Perform a stray drag must never shift the page a player is
        // reading from.
        //
        // This has to be `isScrollEnabled`, not `panGestureRecognizer.isEnabled`.
        // UIScrollView owns that recognizer and re-enables it behind us, so the
        // lock silently came undone: in Perform a turn swipe both turned the
        // page AND dragged the paper a full page-width sideways, parking the
        // viewport over the (invisible) right margin. The score read as blank
        // from page 2 on, which is the worst possible failure on a stand.
        scrollView.isScrollEnabled = annotating
        updateMarginVisibility()
    }

    /// Keep a spread smaller than the viewport centred, and let a zoomed one
    /// reach its own edges. Inset-based centring (not centre constraints) is
    /// what leaves the corners reachable once contentSize exceeds the frame.
    private func centerContent() {
        let bounds = scrollView.bounds.size
        let content = scrollView.contentSize
        guard bounds.width > 0, content.width > 0 else { return }
        let x = max(0, (bounds.width - content.width) / 2)
        let extraY = max(0, bounds.height - content.height)
        let inset = UIEdgeInsets(top: extraY / 2, left: x, bottom: extraY / 2, right: x)
        if scrollView.contentInset != inset {
            scrollView.contentInset = inset
        }
    }

    private func applyToolState() {
        let tool = appState.currentPKTool()
        inkViews.forEach { $0.apply(tool: tool) }
    }

    /// The margin is configured once per part and never again — that is the
    /// whole point of it. Its coordinate space is fixed, so that rotating the
    /// iPad rescales the ink rather than reflowing it onto different notes.
    private func configureMargins(partID: UUID?) {
        guard let renderer else { return }
        let page = renderer.pageSize
        marginRightView.configure(
            partID: partID,
            pageIndex: AnnotationLayers.marginRightIndex,
            pdfSize: CGSize(width: page.width * Tokens.marginWidthFraction, height: page.height)
        )
        // Nothing to configure below the score: the headroom holds no ink and
        // owns no coordinate space.
    }

    /// Push the part's layer state onto both pages. Idempotent by design —
    /// this runs on every sync.
    private func applyLayerState() {
        let active = appState.activeLayer
        let visible = appState.visibleLayers
        inkViews.forEach { $0.setLayers(active: active, visible: visible) }
    }

    /// Single owner of the canvases' input gate: the pencil draws in Study.
    private func applyInputMode() {
        inkViews.forEach { $0.annotationEnabled = appState.annotating }
    }

    private func updateAspect(renderer: PageRenderer) {
        let multiplier = renderer.pageSize.width / max(renderer.pageSize.height, 1)

        if let existing = aspectConstraint, abs(existing.multiplier - multiplier) < 0.001 {
            applySpreadLayout(perView: appState.pagesPerView)
            return
        }
        aspectConstraint?.isActive = false
        // On the page itself: the container's size falls out of the page plus
        // its margins, so an aspect on the container would fight them.
        aspectConstraint = leftPage.widthAnchor.constraint(
            equalTo: leftPage.heightAnchor, multiplier: multiplier)
        aspectConstraint?.isActive = true
        applySpreadLayout(perView: appState.pagesPerView)
    }

    private func applySpreadLayout(perView: Int) {
        if perView == 2 {
            rightWidthZero.isActive = false
            rightWidthEqual.isActive = true
            gutterView.isHidden = false
            rightPage.isHidden = false
        } else {
            rightWidthEqual.isActive = false
            rightWidthZero.isActive = true
            gutterView.isHidden = true
            rightPage.isHidden = true
        }
    }

    private func updatePages(renderer: PageRenderer, animated: Bool, direction: Int) {
        let state = appState!
        let height = max(leftPage.bounds.height, view.bounds.height)
        let stage = state.stageMode

        let apply = { [weak self] in
            guard let self else { return }
            let idx = state.pageIndex
            self.setPage(self.leftPage, renderer: renderer, index: idx, height: height, stage: stage)
            if state.pagesPerView == 2 {
                self.setPage(self.rightPage, renderer: renderer, index: idx + 1, height: height, stage: stage)
            }
            renderer.prefetch(around: idx, span: state.pagesPerView + 1, height: height, stage: stage)
        }

        guard animated, let snapshot = spreadContainer.snapshotView(afterScreenUpdates: false) else {
            apply()
            return
        }

        // 90ms crossfade with a 4pt directional micro-offset — a flick, not a journey.
        snapshot.frame = spreadContainer.frame
        scrollView.addSubview(snapshot)
        apply()
        spreadContainer.transform = CGAffineTransform(translationX: CGFloat(direction) * 4, y: 0)
        UIView.animate(withDuration: 0.09, delay: 0, options: [.curveEaseOut]) {
            snapshot.alpha = 0
            self.spreadContainer.transform = .identity
        } completion: { _ in
            snapshot.removeFromSuperview()
        }
    }

    private func setPage(_ pageView: ReadingPageView, renderer: PageRenderer, index: Int, height: CGFloat, stage: Bool) {
        guard index >= 0, index < renderer.pageCount else {
            pageView.isHidden = true
            return
        }
        pageView.isHidden = false
        pageView.configure(partID: appState.currentPart?.id, pageIndex: index, pdfSize: renderer.pageSize)

        if let cached = renderer.image(at: index, height: height, stage: stage, completion: { [weak pageView] image in
            guard let pageView, pageView.pageIndex == index else { return }
            pageView.imageView.image = image
        }) {
            pageView.imageView.image = cached
        } else if let now = renderer.imageNow(at: index, height: height, stage: stage) {
            pageView.imageView.image = now
        }
    }

    // MARK: - Turns

    private func turn(_ direction: Int, hapticAllowed: Bool) {
        let state = appState!
        let prevPart = state.currentPart?.id
        let prevPage = state.pageIndex
        state.turn(direction)   // handles clamping and cross-piece program flow
        guard state.currentPart?.id != prevPart || state.pageIndex != prevPage else { return }
        if hapticAllowed && state.annotating {
            Haptics.selection()
        }
        syncFromState()
    }

    // MARK: - Gestures

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        guard scrollView.zoomScale <= 1.01 else { return }
        let location = gesture.location(in: view)
        let width = view.bounds.width

        switch gesture.state {
        case .began:
            pressStart = CACurrentMediaTime()
            pressStartPoint = location
            pressZone = location.x < width * 0.2 ? .left : (location.x > width * 0.8 ? .right : .center)
            if pressZone == .right {
                schedulePeek()
            }
        case .ended:
            peekTimer?.invalidate()
            let dt = CACurrentMediaTime() - pressStart
            let moved = hypot(location.x - pressStartPoint.x, location.y - pressStartPoint.y) > 12
            defer { dismissPeek() }
            guard !moved else { return }

            // A quick touch near the top summons the score info, in BOTH
            // modes — the one thing the title chrome is for. Edge zones keep
            // their corners for turning.
            if pressZone == .center, dt < 0.3,
               location.y < view.bounds.height * Tokens.chromeSummonBand {
                appState.chromeVisible = true
                return
            }

            switch pressZone {
            case .left:
                if dt < 0.3 { turn(-1, hapticAllowed: true) }
            case .right:
                if dt < 0.15 {
                    turn(1, hapticAllowed: true)
                } else if dt >= 0.4 {
                    turn(1, hapticAllowed: true)   // peek commit
                }
                // 0.15–0.4s: peek cancel, free
            case .center:
                if appState.annotating {
                    if dt < 0.3 { appState.toggleChrome() }
                } else if dt >= 0.5 {
                    // Perform: center tap does nothing, but a deliberate
                    // long-press summons temporary chrome (scrubber + mode
                    // pill) — the discoverable way out of Perform.
                    appState.chromeVisible = true
                }
            }
        case .cancelled, .failed:
            peekTimer?.invalidate()
            dismissPeek()
        default:
            break
        }
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard scrollView.zoomScale <= 1.01 else { return }
        // In Study a horizontal drag moves the paper to reach the margin, so
        // it cannot also turn the page. Edge taps, the pedal and the scrubber
        // still turn in both modes; swipe stays a Perform gesture.
        guard !appState.annotating else { return }
        turn(gesture.direction == .left ? 1 : -1, hapticAllowed: false)
    }

    @objc private func handleModeTap() {
        Haptics.medium()
        appState.toggleMode()
        syncFromState()
    }

    @objc private func handleUndoTap() {
        guard appState.annotating else { return }
        (lastDrawnPage ?? leftPage).canvas.undoManager?.undo()
        Haptics.rigid()
    }

    @objc private func handleRedoTap() {
        guard appState.annotating else { return }
        (lastDrawnPage ?? leftPage).canvas.undoManager?.redo()
        Haptics.rigid()
    }


    // MARK: - Scoped erase

    private func clearVisibleStrokes(_ shouldRemove: @escaping (PKStroke) -> Bool) {
        guard appState.annotating else { return }
        for page in [leftPage, rightPage] where !page.isHidden {
            page.removeStrokes(where: shouldRemove)
            lastDrawnPage = page
        }
        Haptics.rigid()
    }

    // MARK: - Corner Peek

    private func schedulePeek() {
        peekTimer?.invalidate()
        peekTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            self?.showPeek()
        }
    }

    private func showPeek() {
        guard peekCard == nil, let renderer else { return }
        let state = appState!
        let nextIndex = state.pageIndex + state.pagesPerView
        guard nextIndex < state.pageCount else { return }

        let height = max(spreadContainer.bounds.height, 400)
        guard let image = renderer.imageNow(at: nextIndex, height: height, stage: state.stageMode) else { return }

        let cardWidth = spreadContainer.bounds.width * (state.pagesPerView == 2 ? 0.5 : 1) * 0.15
        let aspect = renderer.pageSize.height / max(renderer.pageSize.width, 1)
        let card = UIImageView(image: image)
        card.contentMode = .scaleAspectFit
        card.layer.cornerRadius = 8
        card.clipsToBounds = true
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(hex: 0xE0DBD1).cgColor
        card.alpha = 0
        let size = CGSize(width: cardWidth, height: cardWidth * aspect)
        card.frame = CGRect(
            x: view.bounds.width - size.width - 24,
            y: view.bounds.height - size.height - 24,
            width: size.width,
            height: size.height
        )
        card.transform = CGAffineTransform(translationX: 12, y: 0)
        view.addSubview(card)
        peekCard = card

        UIView.animate(withDuration: 0.14, delay: 0, options: [.curveEaseOut]) {
            card.alpha = 0.92
            card.transform = .identity
        }
    }

    private func dismissPeek() {
        guard let card = peekCard else { return }
        peekCard = nil
        UIView.animate(withDuration: 0.18, animations: {
            card.alpha = 0
        }, completion: { _ in
            card.removeFromSuperview()
        })
    }

    // MARK: - Keyboard / pedal

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        let next = [UIKeyCommand.inputRightArrow, UIKeyCommand.inputDownArrow, UIKeyCommand.inputPageDown, " "]
        let prev = [UIKeyCommand.inputLeftArrow, UIKeyCommand.inputUpArrow, UIKeyCommand.inputPageUp]

        return next.map { input in
            let cmd = UIKeyCommand(input: input, modifierFlags: [], action: #selector(keyNext))
            cmd.wantsPriorityOverSystemBehavior = true
            return cmd
        } + prev.map { input in
            let cmd = UIKeyCommand(input: input, modifierFlags: [], action: #selector(keyPrev))
            cmd.wantsPriorityOverSystemBehavior = true
            return cmd
        }
    }

    @objc private func keyNext() { turn(1, hapticAllowed: false) }
    @objc private func keyPrev() { turn(-1, hapticAllowed: false) }
}

// MARK: - UIScrollViewDelegate

extension ReadingPageViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        appState.annotating ? spreadContainer : nil
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        updateMarginVisibility()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // The margins fade in as the drag starts, so pulling the paper aside
        // reveals paper rather than a void that pops filled at gesture end.
        updateMarginVisibility()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateMarginVisibility()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { updateMarginVisibility() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateMarginVisibility()
    }
}

// MARK: - UIGestureRecognizerDelegate

extension ReadingPageViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
