import Foundation

/// How a beat is divided, expressed as where the extra clicks fall inside it.
///
/// Beat fractions rather than durations, so the same table is correct at 15
/// and at 500 — the bar buffer multiplies these by the beat's frame count and
/// writes a click at each. The beat itself is not listed: it is the beat.
enum Subdivision: String, CaseIterable, Identifiable {
    case quarter, eighths, triplets, sixteenths, swing, dotted

    var id: String { rawValue }

    var offsets: [Double] {
        switch self {
        case .quarter:    []
        case .eighths:    [1.0 / 2]
        case .triplets:   [1.0 / 3, 2.0 / 3]
        case .sixteenths: [1.0 / 4, 2.0 / 4, 3.0 / 4]
        // Two thirds, not a half. A shuffle played as even eighths is the
        // most common way to practise swing wrong.
        case .swing:      [2.0 / 3]
        // Dotted eighth plus sixteenth: the short note arrives at three
        // quarters of the beat.
        case .dotted:     [3.0 / 4]
        }
    }

    /// Compact enough for a six-across row on the narrowest card. Figures
    /// rather than note glyphs: no bundled face carries U+2669 and friends,
    /// and a row of system-font fallbacks beside our own mono digits reads as
    /// a mistake.
    var label: String {
        switch self {
        case .quarter: "1"
        case .eighths: "2"
        case .triplets: "3"
        case .sixteenths: "4"
        case .swing: "Swing"
        case .dotted: "Dotted"
        }
    }

    var spoken: String {
        switch self {
        case .quarter: "Quarter notes"
        case .eighths: "Eighth notes"
        case .triplets: "Triplets"
        case .sixteenths: "Sixteenth notes"
        case .swing: "Swing"
        case .dotted: "Dotted eighth and sixteenth"
        }
    }
}
