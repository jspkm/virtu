import UIKit
import PencilKit

/// The curated marks musicians actually use — the ~95% of forScore's stamp
/// library that matters, and nothing else. Every stamp is built as real
/// PencilKit strokes, so placed marks journal, export, undo, erase, and
/// lasso-move exactly like handwritten ink.
enum Stamp: String, CaseIterable, Identifiable {
    // Articulation & cues
    case downBow, upBow, eyeglasses, breath, fermata, accent, circle
    // Dynamics
    case pp, p, mp, mf, f, ff
    // Fingerings
    case finger0, finger1, finger2, finger3, finger4

    var id: String { rawValue }

    static let articulation: [Stamp] = [.downBow, .upBow, .eyeglasses, .breath, .fermata, .accent, .circle]
    static let dynamics: [Stamp] = [.pp, .p, .mp, .mf, .f, .ff]
    static let fingerings: [Stamp] = [.finger0, .finger1, .finger2, .finger3, .finger4]

    var label: String {
        switch self {
        case .downBow: "Down-bow"
        case .upBow: "Up-bow"
        case .eyeglasses: "Eyeglasses"
        case .breath: "Breath"
        case .fermata: "Fermata"
        case .accent: "Accent"
        case .circle: "Circle"
        case .pp: "pp"
        case .p: "p"
        case .mp: "mp"
        case .mf: "mf"
        case .f: "f"
        case .ff: "ff"
        case .finger0: "0"
        case .finger1: "1"
        case .finger2: "2"
        case .finger3: "3"
        case .finger4: "4"
        }
    }

    /// Rendered height in PDF points when placed on a page.
    var placedHeight: CGFloat {
        switch self {
        case .downBow, .upBow: 10
        case .eyeglasses: 9
        case .breath: 9
        case .fermata: 11
        case .accent: 8
        case .circle: 16
        case .pp, .p, .mp, .mf, .f, .ff: 12
        case .finger0, .finger1, .finger2, .finger3, .finger4: 10
        }
    }

    /// Glyph strokes in a normalized box (unit height; width follows aspect).
    var glyph: [[CGPoint]] {
        var pen = GlyphPen()
        switch self {
        case .downBow:
            pen.move(0.05, 0.75); pen.line(0.05, 0.12); pen.line(1.15, 0.12); pen.line(1.15, 0.75)
        case .upBow:
            pen.move(0.12, 0.05); pen.line(0.45, 0.95); pen.line(0.78, 0.05)
        case .eyeglasses:
            pen.move(0.55, 0.5)
            pen.ellipse(cx: 0.3, cy: 0.5, rx: 0.26, ry: 0.42)
            pen.line(1.1, 0.5)
            pen.ellipse(cx: 1.36, cy: 0.5, rx: 0.26, ry: 0.42, from: .pi)
        case .breath:
            pen.move(0.5, 0.05)
            pen.curve(to: CGPoint(x: 0.2, y: 0.95), c1: CGPoint(x: 0.62, y: 0.4), c2: CGPoint(x: 0.42, y: 0.75))
        case .fermata:
            pen.move(0.05, 0.8)
            pen.curve(to: CGPoint(x: 1.15, y: 0.8), c1: CGPoint(x: 0.2, y: -0.15), c2: CGPoint(x: 1.0, y: -0.15))
            pen.move(0.57, 0.62)
            pen.ellipse(cx: 0.6, cy: 0.65, rx: 0.045, ry: 0.045)
        case .accent:
            pen.move(0.05, 0.1); pen.line(1.0, 0.5); pen.line(0.05, 0.9)
        case .circle:
            pen.move(1.0, 0.5)
            pen.ellipse(cx: 0.5, cy: 0.5, rx: 0.5, ry: 0.48)
        case .p:
            pen.pLetter(offsetX: 0)
        case .pp:
            pen.pLetter(offsetX: 0); pen.pLetter(offsetX: 0.55)
        case .f:
            pen.fLetter(offsetX: 0)
        case .ff:
            pen.fLetter(offsetX: 0); pen.fLetter(offsetX: 0.42)
        case .mp:
            pen.mLetter(offsetX: 0); pen.pLetter(offsetX: 0.75)
        case .mf:
            pen.mLetter(offsetX: 0); pen.fLetter(offsetX: 0.85)
        case .finger0:
            pen.move(0.5, 0.08)
            pen.ellipse(cx: 0.3, cy: 0.5, rx: 0.24, ry: 0.44, from: -.pi / 2)
        case .finger1:
            pen.move(0.15, 0.3); pen.line(0.38, 0.08); pen.line(0.38, 0.92)
        case .finger2:
            pen.move(0.12, 0.3)
            pen.curve(to: CGPoint(x: 0.52, y: 0.42), c1: CGPoint(x: 0.14, y: -0.08), c2: CGPoint(x: 0.6, y: 0.05))
            pen.line(0.12, 0.92)
            pen.line(0.58, 0.92)
        case .finger3:
            pen.move(0.12, 0.22)
            pen.curve(to: CGPoint(x: 0.3, y: 0.5), c1: CGPoint(x: 0.24, y: -0.05), c2: CGPoint(x: 0.62, y: 0.3))
            pen.curve(to: CGPoint(x: 0.12, y: 0.82), c1: CGPoint(x: 0.68, y: 0.72), c2: CGPoint(x: 0.3, y: 1.05))
        case .finger4:
            pen.move(0.52, 0.08); pen.line(0.12, 0.58); pen.line(0.66, 0.58)
            pen.move(0.52, 0.08); pen.line(0.52, 0.92)
        }
        return pen.finish()
    }

