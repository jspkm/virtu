import XCTest
import PencilKit
@testable import Virtu

/// Regression suite for the ink pipeline. Every bug class found on hardware
/// gets a test here; changes to the reading/ink surface must pass these
/// before being declared done.
final class VirtuInkTests: XCTestCase {

    // MARK: - Helpers

    private func makeStroke(
        from: CGPoint, to: CGPoint,
        width: CGFloat = 3, color: UIColor = .black,
        ink: PKInkingTool.InkType = .pencil
    ) -> PKStroke {
        let points = stride(from: 0.0, through: 1.0, by: 0.1).map { t in
            PKStrokePoint(
                location: CGPoint(
                    x: from.x + (to.x - from.x) * t,
                    y: from.y + (to.y - from.y) * t
                ),
                timeOffset: t,
                size: CGSize(width: width, height: width),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            )
        }
        return PKStroke(
            ink: PKInk(ink, color: color),
            path: PKStrokePath(controlPoints: points, creationDate: Date())
        )
    }

    private func makeDrawing(_ strokes: [PKStroke]) -> PKDrawing {
        var drawing = PKDrawing()
        drawing.strokes = strokes
        return drawing
    }

    /// Bounding box of non-transparent pixels, in image points.
    private func inkPixelBounds(of image: UIImage) -> CGRect? {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return nil }
        let w = cg.width, h = cg.height
        let bpr = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                // Any nonzero channel in the pixel counts as ink.
                let p = y * bpr + x * bpp
                if bytes[p] != 0 || bytes[p + 1] != 0 || bytes[p + 2] != 0 || (bpp > 3 && bytes[p + 3] != 0) {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        let scale = image.scale
        return CGRect(
            x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
            width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale
        )
    }

