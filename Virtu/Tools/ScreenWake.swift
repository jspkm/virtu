import UIKit

/// Whether the screen may sleep — refcounted, because more than one thing
/// wants it awake and they overlap.
///
/// `isIdleTimerDisabled` is a single global flag, and until 2026-09-01 two
/// owners wrote it directly: the reading surface on appear, and the audio
/// session whenever a practice tool started or stopped. Whichever wrote last
/// won, so stopping a metronome while a score was open let the screen sleep
/// mid-piece and nothing re-armed it — `onAppear` had already fired and would
/// not fire again. Nobody could reach that path while Reading and Tools were
/// alternate destinations; a stop control that works from anywhere is what
/// makes it reachable.
///
/// Main-thread only, like everything that claims it.
final class ScreenWake {

    static let shared = ScreenWake()

    private var claims: Set<String> = []

    /// Injectable so a test can watch the decision without an application.
    var apply: (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 }

    private init() {}

    /// True while anything is holding the screen awake.
    var isAwake: Bool { !claims.isEmpty }

    func claim(_ owner: String) {
        let (inserted, _) = claims.insert(owner)
        guard inserted else { return }
        apply(true)
    }

    func release(_ owner: String) {
        guard claims.remove(owner) != nil else { return }
        apply(!claims.isEmpty)
    }
}
