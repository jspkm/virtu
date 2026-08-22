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

    /// The third style is DASHED — line, space, line — not dots (2026-08-22;
    /// the name stays "dotted" because the enum's rawValue and the .pen
    /// carrier ride inside persisted strokes). Dash about three nibs long,
    /// gap about two, so the line reads as a line that breathes rather than
    /// a string of beads.
    static func dottedGeometry(nib: CGFloat) -> (width: CGFloat, dash: [CGFloat]) {
        // The renderer strokes with ROUND caps, which grow each dash by a
        // nib and eat the same out of each gap — these numbers are chosen
        // net of that: on the page a dash reads ~3.6 nibs, a gap ~2.
        let w = max(nib, 1.2)
        return (w, [max(w * 2.6, 3.5), max(w * 3.0, 4.0)])
    }

    /// Fine dotted: smaller dots, same rhythm. "Finer" means a smaller dot,
    /// not merely a closer one — tighter spacing alone lays down MORE ink.
    static func fineDottedGeometry(nib: CGFloat) -> (width: CGFloat, dash: [CGFloat]) {
        let w = max(nib * 0.58, 0.8)
        return (w, [0.01, max(w * 2.1, 0.8)])
    }

    /// How a stroke is drawn, decoded from the ink type it was authored with.
    private enum RenderStyle {
        /// Per-segment pressure width — what makes handwriting look handwritten.
        case pressure
        /// Pressure modulated by stroke direction: an italic nib. PencilKit's
        /// live fountain pen gets its character from stroke DIRECTION, not
        /// from recorded point widths — a fountain stroke's widths are nearly
        /// constant. Replaying widths alone flattened calligraphic ink to a
        /// plain line the moment our renderer took over at pen-up.
        case calligraphic
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
            case .fountainPen:
                return .calligraphic
            default:
                // .pencil (solid) keeps its pressure profile.
                return .pressure
            }
        }
    }

    /// The italic-nib width factor for a segment travelling at `angle`:
    /// widest perpendicular to the nib edge, thinnest along it. Nib edge held
    /// at the classic 45° — in top-left-origin coordinates that makes the
    /// downstroke toward lower-right broad and the northeast stroke thin,
    /// which is how an italic hand actually writes.
    static func nibFactor(angle: CGFloat) -> CGFloat {
        0.35 + 0.95 * abs(sin(angle + .pi / 4))
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

            case .calligraphic:
                for i in 1..<points.count {
                    let a = points[i - 1].location.applying(t)
                    let b = points[i].location.applying(t)
                    let angle = atan2(b.y - a.y, b.x - a.x)
                    let pressure = (points[i - 1].size.width + points[i].size.width) / 2
                    cg.setLineWidth(max(pressure * widthFactor * Self.nibFactor(angle: angle), 0.6))
                    cg.beginPath()
                    cg.move(to: a)
                    cg.addLine(to: b)
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
