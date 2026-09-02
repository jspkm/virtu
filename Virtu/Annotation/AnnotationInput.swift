import PencilKit
import UIKit

/// Who is allowed to draw.
///
/// PRD §0.2 is one sentence with two halves, and both matter: fingers never
/// draw when a Pencil is present, *and* the escape hatch is never on by
/// default. Written as a pure function over two booleans so the rule can be
/// tested without a canvas, a device, or a Pencil — which is the only way it
/// can be tested at all.
enum AnnotationInput {

    static func policy(
        pencilEverPaired: Bool, fingerDrawing: Bool
    ) -> PKCanvasViewDrawingPolicy {
        // The paired case is checked first and answers on its own. `.default`
        // would have been tempting and is wrong: it silently enables finger
        // drawing on a Pencil-less iPad, which is exactly the auto-enabling
        // §0.2 forbids.
        guard !pencilEverPaired else { return .pencilOnly }
        return fingerDrawing ? .anyInput : .pencilOnly
    }

    /// Which touch types reach the ink pipeline under a given policy.
    ///
    /// This is the gate that actually decides who can draw. `drawingPolicy`
    /// governs PencilKit, and PencilKit stopped inking on 2026-08-20 — ink is
    /// observed and committed by our own recognizer, whose `allowedTouchTypes`
    /// is what a fingertip has to get past. Derived from the policy rather
    /// than set beside it, so the two can never disagree.
    static func allowedTouchTypes(for policy: PKCanvasViewDrawingPolicy) -> [NSNumber] {
        let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        guard policy == .anyInput else { return [pencil] }
        return [pencil, NSNumber(value: UITouch.TouchType.direct.rawValue)]
    }

    /// Whether to show the hatch at all. On an iPad that has seen a Pencil it
    /// is a setting nobody should ever want, so it is not offered.
    static func offersHatch(_ preferences: Preferences) -> Bool {
        !preferences.pencilEverPaired
    }
}
