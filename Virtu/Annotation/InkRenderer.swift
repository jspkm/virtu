import UIKit
import PencilKit

/// The app's own stroke rasterizer. PencilKit's renderer (canvas display and
/// PKDrawing.image) produces no output on iPadOS 26.x, so every surface that
/// shows committed ink — page display and PDF export — draws through here:
/// a polyline through interpolated stroke points, round caps and joins.
///
/// It is also where line style lives. A stroke's ink type is the *carrier* for
/// the style chosen in the pencil flyout; what dotted ink actually looks like
/// is decided here and nowhere else.
enum InkRenderer {

    // MARK: - Dotted geometry: ONE source of truth
    //
    // The style swatches in the pencil flyout draw from these same functions,
    // so the mark on the page matches the swatch that promised it — by
    // construction, not by keeping two sets of constants in agreement.

    /// Dotted: round caps on a near-zero dash length give circular dots whose
    /// diameter is the nib width, spaced about a dot apart.
    static func dottedGeometry(nib: CGFloat) -> (width: CGFloat, dash: [CGFloat]) {
        let w = max(nib, 1.2)
        return (w, [0.01, max(w * 2.1, 1.2)])
    }

    /// Fine dotted: smaller dots, same rhythm. "Finer" means a smaller dot,
    /// not merely a closer one — tighter spacing alone lays down MORE ink.
    static func fineDottedGeometry(nib: CGFloat) -> (width: CGFloat, dash: [CGFloat]) {
        let w = max(nib * 0.58, 0.8)
        return (w, [0.01, max(w * 2.1, 0.8)])
    }

    /// What the live wet-ink preview should draw for a tool, so the stroke
    /// under the tip already looks like what will be committed.
    static func wetGeometry(inkType: PKInk.InkType, width: CGFloat) -> (width: CGFloat, dash: [CGFloat]?) {
        switch inkType {
        case .pen:
            let g = dottedGeometry(nib: width); return (g.width, g.dash)
        case .monoline:
            let g = fineDottedGeometry(nib: width); return (g.width, g.dash)
        default:
            return (width, nil)
        }
    }

    /// How a stroke is drawn, decoded from the ink type it was authored with.
    private enum RenderStyle {
        /// Per-segment pressure width — what makes handwriting look handwritten.
        case pressure
        /// One flat path at a resolved width. Overlapping segments of
        /// translucent ink must not double-darken, and a dash pattern must not
        /// restart every segment.
        case flat(width: CGFloat, dash: [CGFloat]?)

        static func decode(_ inkType: PKInk.InkType, width: CGFloat) -> RenderStyle {
            switch inkType {
            case .marker:
                return .flat(width: width, dash: nil)
            case .pen:
                let g = InkRenderer.dottedGeometry(nib: width)
                return .flat(width: g.width, dash: g.dash)
            case .monoline:
                let g = InkRenderer.fineDottedGeometry(nib: width)
                return .flat(width: g.width, dash: g.dash)
            default:
                // .pencil (solid) and .fountainPen (calligraphic) both keep
                // their pressure profile; the fountain pen's own point sizes
                // supply the calligraphic swell.
                return .pressure
            }
        }
    }

    /// Draw one drawing's strokes into a CG context whose coordinate space
    /// matches the drawing's own (PDF points, top-left origin).
    /// Highlighter strokes render first so ink always sits above them.
    static func draw(_ drawing: PKDrawing, in cg: CGContext) {
        cg.setLineCap(.round)
        cg.setLineJoin(.round)

        let ordered = drawing.strokes.sorted {
            ($0.ink.inkType == .marker ? 0 : 1) < ($1.ink.inkType == .marker ? 0 : 1)
        }

        for stroke in ordered {
            let points = Array(stroke.path.interpolatedPoints(by: .distance(1.5)))
            guard points.count > 1 else { continue }
            cg.setStrokeColor(stroke.ink.color.cgColor)

            // CRITICAL: PKStroke geometry = path points ⊗ stroke.transform.
            // PKDrawing.transformed(using:) stores scaling in the transform,
            // NOT in the points — ignoring it renders every stroke shrunk
            // toward the origin (the "marks land above/left of the pencil"
            // bug). Positions map through the transform; widths scale by its
            // uniform scale factor.
            let t = stroke.transform
            let widthFactor = max(sqrt(abs(t.a * t.d - t.b * t.c)), 0.01)
            // Flat styles size from the MEDIAN recorded width, not the first
            // point's: touch-down pressure is light, and a whole dotted line
            // sized by its first millisecond came out thinner than the swatch
            // promised. The median is what the hand actually drew.
            let sorted = points.map { $0.size.width }.sorted()
            let medianWidth = max(sorted[sorted.count / 2] * widthFactor, 0.8)
            let style = RenderStyle.decode(stroke.ink.inkType, width: medianWidth)

            switch style {
            case .flat(let width, let dash):
                cg.setLineWidth(width)
                if let dash {
                    // The geometry already carries widthFactor via the width
                    // it was derived from — scaling the dash again was
                    // double-counting it on transformed strokes.
                    cg.setLineDash(phase: 0, lengths: dash)
                }
                cg.beginPath()
                cg.move(to: points[0].location.applying(t))
                for point in points.dropFirst() {
                    cg.addLine(to: point.location.applying(t))
                }
                cg.strokePath()
                if dash != nil {
                    cg.setLineDash(phase: 0, lengths: [])
                }

            case .pressure:
                for i in 1..<points.count {
                    let a = points[i - 1]
                    let b = points[i]
                    cg.setLineWidth(max((a.size.width + b.size.width) / 2 * widthFactor, 0.8))
                    cg.beginPath()
                    cg.move(to: a.location.applying(t))
                    cg.addLine(to: b.location.applying(t))
                    cg.strokePath()
                }
            }
        }
    }

    /// Composite several layers, bottom-up. Layer 1 sits at the bottom;
    /// highlighter-under-ink ordering applies *within* each layer, so a
    /// highlighter on an upper layer still washes over the layers below it.
    static func draw(_ drawings: [PKDrawing], in cg: CGContext) {
        for drawing in drawings {
            draw(drawing, in: cg)
        }
    }

    /// Rasterize PDF-point-space layers at a display scale.
    static func image(for drawings: [PKDrawing], pdfSize: CGSize, displayScale: CGFloat) -> UIImage? {
        let inked = drawings.filter { !$0.strokes.isEmpty }
        guard !inked.isEmpty, displayScale > 0 else { return nil }
        let size = CGSize(width: pdfSize.width * displayScale, height: pdfSize.height * displayScale)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            ctx.cgContext.scaleBy(x: displayScale, y: displayScale)
            draw(inked, in: ctx.cgContext)
        }
    }

    static func image(for drawing: PKDrawing, pdfSize: CGSize, displayScale: CGFloat) -> UIImage? {
        image(for: [drawing], pdfSize: pdfSize, displayScale: displayScale)
    }
}