    /// How many pixels carry ink. Dashes are the difference between a line
    /// and a row of dots, and nothing else in the pipeline can prove it.
    private func inkPixelCount(of image: UIImage) -> Int {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return 0 }
        let w = cg.width, h = cg.height
        let bpr = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
        var count = 0
        for y in 0..<h {
            for x in 0..<w where bpp > 3 && bytes[y * bpr + x * bpp + 3] != 0 {
                count += 1
            }
        }
        return count
    }

    /// A laid-out page view at 1:1 PDF scale, hosted in a window.
    private func makePageView(partID: UUID = UUID()) -> ReadingPageView {
        let pdfSize = CGSize(width: 612, height: 792)
        let page = ReadingPageView(frame: CGRect(origin: .zero, size: pdfSize))
        let window = UIWindow(frame: CGRect(origin: .zero, size: pdfSize))
        window.addSubview(page)
        page.configure(partID: partID, pageIndex: 0, pdfSize: pdfSize)
        page.layoutIfNeeded()
        return page
    }

    /// A private defaults store per test. Tool settings persist now, so a
    /// shared one lets any test that sets a colour decide what every other
    /// test sees.
    static func scratchDefaults() -> UserDefaults {
        let name = "virtu.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name) ?? .standard
    }

    private func waitForJournal() {
        // StrokeJournal writes on a background queue.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.6))
    }

    // MARK: - Rendering: ink must be visible

    func testInkRendererDrawsVisibleStrokes() {
        let drawing = makeDrawing([makeStroke(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 200, y: 200))])
        let image = InkRenderer.image(for: drawing, pdfSize: CGSize(width: 612, height: 792), displayScale: 1)
        XCTAssertNotNil(image, "renderer produced no image for a non-empty drawing")
        XCTAssertNotNil(inkPixelBounds(of: image!), "rendered image contains no visible ink pixels")
    }

    // MARK: - Rendering: ink must be WHERE the stroke is (offset bug class)

    func testInkRendererPositionMatchesStrokeBounds() throws {
        let stroke = makeStroke(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 200, y: 260))
        let drawing = makeDrawing([stroke])
        let scale: CGFloat = 1.5
        let image = try XCTUnwrap(InkRenderer.image(for: drawing, pdfSize: CGSize(width: 612, height: 792), displayScale: scale))
        let bounds = try XCTUnwrap(inkPixelBounds(of: image))

        let expected = CGRect(x: 100 * scale, y: 200 * scale, width: 100 * scale, height: 60 * scale)
        let tolerance: CGFloat = 8   // round caps + antialiasing
        XCTAssertEqual(bounds.minX, expected.minX, accuracy: tolerance, "ink shifted horizontally")
        XCTAssertEqual(bounds.minY, expected.minY, accuracy: tolerance, "ink shifted vertically")
        XCTAssertEqual(bounds.maxX, expected.maxX, accuracy: tolerance)
        XCTAssertEqual(bounds.maxY, expected.maxY, accuracy: tolerance)
    }

    /// THE offset bug: `PKDrawing.transformed(using:)` stores scaling in each
    /// stroke's `transform`, not in its points. A renderer that ignores the
    /// transform draws every stroke shrunk toward the origin — marks land
    /// above/left of the pencil. The previous position test missed this
    /// because its strokes had identity transforms.
    func testInkRendererHonorsStrokeTransform() throws {
        let stroke = makeStroke(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 200, y: 260))
        let base = makeDrawing([stroke])

        // Exactly what ReadingPageView does when displaying at page scale.
        let displayScale: CGFloat = 0.8774509803921569
        let transformed = base.transformed(using: CGAffineTransform(scaleX: displayScale, y: displayScale))
        XCTAssertNotEqual(transformed.strokes.first?.transform, .identity, "precondition: transformed() must carry a stroke transform")

        let image = try XCTUnwrap(InkRenderer.image(for: transformed, pdfSize: CGSize(width: 612, height: 792), displayScale: 1))
        let bounds = try XCTUnwrap(inkPixelBounds(of: image))

        // Ink must land at the TRANSFORMED position, not the raw point positions.
        let expected = CGRect(
            x: 100 * displayScale, y: 200 * displayScale,
            width: 100 * displayScale, height: 60 * displayScale
        )
        XCTAssertEqual(bounds.minX, expected.minX, accuracy: 8, "stroke transform ignored: ink shifted horizontally toward the origin")
        XCTAssertEqual(bounds.minY, expected.minY, accuracy: 8, "stroke transform ignored: ink shifted vertically toward the origin")
        XCTAssertEqual(bounds.maxX, expected.maxX, accuracy: 8)
        XCTAssertEqual(bounds.maxY, expected.maxY, accuracy: 8)
    }

    /// The full display path: master (PDF space) → page view at device scale →
    /// rendered ink must sit where the master says, in view coordinates.
    func testPageViewRendersInkAtCorrectViewPosition() throws {
        let partID = UUID()
        let pdfSize = CGSize(width: 612, height: 792)
        let page = ReadingPageView(frame: CGRect(x: 0, y: 0, width: 537, height: 696))  // real device geometry
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 537, height: 696))
        window.addSubview(page)
        page.configure(partID: partID, pageIndex: 0, pdfSize: pdfSize)
        page.layoutIfNeeded()

        let scale = 537.0 / 612.0
        page.canvas.drawing = makeDrawing([makeStroke(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 200, y: 200))])
            .transformed(using: CGAffineTransform(scaleX: scale, y: scale))
        page.canvasViewDrawingDidChange(page.canvas)
        page.layoutIfNeeded()

        let image = try XCTUnwrap(page.inkView.image, "no committed ink image")
        let bounds = try XCTUnwrap(inkPixelBounds(of: image))
        // Image is in view points; the stroke was drawn at view x≈87.7..175
        XCTAssertEqual(bounds.minX, 100 * scale, accuracy: 10, "committed ink not under where the pencil drew")
        XCTAssertEqual(bounds.minY, 200 * scale, accuracy: 10, "committed ink not under where the pencil drew")
    }

    // MARK: - Input space: the canvas must be inset-free (above-the-tip bug)

    func testCanvasHasNoContentInsetOrOffset() {
        let page = makePageView()
        XCTAssertEqual(page.canvas.contentOffset, .zero, "canvas content offset shifts recorded strokes away from the pencil tip")
        XCTAssertEqual(page.canvas.adjustedContentInset, .zero, "safe-area inset adjustment displaces recorded strokes")
        XCTAssertEqual(page.canvas.contentInsetAdjustmentBehavior, .never)
    }

    // MARK: - Round trip: what you draw is what persists, where you drew it

    func testDrawingRoundTripPreservesGeometry() throws {
        let partID = UUID()
        let page = makePageView(partID: partID)
        let stroke = makeStroke(from: CGPoint(x: 150, y: 300), to: CGPoint(x: 250, y: 320))
        page.canvas.drawing = makeDrawing([stroke])

        page.canvasViewDrawingDidChange(page.canvas)
        waitForJournal()

        let saved = try XCTUnwrap(StrokeJournal.shared.load(partID: partID, pageIndex: 0, layer: AnnotationLayers.first))
        XCTAssertEqual(saved.strokes.count, 1)
        let savedBounds = saved.bounds
        XCTAssertEqual(savedBounds.minX, 150, accuracy: 4, "persisted stroke drifted horizontally")
        XCTAssertEqual(savedBounds.minY, 300, accuracy: 4, "persisted stroke drifted vertically")
    }

    // MARK: - Lasso ghost: the change callback must not touch the canvas

    func testDidChangeDoesNotMutateCanvasDrawing() {
        let page = makePageView()
        let drawing = makeDrawing([
            makeStroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 150, y: 100)),
            makeStroke(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 250, y: 200)),
        ])
        page.canvas.drawing = drawing

        page.canvasViewDrawingDidChange(page.canvas)

        XCTAssertEqual(
            page.canvas.drawing.strokes.count, 2,
            "didChange mutated the canvas drawing — this destroys PencilKit's in-flight lasso selection and duplicates moved strokes"
        )
    }

    func testStrokeRemovalPersists() throws {
        let partID = UUID()
        let page = makePageView(partID: partID)
        page.canvas.drawing = makeDrawing([
            makeStroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 150, y: 100)),
            makeStroke(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 250, y: 200)),
        ])
        page.canvasViewDrawingDidChange(page.canvas)
        waitForJournal()

        // Simulate an erase: one stroke removed interactively.
        var reduced = page.canvas.drawing
        reduced.strokes.removeFirst()
        page.canvas.drawing = reduced
        page.canvasViewDrawingDidChange(page.canvas)
        waitForJournal()

        let saved = try XCTUnwrap(StrokeJournal.shared.load(partID: partID, pageIndex: 0, layer: AnnotationLayers.first))
        XCTAssertEqual(saved.strokes.count, 1, "removed stroke was resurrected in the journal")
    }

    // MARK: - Tool model: the pencil must be legible

    func testPencilToolIsLegible() throws {
        let state = AppState()
        state.tool = .pencil
        let tool = try XCTUnwrap(state.currentPKTool() as? PKInkingTool)
        XCTAssertGreaterThanOrEqual(tool.width, 3, "pencil too thin to read from a stand")
        var alpha: CGFloat = 0
        tool.color.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        XCTAssertGreaterThanOrEqual(alpha, 0.9, "pencil ink too faint")
    }

    func testStageFlipsDefaultGraphiteToLight() throws {
        let state = AppState(defaults: Self.scratchDefaults())
        state.tool = .pencil
        state.toolColors[.pencil] = AppState.graphiteHex
        state.stageMode = true
        let tool = try XCTUnwrap(state.currentPKTool() as? PKInkingTool)
        var white: CGFloat = 0
        tool.color.getWhite(&white, alpha: nil)
        XCTAssertGreaterThan(white, 0.6, "default graphite must flip light in Stage or it vanishes on the black page")
    }

    // MARK: - Display ownership (lasso-ghost bug class, round 2)
    //
    // The on-device duplicate came from two renderers disagreeing: PencilKit's
    // interactive layer vs our committed ink layer. These tests pin the
    // ownership state machine. The interactive lasso drag itself cannot be
    // driven programmatically — that path stays hand-verified — but the
    // states that made the ghost possible are locked down here.

    func testToolApplicationIsIdempotent() {
        let page = makePageView()
        let state = AppState()
        state.tool = .pencil
        page.apply(tool: state.currentPKTool())
        let after = page.toolAssignments
        // Repeated syncs with an unchanged tool must NOT reassign — mid-gesture
        // reassignment cancels PencilKit's in-flight stroke or selection.
        page.apply(tool: state.currentPKTool())
        page.apply(tool: state.currentPKTool())
        XCTAssertEqual(page.toolAssignments, after, "unchanged tool was reassigned; a UI-timer sync mid-lasso would cancel the selection")
        state.tool = .eraser
        page.apply(tool: state.currentPKTool())
        XCTAssertEqual(page.toolAssignments, after + 1, "a genuine tool change must reassign")
    }

    func testInkLayerHiddenDuringLassoSession() {
        let page = makePageView()
        page.apply(tool: PKLassoTool())
        XCTAssertTrue(page.inkView.isHidden, "during a lasso session PencilKit owns the display; a visible ink layer ghosts the pre-move positions")
        page.apply(tool: PKInkingTool(.pencil, color: .black, width: 3))
        XCTAssertFalse(page.inkView.isHidden, "leaving lasso must hand display back to the ink layer")
    }

    func testCanvasNormalizesAfterGestureNotDuring() {
        let page = makePageView()
        page.canvas.drawing = makeDrawing([makeStroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 40, y: 10))])
        let before = page.canvasNormalizations

        page.setPencilDown(true)
        page.canvasViewDrawingDidChange(page.canvas)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        XCTAssertEqual(page.canvasNormalizations, before, "canvas must never be re-set while the pencil is down — it destroys in-flight PencilKit state")

        page.setPencilDown(false)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        XCTAssertGreaterThan(page.canvasNormalizations, before, "after the gesture ends the canvas must normalize so the ink layer becomes sole display owner")
    }

    func testLeavingLassoNormalizesCanvas() {
        let page = makePageView()
        page.apply(tool: PKLassoTool())
        let before = page.canvasNormalizations
        page.apply(tool: PKInkingTool(.pencil, color: .black, width: 3))
        XCTAssertGreaterThan(page.canvasNormalizations, before, "leaving a lasso session must normalize the canvas to blank PencilKit's layer")
    }

    // MARK: - Journal

    func testJournalRoundTrip() throws {
        let partID = UUID()
        let drawing = makeDrawing([makeStroke(from: CGPoint(x: 50, y: 60), to: CGPoint(x: 90, y: 60))])
        StrokeJournal.shared.save(drawing, partID: partID, pageIndex: 3, layer: AnnotationLayers.first, pageSize: CGSize(width: 595, height: 842))
        waitForJournal()

        let loaded = try XCTUnwrap(StrokeJournal.shared.load(partID: partID, pageIndex: 3, layer: AnnotationLayers.first))
        // PKDrawing serialization is not byte-stable across round-trips;
        // compare geometry and ink instead.
        XCTAssertEqual(loaded.strokes.count, drawing.strokes.count)
        XCTAssertEqual(loaded.bounds.minX, drawing.bounds.minX, accuracy: 0.5)
        XCTAssertEqual(loaded.bounds.minY, drawing.bounds.minY, accuracy: 0.5)
        XCTAssertEqual(loaded.bounds.width, drawing.bounds.width, accuracy: 1)
        XCTAssertEqual(loaded.bounds.height, drawing.bounds.height, accuracy: 1)
        XCTAssertEqual(loaded.strokes.first?.ink.inkType, drawing.strokes.first?.ink.inkType)
    }

    // MARK: - Layers
    //
    // The promise is "hide a layer and it is safe." Every test here defends a
    // way that promise could quietly stop being true.

    func testLayersPersistIndependently() throws {
        let partID = UUID()
        let page = makePageView(partID: partID)

        page.canvas.drawing = makeDrawing([makeStroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 160, y: 100))])
        page.canvasViewDrawingDidChange(page.canvas)
        waitForJournal()

        page.setLayers(active: 2, visible: [1, 2])
        page.canvas.drawing = makeDrawing([
            makeStroke(from: CGPoint(x: 300, y: 400), to: CGPoint(x: 360, y: 400)),
            makeStroke(from: CGPoint(x: 300, y: 440), to: CGPoint(x: 360, y: 440)),
        ])
        page.canvasViewDrawingDidChange(page.canvas)
        waitForJournal()

        let one = try XCTUnwrap(StrokeJournal.shared.load(partID: partID, pageIndex: 0, layer: 1))
        let two = try XCTUnwrap(StrokeJournal.shared.load(partID: partID, pageIndex: 0, layer: 2))
        XCTAssertEqual(one.strokes.count, 1, "layer 1 was overwritten by ink meant for layer 2")
        XCTAssertEqual(two.strokes.count, 2)
        XCTAssertEqual(one.bounds.minY, 100, accuracy: 4)
        XCTAssertEqual(two.bounds.minY, 400, accuracy: 4)
    }

    func testActiveLayerIsTheOnlyOneHandedToTheCanvas() {
        let page = makePageView()
        page.canvas.drawing = makeDrawing([makeStroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 160, y: 100))])
        page.canvasViewDrawingDidChange(page.canvas)

        page.setLayers(active: 2, visible: [1, 2])

        XCTAssertEqual(
            page.canvas.drawing.strokes.count, 0,
            "switching layers left the previous layer's ink in the canvas — erase and lasso would reach it"
        )
    }

    func testEraseCannotReachAnotherLayer() throws {
        let partID = UUID()
        let page = makePageView(partID: partID)

        page.canvas.drawing = makeDrawing([makeStroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 160, y: 100))])
        page.canvasViewDrawingDidChange(page.canvas)
        waitForJournal()

        page.setLayers(active: 2, visible: [1, 2])
        page.canvas.drawing = makeDrawing([makeStroke(from: CGPoint(x: 300, y: 400), to: CGPoint(x: 360, y: 400))])
        page.canvasViewDrawingDidChange(page.canvas)
        waitForJournal()

        // "Clear this spread" while layer 2 is active.
        page.removeStrokes { _ in true }
        waitForJournal()

        let one = try XCTUnwrap(StrokeJournal.shared.load(partID: partID, pageIndex: 0, layer: 1))
        XCTAssertEqual(one.strokes.count, 1, "an erase on layer 2 destroyed ink on layer 1")
        let two = StrokeJournal.shared.load(partID: partID, pageIndex: 0, layer: 2)
        XCTAssertEqual(two?.strokes.count ?? 0, 0)
    }

    func testHidingEveryLayerLeavesACleanPage() {
        let page = makePageView()
        page.canvas.drawing = makeDrawing([makeStroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 160, y: 100))])
        page.canvasViewDrawingDidChange(page.canvas)
        XCTAssertNotNil(page.inkView.image, "precondition: ink is on the page")

        page.setLayers(active: 1, visible: [])

        XCTAssertNil(page.inkView.image, "hidden layers still rendered — the clean-score promise is broken")
    }

    func testHidingALayerAlsoBlanksTheCanvas() {
        // Found on hardware: hiding a layer cleared the older marks but left
        // the freshly-written ones on screen. Re-rendering our ink layer is
        // not enough — PencilKit is still lighting the strokes it drew
        // interactively, and it is a second renderer with its own opinion.
        let page = makePageView()
        page.annotationEnabled = true
        page.canvas.drawing = makeDrawing([makeStroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 160, y: 100))])
        page.canvasViewDrawingDidChange(page.canvas)
        XCTAssertEqual(page.canvas.drawing.strokes.count, 1, "precondition: the canvas holds the ink")

        page.setLayers(active: 1, visible: [])

        XCTAssertEqual(
            page.canvas.drawing.strokes.count, 0,
            "hiding a layer left ink in PencilKit's canvas, which keeps drawing what our ink layer no longer does"
        )
        XCTAssertFalse(
            page.canvas.drawingGestureRecognizer.isEnabled,
            "a hidden active layer still accepted ink — the pencil would write into something invisible"
        )
    }

    func testCanvasAcceptsPencilTouchesWheneverItShould() {
        // The regression this pins: an attempt to keep fingers off the canvas
        // via hitTest rejected pencil touches at random, so marks died
        // mid-stroke and the escaped touches panned the score. The canvas must
        // be fully live whenever Study is open and the active layer is visible.
        let page = makePageView()
        page.setLayers(active: 1, visible: [1])
        page.annotationEnabled = true

        XCTAssertTrue(page.canvas.isUserInteractionEnabled, "the canvas cannot receive the pencil")
        XCTAssertTrue(page.canvas.drawingGestureRecognizer.isEnabled)
        XCTAssertNotNil(
            page.canvas.hitTest(CGPoint(x: 100, y: 100), with: nil),
            "the canvas refuses touches at the point of a mark"
        )
    }

    func testPerformModeCanvasTakesNoTouchesAtAll() {
        // No touches means no long press, and so no "Select All / Insert
        // Space" over music somebody is reading.
        let page = makePageView()
        page.annotationEnabled = false

        XCTAssertFalse(page.canvas.isUserInteractionEnabled)
        XCTAssertFalse(page.canvas.drawingGestureRecognizer.isEnabled)
    }

    func testShowingTheLayerAgainGivesTheCanvasBackItsInk() {
        let page = makePageView()
        page.annotationEnabled = true
        page.canvas.drawing = makeDrawing([makeStroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 160, y: 100))])
        page.canvasViewDrawingDidChange(page.canvas)

        page.setLayers(active: 1, visible: [])
        page.setLayers(active: 1, visible: [1])

        XCTAssertEqual(page.canvas.drawing.strokes.count, 1, "ink did not return to the canvas when its layer was shown")
        XCTAssertTrue(page.canvas.drawingGestureRecognizer.isEnabled)
    }

    func testHiddenLayerReturnsUnharmed() throws {
        let partID = UUID()
        let page = makePageView(partID: partID)
        page.canvas.drawing = makeDrawing([makeStroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 160, y: 100))])
        page.canvasViewDrawingDidChange(page.canvas)
        waitForJournal()

        page.setLayers(active: 1, visible: [])
        page.setLayers(active: 1, visible: [1])

        XCTAssertNotNil(page.inkView.image, "ink did not come back when its layer was shown again")
        let saved = try XCTUnwrap(StrokeJournal.shared.load(partID: partID, pageIndex: 0, layer: 1))
        XCTAssertEqual(saved.strokes.count, 1)
    }

    // MARK: - Shared margins

    func testMarginInkBelongsToThePartNotThePage() throws {
        // The whole promise: write beside page 1, still there beside page 5.
        let partID = UUID()
        let pdfSize = CGSize(width: 140, height: 792)
        let margin = ReadingPageView(frame: CGRect(origin: .zero, size: pdfSize))
        let window = UIWindow(frame: CGRect(origin: .zero, size: pdfSize))
        window.addSubview(margin)
        margin.isMarginSurface = true
        margin.configure(
            partID: partID, pageIndex: AnnotationLayers.marginRightIndex, pdfSize: pdfSize)
        margin.layoutIfNeeded()

        margin.canvas.drawing = makeDrawing([
            makeStroke(from: CGPoint(x: 20, y: 40), to: CGPoint(x: 90, y: 40))
        ])
        margin.canvasViewDrawingDidChange(margin.canvas)
        waitForJournal()

        let saved = try XCTUnwrap(StrokeJournal.shared.load(
            partID: partID, pageIndex: AnnotationLayers.marginRightIndex, layer: AnnotationLayers.first))
        XCTAssertEqual(saved.strokes.count, 1)

        // It must not have landed on any real page, at any index.
        for page in 0..<6 {
            XCTAssertNil(
                StrokeJournal.shared.load(partID: partID, pageIndex: page, layer: AnnotationLayers.first),
                "margin ink leaked onto page \(page)")
        }
    }

    func testTheTwoMarginsDoNotShareASlot() throws {
        let partID = UUID()
        for (index, y) in [(AnnotationLayers.marginRightIndex, 40.0), (AnnotationLayers.marginBottomIndex, 300.0)] {
            StrokeJournal.shared.save(
                makeDrawing([makeStroke(from: CGPoint(x: 10, y: y), to: CGPoint(x: 60, y: y))]),
                partID: partID, pageIndex: index, layer: AnnotationLayers.first,
                pageSize: CGSize(width: 200, height: 400))
        }
        waitForJournal()

        let left = try XCTUnwrap(StrokeJournal.shared.load(
            partID: partID, pageIndex: AnnotationLayers.marginRightIndex, layer: AnnotationLayers.first))
        let bottom = try XCTUnwrap(StrokeJournal.shared.load(
            partID: partID, pageIndex: AnnotationLayers.marginBottomIndex, layer: AnnotationLayers.first))
        XCTAssertEqual(left.bounds.minY, 40, accuracy: 4)
        XCTAssertEqual(bottom.bounds.minY, 300, accuracy: 4, "the two margins overwrote each other")
    }

    // MARK: - Journal format v2

    func testJournalCarriesAuthoredPageSize() throws {
        let partID = UUID()
        let size = CGSize(width: 595, height: 842)
        StrokeJournal.shared.save(
            makeDrawing([makeStroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 40, y: 10))]),
            partID: partID, pageIndex: 0, layer: 1, pageSize: size
        )
        waitForJournal()

        let record = try XCTUnwrap(StrokeJournal.shared.record(partID: partID, pageIndex: 0, layer: 1))
        // PRD 7.3: nothing reads this yet; ink written without it can never
        // get it back, which is the whole reason it is stored now.
        XCTAssertEqual(record.pageSize.width, size.width, accuracy: 0.01)
        XCTAssertEqual(record.pageSize.height, size.height, accuracy: 0.01)
        XCTAssertEqual(record.schemaVersion, 2)
    }

    func testPreLayerInkReadsForwardIntoLayerOne() throws {
        // A v1 blob, exactly as a build before layers would have left it.
        let partID = UUID()
        let drawing = makeDrawing([makeStroke(from: CGPoint(x: 70, y: 90), to: CGPoint(x: 130, y: 90))])
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Virtu/Drawings", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try drawing.dataRepresentation().write(
            to: dir.appendingPathComponent("\(partID.uuidString)-page0.pkdrawing"))

        let loaded = try XCTUnwrap(
            StrokeJournal.shared.load(partID: partID, pageIndex: 0, layer: AnnotationLayers.first),
            "ink written before layers existed was lost by the format change"
        )
        XCTAssertEqual(loaded.strokes.count, 1)
        XCTAssertNil(
            StrokeJournal.shared.load(partID: partID, pageIndex: 0, layer: 2),
            "legacy ink leaked onto every layer, not just layer 1"
        )
    }

    // MARK: - Line style and nib width

    func testStrokeStyleRidesInsideTheInkType() throws {
        let state = AppState(defaults: Self.scratchDefaults())
        state.tool = .pencil

        let expected: [(AppState.StrokeStyle, PKInkingTool.InkType)] = [
            (.solid, .pencil), (.calligraphic, .fountainPen),
            (.dotted, .pen), (.fineDotted, .monoline),
        ]
        for (style, inkType) in expected {
            state.strokeStyle = style
            let tool = try XCTUnwrap(state.currentPKTool() as? PKInkingTool)
            XCTAssertEqual(tool.inkType, inkType, "\(style.label) lost its carrier")
        }
    }

    func testNibLadderDoesNotMoveWhenTheLineStyleChanges() throws {
        let state = AppState(defaults: Self.scratchDefaults())
        state.tool = .pencil

        for index in AppState.nibWidths.indices {
            state.nibIndex = index
            let expected = AppState.nibWidths[index]
            for style in AppState.StrokeStyle.allCases {
                state.strokeStyle = style
                XCTAssertEqual(
                    state.pencilWidth, expected,
                    "changing line style to \(style.label) moved the nib — a nib is not something a line style gets to resize"
                )
            }
        }

        for index in AppState.nibWidths.indices.dropFirst() {
            XCTAssertGreaterThan(AppState.nibWidths[index], AppState.nibWidths[index - 1])
        }
    }

    func testDefaultNibIsHonouredByEveryStyle() throws {
        // 3pt must land exactly whatever the style: it is the width every
        // existing mark was made at, and the one nobody chose.
        let state = AppState(defaults: Self.scratchDefaults())
        state.tool = .pencil
        state.nibIndex = 1

        for style in AppState.StrokeStyle.allCases {
            state.strokeStyle = style
            let tool = try XCTUnwrap(state.currentPKTool() as? PKInkingTool)
            XCTAssertEqual(
                tool.width, 3.0, accuracy: 0.01,
                "\(style.label) clamped the default nib — its ink type cannot carry 3pt")
        }
    }

    func testDottedStylesActuallyBreakTheLine() throws {
        let size = CGSize(width: 200, height: 40)
        func inked(_ type: PKInkingTool.InkType) throws -> Int {
            let drawing = makeDrawing([
                makeStroke(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 190, y: 20), ink: type)
            ])
            let image = try XCTUnwrap(
                InkRenderer.image(for: drawing, pdfSize: size, displayScale: 1))
            return inkPixelCount(of: image)
        }

        let solid = try inked(.pencil)
        let dotted = try inked(.pen)
        let fine = try inked(.monoline)

        XCTAssertGreaterThan(solid, 0)
        XCTAssertLessThan(dotted, solid, "dotted rendered as a solid line")
        XCTAssertLessThan(fine, dotted, "fine dotted is not finer than dotted")
    }

    func testDottedDotSizeComesFromTheMedianPressureNotTheFirstPoint() throws {
        // A stroke begins at touch-down pressure, which is light. Sizing the
        // dots from the first point made every dotted line thinner than the
        // swatch promised — the median is what the hand actually drew.
        let size = CGSize(width: 200, height: 40)
        func stroke(firstWidth: CGFloat) -> PKStroke {
            let points = stride(from: 0.0, through: 1.0, by: 0.05).map { t in
                PKStrokePoint(
                    location: CGPoint(x: 10 + 180 * t, y: 20),
                    timeOffset: t,
                    size: CGSize(width: t == 0 ? firstWidth : 3, height: t == 0 ? firstWidth : 3),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
                )
            }
            return PKStroke(
                ink: PKInk(.pen, color: .black),
                path: PKStrokePath(controlPoints: points, creationDate: Date())
            )
        }

        func count(_ s: PKStroke) throws -> Int {
            let image = try XCTUnwrap(
                InkRenderer.image(for: makeDrawing([s]), pdfSize: size, displayScale: 1))
            return inkPixelCount(of: image)
        }

        let lightStart = try count(stroke(firstWidth: 0.4))
        let steady = try count(stroke(firstWidth: 3))
        XCTAssertEqual(
            Double(lightStart), Double(steady), accuracy: Double(steady) / 5,
            "a light touch-down resized the whole dotted line")
    }

    func testDottedStyleSurvivesTheFullCanvasPipeline() throws {
        // Not just the renderer in isolation: a stroke drawn on the canvas
        // goes through display-space -> PDF-space conversion and back before
        // the ink layer shows it. The style must survive the round trip.
        func inkPixels(_ ink: PKInkingTool.InkType) throws -> Int {
            let page = makePageView()
            page.canvas.drawing = makeDrawing([
                makeStroke(from: CGPoint(x: 50, y: 300), to: CGPoint(x: 550, y: 300), ink: ink)
            ])
            page.canvasViewDrawingDidChange(page.canvas)
            let image = try XCTUnwrap(page.inkView.image, "no committed ink rendered")
            return inkPixelCount(of: image)
        }

        let solid = try inkPixels(.pencil)
        let dotted = try inkPixels(.pen)
        let fine = try inkPixels(.monoline)
        XCTAssertLessThan(dotted, solid * 3 / 4, "dotted committed as a solid line")
        XCTAssertLessThan(fine, dotted, "fine dotted committed no finer than dotted")
    }

    func testCalligraphicWidthFollowsStrokeDirection() throws {
        // The italic nib: a northwest stroke is broad, a northeast stroke is
        // thin. If both render the same, the calligraphic style has collapsed
        // into the regular one — which is exactly what shipping only the
        // recorded point widths did.
        func inkPixels(from: CGPoint, to: CGPoint) throws -> Int {
            let drawing = makeDrawing([makeStroke(from: from, to: to, ink: .fountainPen)])
            let image = try XCTUnwrap(
                InkRenderer.image(for: drawing, pdfSize: CGSize(width: 300, height: 300), displayScale: 1))
            return inkPixelCount(of: image)
        }

        let northeast = try inkPixels(from: CGPoint(x: 50, y: 250), to: CGPoint(x: 250, y: 50))
        let northwest = try inkPixels(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 250, y: 250))
        XCTAssertGreaterThan(
            Double(northwest), Double(northeast) * 1.5,
            "calligraphic ink ignores stroke direction — it will read as the regular style")
    }

    func testCanvasLiveRenderHiddenUniformly() throws {
        // ONE rule for every tool but the lasso. Per-style alpha was tried
        // and produced the worst bug of the batch: committed ink's appearance
        // depended on which tool was ARMED — switching styles revealed
        // PencilKit's hidden solid render of strokes already on the page.
        let state = AppState(defaults: Self.scratchDefaults())
        let page = makePageView()

        state.tool = .pencil
        var alphas: [CGFloat] = []
        for style in AppState.StrokeStyle.allCases {
            state.strokeStyle = style
            page.apply(tool: state.currentPKTool())
            alphas.append(page.canvas.alpha)
        }
        state.tool = .highlighter
        page.apply(tool: state.currentPKTool())
        alphas.append(page.canvas.alpha)
        state.tool = .eraser
        page.apply(tool: state.currentPKTool())
        alphas.append(page.canvas.alpha)

        XCTAssertEqual(Set(alphas).count, 1,
                       "canvas visibility varies by tool — switching tools will change how existing ink looks")
        let alpha = try XCTUnwrap(alphas.first)
        XCTAssertLessThan(alpha, 0.1, "PencilKit's layer can flash its own opinion of committed ink")
        XCTAssertGreaterThan(alpha, 0.011, "an alpha this low stops hit-testing — input dies")

        state.tool = .lasso
        page.apply(tool: state.currentPKTool())
        XCTAssertEqual(page.canvas.alpha, 1, "lasso: PencilKit renders the selection — it must be visible")
    }

    func testHighlighterStillCompositesUnderInk() {
        // Sorting by ink type is what keeps a marker under a pencil; the style
        // carriers added four more ink types it must not be confused by.
        let drawing = makeDrawing([
            makeStroke(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 90, y: 20), ink: .pen),
            makeStroke(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 90, y: 20), width: 14, ink: .marker),
        ])
        let image = InkRenderer.image(for: drawing, pdfSize: CGSize(width: 100, height: 40), displayScale: 1)
        XCTAssertNotNil(image)
    }

    // MARK: - Tool persistence (PRD 7.4)

    func testToolSettingsSurviveRelaunch() {
        let store = Self.scratchDefaults()
        let first = AppState(defaults: store)
        first.tool = .highlighter
        first.strokeStyle = .fineDotted
        first.nibIndex = 3
        first.toolColors[.pencil] = 0x123456

        // A fresh AppState reading the same store is what a cold launch does.
        let second = AppState(defaults: store)
        XCTAssertEqual(second.tool, .highlighter)
        XCTAssertEqual(second.strokeStyle, .fineDotted)
        XCTAssertEqual(second.nibIndex, 3)
        XCTAssertEqual(second.toolColors[.pencil], 0x123456)
    }

    // MARK: - Reading layout: what the two modes reserve

    /// Hosts the real controller against a real PDF and toggles modes.
    /// The contract: the score occupies the same space in both modes — all
    /// chrome overlays it — and each switch re-parks the page cleanly.
    func testModeSwitchDoesNotResizeTheScore() throws {
        let bundle = Bundle(for: ReadingPageViewController.self)
        let pdfURL = try XCTUnwrap(bundle.url(forResource: "test-score", withExtension: "pdf"))
        let stored = "\(UUID().uuidString).pdf"
        try FileManager.default.copyItem(
            at: pdfURL, to: Part.storageDirectory.appendingPathComponent(stored))

        let state = AppState(defaults: Self.scratchDefaults())
        state.currentPart = Part(name: "test", pdfFileName: stored, pageCount: 1)

        let vc = ReadingPageViewController()
        vc.appState = state
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1032, height: 1376))
        window.rootViewController = vc
        window.isHidden = false
        window.layoutIfNeeded()

        func settle() {
            vc.view.setNeedsLayout()
            window.layoutIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        settle()

        let scroll = try XCTUnwrap(vc.view.subviews.compactMap { $0 as? UIScrollView }.first)

        let performInsetTop = scroll.contentInset.top
        let performPageHeight = scroll.subviews.first?.bounds.height ?? 0

        state.readingMode = .study
        vc.syncFromState()
        settle()
        // The mode switch must not resize or move the score: chrome, tool
        // rail and scrubber are all overlays now.
        XCTAssertEqual(scroll.contentInset.top, performInsetTop, accuracy: 1,
                       "Study reserved space Perform did not — the score shrank")
        XCTAssertEqual(scroll.subviews.first?.bounds.height ?? 0, performPageHeight, accuracy: 1,
                       "the score changed size across the mode switch")
        XCTAssertEqual(scroll.contentOffset.y, -scroll.contentInset.top, accuracy: 2,
                       "entering Study moved the page off its parked position")

        state.readingMode = .perform
        vc.syncFromState()
        settle()
        XCTAssertEqual(scroll.contentOffset.y, -scroll.contentInset.top, accuracy: 2,
                       "returning to Perform did not re-park at full bleed")
    }
}
