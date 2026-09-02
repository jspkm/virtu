import Foundation

/// The two things on the bench that make noise.
///
/// Exists so that "is anything audible right now" is asked in one place. The
/// nav rail needs it, and anything that later wants to stop a running tool
/// from somewhere else needs it too — and neither should have to know that
/// the tuner has two separate ways of being busy.
enum PracticeTools {

    static var isRunning: Bool {
        Metronome.shared.isRunning || Tuner.shared.isSounding || Tuner.shared.isListening
    }

    static func stopAll() {
        Metronome.shared.stop()
        Tuner.shared.stopSounding()
        Tuner.shared.stopListening()
    }
}
