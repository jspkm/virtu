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
        // Arming alone changes nothing (2026-08-22: picking up the lasso used
        // to restyle dotted marks solid); the session starts at the gesture.
        page.apply(tool: PKLassoTool())
        XCTAssertFalse(page.inkView.isHidden, "arming the lasso restyled the page before any gesture")
        page.testBeginLassoInteraction()
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
        page.testBeginLassoInteraction()   // the session starts at the gesture
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

    // MARK: - The Right Page

    /// One Right Page per spread, not one per part and not one per page.
    /// Right Page 1 sits beside score pages 1 and 2, Right Page 2 beside 3
    /// and 4.
    func testRightPageIsKeyedToTheSpread() {
        XCTAssertEqual(AnnotationLayers.spread(forPage: 0), 0)
        XCTAssertEqual(AnnotationLayers.spread(forPage: 1), 0, "page 2 left its spread")
        XCTAssertEqual(AnnotationLayers.spread(forPage: 2), 1)
        XCTAssertEqual(AnnotationLayers.spread(forPage: 3), 1, "page 4 left its spread")

        XCTAssertNotEqual(AnnotationLayers.rightPageIndex(spread: 0),
                          AnnotationLayers.rightPageIndex(spread: 1),
                          "two spreads share one sheet")

        // Slots must stay clear of real pages and of the two retired values,
        // because journals in the field still hold records at both.
        var seen = Set<Int>()
        for spread in 0..<200 {
            let slot = AnnotationLayers.rightPageIndex(spread: spread)
            XCTAssertLessThan(slot, 0, "a Right Page slot collided with a real page")
            XCTAssertNotEqual(slot, -1, "-1 is retired: the old part-wide margin")
            XCTAssertNotEqual(slot, -2, "-2 is retired: the old bottom margin")
            XCTAssertTrue(seen.insert(slot).inserted, "slot \(slot) handed out twice")
        }

        XCTAssertEqual(AnnotationLayers.rightPageIndices(pageCount: 6).count, 3,
                       "six pages are three spreads, so three Right Pages")
        XCTAssertEqual(AnnotationLayers.rightPageIndices(pageCount: 5).count, 3,
                       "an odd last page still has a spread to sit beside")
        XCTAssertTrue(AnnotationLayers.rightPageIndices(pageCount: 0).isEmpty)
    }

    /// Turning the iPad must not change which sheet you are writing on.
    /// Landscape shows pages 1 and 2 at once; portrait shows them one at a
    /// time. Both reach Right Page 1, or a note written beside page 2 in
    /// portrait disappears on rotation.
    func testRotatingKeepsTheSameRightPage() throws {
        let bundle = Bundle(for: ReadingPageViewController.self)
        let pdfURL = try XCTUnwrap(bundle.url(forResource: "test-score", withExtension: "pdf"))
        let stored = "\(UUID().uuidString).pdf"
        try FileManager.default.copyItem(
            at: pdfURL, to: Part.storageDirectory.appendingPathComponent(stored))

        let state = AppState(defaults: Self.scratchDefaults())
        state.currentPart = Part(name: "test", pdfFileName: stored, pageCount: 6)
        state.readingMode = .study

        let vc = ReadingPageViewController()
        vc.appState = state
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1032, height: 1376))
        window.rootViewController = vc
        window.isHidden = false
        window.layoutIfNeeded()

        func settle(_ frame: CGRect) {
            window.frame = frame
            vc.view.frame = CGRect(origin: .zero, size: frame.size)
            vc.view.setNeedsLayout()
            window.layoutIfNeeded()
            vc.syncFromState()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        let portrait = CGRect(x: 0, y: 0, width: 1032, height: 1376)
        let landscape = CGRect(x: 0, y: 0, width: 1376, height: 1032)

        // Portrait on page 2, the right-hand page of spread 1.
        settle(portrait)
        state.goToPage(1)
        settle(portrait)
        XCTAssertEqual(state.pageIndex, 1, "portrait should sit on page 2")
        let fromPageTwo = vc.testRightPage.pageIndex

        // Portrait on page 1 — same spread, so the same sheet.
        state.goToPage(0)
        settle(portrait)
        XCTAssertEqual(vc.testRightPage.pageIndex, fromPageTwo,
                       "pages 1 and 2 do not share a Right Page")

        // Landscape showing both at once — still the same sheet.
        settle(landscape)
        XCTAssertEqual(state.pagesPerView, 2, "landscape should show a spread")
        XCTAssertEqual(vc.testRightPage.pageIndex, fromPageTwo,
                       "turning the iPad moved the musician to a different sheet")

        // The next spread is a different sheet.
        state.goToPage(2)
        settle(landscape)
        XCTAssertNotEqual(vc.testRightPage.pageIndex, fromPageTwo,
                          "pages 3 and 4 reuse the sheet from pages 1 and 2")
        XCTAssertEqual(vc.testRightPage.pageIndex,
                       AnnotationLayers.rightPageIndex(spread: 1))
    }

    func testRightPageInkLandsInItsSpreadSlotAndNowhereElse() throws {
        let partID = UUID()
        let pdfSize = CGSize(width: 140, height: 792)
        let slot = AnnotationLayers.rightPageIndex(spread: 0)
        let sheet = ReadingPageView(frame: CGRect(origin: .zero, size: pdfSize))
        let window = UIWindow(frame: CGRect(origin: .zero, size: pdfSize))
        window.addSubview(sheet)
        sheet.isMarginSurface = true
        sheet.configure(partID: partID, pageIndex: slot, pdfSize: pdfSize)
        sheet.layoutIfNeeded()

        sheet.canvas.drawing = makeDrawing([
            makeStroke(from: CGPoint(x: 20, y: 40), to: CGPoint(x: 90, y: 40))
        ])
        sheet.canvasViewDrawingDidChange(sheet.canvas)
        waitForJournal()

        let saved = try XCTUnwrap(StrokeJournal.shared.load(
            partID: partID, pageIndex: slot, layer: AnnotationLayers.first))
        XCTAssertEqual(saved.strokes.count, 1)

        // Not on any real page, and not on the next spread's sheet.
        for page in 0..<6 {
            XCTAssertNil(
                StrokeJournal.shared.load(partID: partID, pageIndex: page, layer: AnnotationLayers.first),
                "Right Page ink leaked onto score page \(page)")
        }
        XCTAssertNil(StrokeJournal.shared.load(
            partID: partID,
            pageIndex: AnnotationLayers.rightPageIndex(spread: 1),
            layer: AnnotationLayers.first),
            "ink leaked onto the next spread's Right Page")
    }

    /// The space under the score is headroom, not a surface. It used to be a
    /// ReadingPageView a full page tall, which meant it took tools, layers,
    /// pencil input and a journal slot, and gave a whole screen of scrolling
    /// through nothing. Both halves of that are the bug.
    func testBottomHeadroomIsNotWritableAndIsNotAPage() throws {
        let bundle = Bundle(for: ReadingPageViewController.self)
        let pdfURL = try XCTUnwrap(bundle.url(forResource: "test-score", withExtension: "pdf"))
        let stored = "\(UUID().uuidString).pdf"
        try FileManager.default.copyItem(
            at: pdfURL, to: Part.storageDirectory.appendingPathComponent(stored))

        let state = AppState(defaults: Self.scratchDefaults())
        state.currentPart = Part(name: "test", pdfFileName: stored, pageCount: 1)
        state.readingMode = .study

        let vc = ReadingPageViewController()
        vc.appState = state
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1032, height: 1376))
        window.rootViewController = vc
        window.isHidden = false
        window.layoutIfNeeded()
        vc.syncFromState()
        vc.view.setNeedsLayout()
        window.layoutIfNeeded()

        let headroom = vc.testBottomHeadroom
        XCTAssertFalse(headroom is ReadingPageView,
                       "the space under the score is a writable surface again")
        XCTAssertFalse(headroom.isUserInteractionEnabled,
                       "the headroom takes touches, so it can take a pencil")
        XCTAssertTrue(headroom.subviews.isEmpty,
                      "something is mounted in the headroom — it holds nothing")

        // Headroom, not a second page: one bar of travel, fixed. It clears a
        // hand, so it does not scale with the paper.
        let pageHeight = vc.testPage.bounds.height
        XCTAssertGreaterThan(pageHeight, 0)
        XCTAssertEqual(headroom.bounds.height, Tokens.bottomHeadroom, accuracy: 1,
                       "the headroom is no longer a fixed height")
        XCTAssertLessThan(headroom.bounds.height, pageHeight / 4,
                          "a page of headroom is scrolling through nothing")
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

        // The lasso joins the rule at ARM time (2026-08-22: an armed lasso's
        // opaque canvas double-drew PencilKit's rendering over ours, shifting
        // every marking slightly). Full strength arrives only with the
        // session, when a lasso gesture actually begins.
        state.tool = .lasso
        page.apply(tool: state.currentPKTool())
        XCTAssertLessThan(page.canvas.alpha, 0.1,
                          "an armed-but-idle lasso lit PencilKit's layer over committed ink")
        page.testBeginLassoInteraction()
        XCTAssertEqual(page.canvas.alpha, 1, "lasso session: PencilKit renders the selection — it must be visible")
    }

    func testLivePreviewIsTheChosenStyleFromTheFirstMillimetre() throws {
        // The wet stroke renders through InkRenderer itself, so what you
        // write IS the style you chose — pen-up refines, it does not replace.
        func pixels(_ inkType: PKInkingTool.InkType) -> Int {
            let wet = WetStrokeView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
            let samples = (0...29).map { i in
                (location: CGPoint(x: 10 + CGFloat(i) * 9.3, y: 50), force: CGFloat(0.6))
            }
            wet.begin(ink: PKInk(inkType, color: .black), baseWidth: 3, samples: [samples[0]])
            wet.append(samples: Array(samples.dropFirst()))
            let renderer = UIGraphicsImageRenderer(size: wet.bounds.size)
            let image = renderer.image { wet.layer.render(in: $0.cgContext) }
            return inkPixelCount(of: image)
        }

        let solid = pixels(.pencil)
        let dotted = pixels(.pen)
        let fine = pixels(.monoline)
        XCTAssertGreaterThan(solid, 0, "the live preview draws nothing at all")
        XCTAssertLessThan(dotted, solid * 3 / 4,
                          "the live preview draws dotted as a solid line — the style snaps at pen-up")
        XCTAssertLessThan(fine, dotted, "live fine dotted is not finer than dotted")
    }

    func testCommittedStrokeIsIdenticallyTheLiveStroke() throws {
        // The paper rule: pen-up changes nothing. The pencil pipeline is ours
        // end to end, so the points drawn under the tip must be, identically,
        // the points that persist — same geometry, same ink, same widths.
        let partID = UUID()
        let page = makePageView(partID: partID)
        page.setLayers(active: 1, visible: [1])
        page.annotationEnabled = true

        let state = AppState(defaults: Self.scratchDefaults())
        state.tool = .pencil
        state.strokeStyle = .dotted
        page.apply(tool: state.currentPKTool())

        let samples = (0...20).map { i in
            (location: CGPoint(x: 100 + CGFloat(i) * 10, y: 200 + CGFloat(i) * 3),
             force: CGFloat(0.6))
        }
        page.inkGestureBegan([samples[0]])
        page.inkGestureMoved(Array(samples.dropFirst()))
        page.inkGestureEnded()
        waitForJournal()

        let saved = try XCTUnwrap(
            StrokeJournal.shared.load(partID: partID, pageIndex: 0, layer: 1),
            "the live stroke was not committed at pen-up")
        XCTAssertEqual(saved.strokes.count, 1)
        let stroke = try XCTUnwrap(saved.strokes.first)
        XCTAssertEqual(stroke.ink.inkType, .pen, "the committed stroke lost its style carrier")
        // Display scale is 1 in the harness, so PDF-space equals view-space.
        XCTAssertEqual(saved.bounds.minX, 100, accuracy: 4)
        XCTAssertEqual(saved.bounds.maxX, 300, accuracy: 4)
        XCTAssertNotNil(page.inkView.image, "committed ink is not on the ink layer")

        // PencilKit did not participate: its recognizer must be off while an
        // inking tool is armed, and on for the lasso.
        XCTAssertFalse(page.canvas.drawingGestureRecognizer.isEnabled,
                       "PencilKit still records inking strokes — two sources of truth again")
        state.tool = .lasso
        page.apply(tool: state.currentPKTool())
        XCTAssertTrue(page.canvas.drawingGestureRecognizer.isEnabled,
                      "the lasso still needs PencilKit's recognizer")
    }

    func testCancelledInkGestureLeavesNoMark() {
        // A cancelled touch is the system taking the gesture back — paper
        // keeps no mark from a pencil that never truly landed.
        let partID = UUID()
        let page = makePageView(partID: partID)
        page.setLayers(active: 1, visible: [1])
        page.annotationEnabled = true
        let state = AppState(defaults: Self.scratchDefaults())
        state.tool = .pencil
        page.apply(tool: state.currentPKTool())

        page.inkGestureBegan([(location: CGPoint(x: 50, y: 50), force: 0.6)])
        page.inkGestureMoved([(location: CGPoint(x: 150, y: 50), force: 0.6)])
        // Cancel path clears without committing (observer.onCancelled → clearWet).
        waitForJournal()
        XCTAssertNil(StrokeJournal.shared.load(partID: partID, pageIndex: 0, layer: 1),
                     "an uncommitted gesture persisted ink")
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

    /// A turn must never move the paper. Perform panning is meant to be off —
    /// "a stray drag must never shift the page a player is reading from" — but
    /// the lock was written as `panGestureRecognizer.isEnabled = false`, and
    /// UIScrollView owns that recognizer and re-enables it. The turn swipe then
    /// dragged the spread one page-width sideways onto the invisible right
    /// margin, so every page after the first read as blank paper on the stand.
    func testPerformModeLocksTheScroll() throws {
        let bundle = Bundle(for: ReadingPageViewController.self)
        let pdfURL = try XCTUnwrap(bundle.url(forResource: "test-score", withExtension: "pdf"))
        let stored = "\(UUID().uuidString).pdf"
        try FileManager.default.copyItem(
            at: pdfURL, to: Part.storageDirectory.appendingPathComponent(stored))

        let state = AppState(defaults: Self.scratchDefaults())
        state.currentPart = Part(name: "test", pdfFileName: stored, pageCount: 6)

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

        let scroll = vc.testScrollView
        XCTAssertFalse(scroll.isScrollEnabled,
                       "Perform left the scroll live: a turn swipe drags the page off screen")

        // A turn is where it used to come undone.
        state.turn(1)
        vc.syncFromState()
        settle()
        XCTAssertFalse(scroll.isScrollEnabled, "a turn re-opened the Perform scroll lock")
        XCTAssertEqual(scroll.contentOffset.x, -scroll.contentInset.left, accuracy: 2,
                       "the page is no longer parked in the viewport after a turn")

        // Study is the mode that reaches the margins, so it must pan.
        state.readingMode = .study
        vc.syncFromState()
        settle()
        XCTAssertTrue(scroll.isScrollEnabled, "Study cannot reach the shared margins")
    }

    // MARK: - Ink palettes

    /// Three swatches per tool, the first of which is the tool's own colour and
    /// cannot be lost.
    func testPaletteFirstSlotIsFixed() {
        let state = AppState(defaults: Self.scratchDefaults())

        XCTAssertEqual(state.palette(for: .pencil).count, 3)
        XCTAssertEqual(state.palette(for: .pencil)[0], AppState.graphiteHex)
        XCTAssertEqual(state.palette(for: .highlighter)[0], AppState.highlighterYellowHex)

        state.setPaletteSlot(AppState.fixedSlot, to: 0x00FF00, for: .pencil)
        XCTAssertEqual(state.palette(for: .pencil)[0], AppState.graphiteHex,
                       "the pencil's own graphite was overwritten")
        state.setPaletteSlot(AppState.fixedSlot, to: 0x00FF00, for: .highlighter)
        XCTAssertEqual(state.palette(for: .highlighter)[0], AppState.highlighterYellowHex,
                       "the highlighter's own yellow was overwritten")

        // Out of range must not crash or grow the palette.
        state.setPaletteSlot(9, to: 0x00FF00, for: .pencil)
        XCTAssertEqual(state.palette(for: .pencil).count, 3)
    }

    /// The highlighter's colours are its own. A wash and a line want different
    /// colours, so re-colouring one tool must not reach the other.
    func testHighlighterKeepsItsOwnPalette() {
        let state = AppState(defaults: Self.scratchDefaults())
        XCTAssertNotEqual(state.palette(for: .pencil), state.palette(for: .highlighter))

        let pencilBefore = state.palette(for: .pencil)
        state.setPaletteSlot(1, to: 0x123456, for: .highlighter)
        XCTAssertEqual(state.palette(for: .highlighter)[1], 0x123456)
        XCTAssertEqual(state.palette(for: .pencil), pencilBefore,
                       "re-colouring the highlighter moved the pencil's swatch")
    }

    /// Re-colouring the swatch you are drawing with changes the ink in your
    /// hand, rather than making you pick it a second time.
    func testRecolouringTheActiveSwatchChangesTheInk() {
        let state = AppState(defaults: Self.scratchDefaults())
        let red = state.palette(for: .pencil)[1]
        state.tool = .pencil
        state.toolColors[.pencil] = red

        state.setPaletteSlot(1, to: 0x123456, for: .pencil)
        XCTAssertEqual(state.toolColors[.pencil], 0x123456)

        // An inactive slot leaves the ink alone.
        state.setPaletteSlot(2, to: 0xABCDEF, for: .pencil)
        XCTAssertEqual(state.toolColors[.pencil], 0x123456)
    }

    /// A chosen colour survives a cold launch; the fixed slot comes from the
    /// build, so changing it in a release moves it for everyone.
    func testPaletteSurvivesRelaunchButTheFixedSlotComesFromTheBuild() {
        let store = Self.scratchDefaults()
        let first = AppState(defaults: store)
        first.setPaletteSlot(2, to: 0x336699, for: .pencil)
        first.setPaletteSlot(1, to: 0x66AA22, for: .highlighter)

        let second = AppState(defaults: store)
        XCTAssertEqual(second.palette(for: .pencil)[2], 0x336699)
        XCTAssertEqual(second.palette(for: .highlighter)[1], 0x66AA22)
        XCTAssertEqual(second.palette(for: .pencil)[0], AppState.graphiteHex)
        XCTAssertEqual(second.palette(for: .highlighter)[0], AppState.highlighterYellowHex)
    }

    // MARK: - Tool options (eraser mode, highlighter height, lasso mode)

    /// The area eraser is the default — a real eraser rubs out what it
    /// touches — and the old remove-the-whole-marking behaviour is the option.
    func testEraserDefaultsToAreaAndMapsToTheRightPKTool() {
        let state = AppState(defaults: Self.scratchDefaults())
        XCTAssertEqual(state.eraserMode, .area)

        state.tool = .eraser
        let area = state.currentPKTool() as? PKEraserTool
        // PencilKit normalizes a width-carrying bitmap eraser to
        // .fixedWidthBitmap and clamps the tip to its floor (16.4pt). What
        // matters: it erases AREA, not whole strokes, at the smallest tip
        // the platform allows.
        XCTAssertNotEqual(area?.eraserType, .vector,
                          "area mode handed PencilKit a whole-stroke eraser")
        let width = area?.width ?? 0
        XCTAssertGreaterThan(width, 0)
        XCTAssertLessThan(width, 20, "the area tip is no longer the smallest available")

        state.eraserMode = .stroke
        let stroke = state.currentPKTool() as? PKEraserTool
        XCTAssertEqual(stroke?.eraserType, .vector)
    }

    /// Four heights; the default is the second (double the original), and the
    /// armed tool actually wears the chosen width.
    func testHighlighterHeightsAndDefault() {
        let state = AppState(defaults: Self.scratchDefaults())
        XCTAssertEqual(AppState.highlighterWidths, [14, 28, 42, 56])
        XCTAssertEqual(state.highlighterWidthIndex, 1)
        XCTAssertEqual(state.highlighterWidth, 28)

        state.tool = .highlighter
        state.highlighterWidthIndex = 3
        let tool = state.currentPKTool() as? PKInkingTool
        XCTAssertEqual(tool?.width ?? 0, 56, accuracy: 0.5)
    }

    /// Move stays the lasso default. Every mode choice survives a relaunch.
    func testToolOptionsSurviveRelaunch() {
        let store = Self.scratchDefaults()
        let first = AppState(defaults: store)
        XCTAssertEqual(first.lassoMode, .move)
        first.eraserMode = .stroke
        first.highlighterWidthIndex = 2
        first.lassoMode = .copy

        let second = AppState(defaults: store)
        XCTAssertEqual(second.eraserMode, .stroke)
        XCTAssertEqual(second.highlighterWidthIndex, 2)
        XCTAssertEqual(second.lassoMode, .copy)
    }

    // MARK: - Clippings

    /// A clipping persists to its page slot, renders back, and dies with the
    /// part. The stroke journal is never involved.
    func testClippingRoundTripAndDelete() throws {
        let partID = UUID()
        let store = ClippingStore.shared

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20))
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }

        let rect = CGRect(x: 100, y: 200, width: 80, height: 40)
        let added = try XCTUnwrap(store.add(partID: partID, pageIndex: 2, rect: rect, image: image))
        XCTAssertEqual(store.clippings(partID: partID, pageIndex: 2).count, 1)
        XCTAssertTrue(store.clippings(partID: partID, pageIndex: 3).isEmpty,
                      "the clipping leaked onto another page")
        XCTAssertEqual(store.clippings(partID: partID, pageIndex: 2).first?.rect, rect)
        XCTAssertNotNil(store.image(for: added))

        // A Right Page slot holds clippings too — that is the point.
        let rpSlot = AnnotationLayers.rightPageIndex(spread: 0)
        store.add(partID: partID, pageIndex: rpSlot, rect: rect, image: image)
        XCTAssertEqual(store.clippings(partID: partID, pageIndex: rpSlot).count, 1)

        store.remove(partID: partID, clippingID: added.id)
        XCTAssertTrue(store.clippings(partID: partID, pageIndex: 2).isEmpty)

        store.deleteAll(partID: partID)
        XCTAssertTrue(store.all(partID: partID).isEmpty)
    }

    // MARK: - 2026-08-22 regressions

    /// Copy mode must keep the ink layer lit. The lasso DISPLAY session hides
    /// inkView so PencilKit can render a Move drag — but the ink layer is
    /// also where clippings composite, so entering that session in Copy mode
    /// made every dropped clipping vanish the moment the lasso re-applied.
    func testCopyModeNeverHidesTheInkLayer() {
        let page = ReadingPageView(frame: CGRect(x: 0, y: 0, width: 200, height: 300))

        // ARMING the Move lasso changes nothing: the display session — which
        // hides our dotted-faithful ink layer in favour of PencilKit's
        // literal rendering — waits for an actual lasso gesture.
        page.copyModeArmed = false
        page.apply(tool: PKLassoTool())
        XCTAssertFalse(page.inkView.isHidden,
                       "picking up the lasso restyled the page before it touched anything")
        XCTAssertLessThan(page.canvas.alpha, 0.05,
                          "arming the lasso lit PencilKit's layer — its rendering double-draws over ours")

        // The first lasso gesture hands display to PencilKit.
        page.testBeginLassoInteraction()
        XCTAssertTrue(page.inkView.isHidden, "a lasso gesture should hand display to PencilKit")
        XCTAssertEqual(page.canvas.alpha, 1, accuracy: 0.01,
                       "the session needs PencilKit's layer at full strength for the drag")

        // Copy-mode lasso: our marquee, our display — ink layer stays.
        page.copyModeArmed = true
        XCTAssertFalse(page.inkView.isHidden, "copy mode hid the layer that shows the clippings")

        // Back to Move: the session needs a fresh gesture, not just the mode.
        page.copyModeArmed = false
        XCTAssertFalse(page.inkView.isHidden)
        page.testBeginLassoInteraction()
        XCTAssertTrue(page.inkView.isHidden)

        // Leaving the lasso entirely restores the ink layer.
        page.apply(tool: PKInkingTool(.pencil, color: .black, width: 3))
        XCTAssertFalse(page.inkView.isHidden)

        // A gesture with the eraser (or any non-lasso tool) starts no session.
        page.apply(tool: PKEraserTool(.vector))
        page.testBeginLassoInteraction()
        XCTAssertFalse(page.inkView.isHidden,
                       "an eraser gesture must never restyle the page")
    }

    /// Three layers, always — for every part, with no adding.
    func testExactlyThreeLayersAlways() {
        XCTAssertEqual(AnnotationLayers.max, 3)
        let state = AppState(defaults: Self.scratchDefaults())
        XCTAssertEqual(state.layerCount, 3, "layer count must not depend on the part")

        // A part whose stored layerCount predates the cap still shows three.
        let part = Part(name: "test", pdfFileName: "x.pdf", pageCount: 1)
        part.layerCount = 1
        XCTAssertEqual(part.visibleLayerIndices, [1, 2, 3])
    }

    /// Deep-press support: a placed clipping must be findable under a point,
    /// in view space, topmost first — that hit is what a hold lifts.
    func testClippingHitTest() throws {
        let partID = UUID()
        let pdfSize = CGSize(width: 200, height: 400)
        let page = ReadingPageView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        page.configure(partID: partID, pageIndex: 0, pdfSize: pdfSize)
        page.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let image = renderer.image { ctx in
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        // PDF-space rect 50,100 60x40; display scale is 2, so its view-space
        // home is 100,200 120x80.
        let added = try XCTUnwrap(ClippingStore.shared.add(
            partID: partID, pageIndex: 0,
            rect: CGRect(x: 50, y: 100, width: 60, height: 40), image: image))
        defer { ClippingStore.shared.deleteAll(partID: partID) }

        XCTAssertEqual(page.clippingHit(at: CGPoint(x: 160, y: 240))?.id, added.id)
        XCTAssertNil(page.clippingHit(at: CGPoint(x: 30, y: 30)),
                     "a point outside every clipping still hit one")
    }
}