    /// The stamp as PencilKit strokes, centered at `center` (page/PDF points).
    func strokes(centeredAt center: CGPoint, color: UIColor) -> [PKStroke] {
        let paths = glyph
        let height = placedHeight
        let allPoints = paths.flatMap { $0 }
        guard !allPoints.isEmpty else { return [] }

        let minX = allPoints.map(\.x).min()!
        let maxX = allPoints.map(\.x).max()!
        let minY = allPoints.map(\.y).min()!
        let maxY = allPoints.map(\.y).max()!
        let glyphW = max(maxX - minX, 0.001)
        let glyphH = max(maxY - minY, 0.001)
        let scale = height / glyphH
        let origin = CGPoint(
            x: center.x - glyphW * scale / 2,
            y: center.y - height / 2
        )

        let ink = PKInk(.pen, color: color)
        return paths.map { points in
            let strokePoints = points.enumerated().map { idx, pt in
                PKStrokePoint(
                    location: CGPoint(
                        x: origin.x + (pt.x - minX) * scale,
                        y: origin.y + (pt.y - minY) * scale
                    ),
                    timeOffset: TimeInterval(idx) * 0.008,
                    size: CGSize(width: 1.5, height: 1.5),
                    opacity: 0.92,
                    force: 1,
                    azimuth: 0,
                    altitude: .pi / 2
                )
            }
            return PKStroke(ink: ink, path: PKStrokePath(controlPoints: strokePoints, creationDate: Date()))
        }
    }
}

/// Tiny sampling pen: records dense polyline points so B-spline stroke paths
/// keep corners crisp and curves handwritten.
struct GlyphPen {
    private var strokes: [[CGPoint]] = []
    private var current: [CGPoint] = []
    private let step: CGFloat = 0.045

    mutating func move(_ x: CGFloat, _ y: CGFloat) {
        flush()
        current = [CGPoint(x: x, y: y)]
    }

    mutating func line(_ x: CGFloat, _ y: CGFloat) {
        guard let from = current.last else { return }
        let to = CGPoint(x: x, y: y)
        let dist = hypot(to.x - from.x, to.y - from.y)
        let steps = max(Int(dist / step), 1)
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            current.append(CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
        }
    }

    mutating func curve(to: CGPoint, c1: CGPoint, c2: CGPoint) {
        guard let from = current.last else { return }
        let steps = 22
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let mt = 1 - t
            let x = mt * mt * mt * from.x + 3 * mt * mt * t * c1.x + 3 * mt * t * t * c2.x + t * t * t * to.x
            let y = mt * mt * mt * from.y + 3 * mt * mt * t * c1.y + 3 * mt * t * t * c2.y + t * t * t * to.y
            current.append(CGPoint(x: x, y: y))
        }
    }

    /// Full ellipse starting from angle `from`, sweeping 2π.
    mutating func ellipse(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, from start: CGFloat = 0) {
        let steps = 26
        for i in 0...steps {
            let a = start + CGFloat(i) / CGFloat(steps) * 2 * .pi
            let pt = CGPoint(x: cx + cos(a) * rx, y: cy + sin(a) * ry)
            if current.isEmpty {
                current = [pt]
            } else {
                current.append(pt)
            }
        }
    }

    // Single-stroke handwritten letterforms for dynamics.
    mutating func pLetter(offsetX dx: CGFloat) {
        move(0.18 + dx, 0.3)
        line(0.08 + dx, 0.95)
        move(0.13 + dx, 0.52)
        curve(to: CGPoint(x: 0.16 + dx, y: 0.62),
              c1: CGPoint(x: 0.3 + dx, y: 0.1), c2: CGPoint(x: 0.52 + dx, y: 0.62))
    }

    mutating func fLetter(offsetX dx: CGFloat) {
        move(0.42 + dx, 0.12)
        curve(to: CGPoint(x: 0.18 + dx, y: 0.55),
              c1: CGPoint(x: 0.22 + dx, y: 0.02), c2: CGPoint(x: 0.2 + dx, y: 0.3))
        curve(to: CGPoint(x: 0.02 + dx, y: 0.95),
              c1: CGPoint(x: 0.16 + dx, y: 0.8), c2: CGPoint(x: 0.12 + dx, y: 0.95))
        move(0.05 + dx, 0.45)
        line(0.38 + dx, 0.42)
    }

    mutating func mLetter(offsetX dx: CGFloat) {
        move(0.05 + dx, 0.9)
        line(0.12 + dx, 0.45)
        curve(to: CGPoint(x: 0.3 + dx, y: 0.9), c1: CGPoint(x: 0.26 + dx, y: 0.3), c2: CGPoint(x: 0.3 + dx, y: 0.6))
        curve(to: CGPoint(x: 0.5 + dx, y: 0.9), c1: CGPoint(x: 0.44 + dx, y: 0.3), c2: CGPoint(x: 0.5 + dx, y: 0.6))
    }

    private mutating func flush() {
        if current.count > 1 { strokes.append(current) }
        current = []
    }

    mutating func finish() -> [[CGPoint]] {
        flush()
        return strokes
    }
}
