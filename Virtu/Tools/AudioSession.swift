import AVFoundation
import UIKit

/// The one place the audio session is configured — and the one place that
/// decides whether the screen may sleep.
///
/// This exists because there are now two practice tools and they do not want
/// the same session. The metronome plays; the tuner, while it is listening,
/// records. Left to themselves each would call `setCategory` on the way in and
/// `setActive(false)` on the way out, which means the last one to start
/// decides the category for both and the *first* one to stop deactivates the
/// session underneath the other. Starting the tuner would have silenced a
/// running click, and stopping the click would have deafened the tuner.
///
/// So nothing sets the category directly. A tool claims what it needs and
/// releases it when it stops; the category is derived from every claim
/// standing at that moment, and the session is torn down only when the last
/// one goes.
///
/// Main-thread only, like the tools that call it.
final class AudioSession {

    static let shared = AudioSession()

    enum Need {
        case play
        /// Implies play as well: `.playAndRecord` covers both.
        case record
    }

    private var claims: [String: Need] = [:]

    private init() {}

    /// Returns false if the session could not be put into the shape the
    /// caller asked for — in which case the caller must not start.
    @discardableResult
    func claim(_ need: Need, by owner: String) -> Bool {
        let previous = claims[owner]
        claims[owner] = need
        guard apply() else {
            claims[owner] = previous
            _ = apply()
            return false
        }
        return true
    }

    func release(_ owner: String) {
        guard claims.removeValue(forKey: owner) != nil else { return }
        _ = apply()
    }

    private func apply() -> Bool {
        let session = AVAudioSession.sharedInstance()

        guard !claims.isEmpty else {
            // The reading surface owns the idle timer while a score is open
            // and sets it on appear, so releasing it here cannot strand a lit
            // screen — and cannot leave one lit either.
            UIApplication.shared.isIdleTimerDisabled = false
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
            return true
        }

        do {
            if claims.values.contains(where: { $0 == .record }) {
                // `.measurement` turns off the input chain's automatic gain,
                // equalisation and noise suppression. All three are tuned to
                // make speech intelligible, and all three move a pitch — a
                // tuner has to hear the string, not a helpful version of it.
                //
                // The cost is paid by the other tool: `.measurement` also
                // quietens output, so a metronome left running while the
                // tuner listens gets softer. Accepted — an inaudible click
                // is recoverable by stopping the tuner, and a needle that
                // moves with the bow's dynamic is not recoverable at all.
                try session.setCategory(
                    .playAndRecord, mode: .measurement,
                    options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP]
                )
            } else {
                // `.playback` so the ring/silent switch cannot silence a
                // practice tool; `.mixWithOthers` so starting the click does
                // not stop the recording someone is playing along to.
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            }
            try session.setActive(true)
            // A tool you started and then stopped watching still has to be
            // there when you look up from the cello.
            UIApplication.shared.isIdleTimerDisabled = true
            return true
        } catch {
            // The caller does not start. There is nothing useful to say to a
            // musician about an audio session that would not open.
            return false
        }
    }
}
