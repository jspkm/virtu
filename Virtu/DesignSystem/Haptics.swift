import UIKit

/// The app's haptic vocabulary. Perform mode is silent by design — callers are
/// responsible for never firing haptics there except where the spec allows.
enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func rigid() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
