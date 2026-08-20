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

    /// How a stroke is drawn, decoded from the ink type it was authored with.
    private enum RenderStyle {
        /// Per-segment pressure width — what makes handwriting look handwritten.
        case pressure
        /// One flat path. Overlapping segments of translucent ink must not
        /// double-darken, and a dash pattern must not restart every segment.
        case flat(dash: [CGFloat]?, widthScale: CGFloat)

        static func decode(_ inkType: PKInk.InkType, width: CGFloat) -> RenderStyle {
            switch inkType {
            case .marker:
                return .flat(dash: nil, widthScale: 1)
            case .pen:
                // Dotted: round caps on a near-zero dash length give dots
                // whose diameter is the line width.
                return .flat(dash: [0.01, max(width * 2.2, 1.2)], widthScale: 1)
            case .monoline:
                // Fine dotted. "Finer" has to mean a smaller dot, not merely a
                // closer one — tightening the spacing alone lays down *more*
                // ink than plain dotted, which is the opposite of the ask.
                let scaled = width * 0.6
                return .flat(dash: [0.01, max(scaled * 2.6, 1.0)], widthScale: 0.6)
            default:
                // .pencil (solid) and .fountainPen (calligraphic) both keep
                // their pressure profile; the fountain pen's own point sizes
                // supply the calligraphic swell.
                return .pressure
            }
        }

        var isDashed: Bool {
            if case .flat(let dash, _) = self { return dash != nil }
            return false
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
            let baseWidth = max(points[0].size.width * widthFactor, 0.8)
            let style = RenderStyle.decode(stroke.ink.inkType, width: baseWidth)

            switch style {
            case .flat(let dash, let widthScale):
                cg.setLineWidth(max(baseWidth * widthScale, 0.5))
                if let dash {
                    cg.setLineDash(phase: 0, lengths: dash.map { $0 * widthFactor })
                }
                cg.beginPath()
                cg.move(to: points[0].location.applying(t))
                for point in points.dropFirst() {
                    cg.addLine(to: point.location.applying(t))
                }
                cg.strokePath()
                if style.isDashed {
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
