import AVFoundation
import Foundation

/// The click, on a sample-accurate clock.
///
/// PRD §10 is explicit that this may not be a `Timer`: a metronome that drifts
/// is worse than none, because a musician trusts it. So one bar of audio is
/// synthesised into a buffer — the clicks are AT their sample offsets — and
/// looped by `AVAudioPlayerNode`. The gap between beat one and beat two is
/// then a property of the file, not of when a timer happened to fire.
///
/// The lamps read the same clock (`currentBeat` asks the player where it is),
/// so what you see and what you hear cannot disagree.
///
/// The engine, the loop and the playhead are `LoopPlayer`; the session is
/// `AudioSession`. Both were written here first and both moved out when the
/// tuner turned out to need exactly the same machine.
///
/// Shared, not owned by the Tools screen: PRD §5 requires that leaving a
/// surface never stops a running metronome. You can start it and go read.
@Observable
final class Metronome {

    static let shared = Metronome()

    // Range and defaults from the design handoff (`Virtu.dc.html`, Tools).
    static let minBPM = 30
    static let maxBPM = 220

    private(set) var isRunning = false

    // Clamped in an explicit setter over a private store, NOT in a didSet.
    // @Observable rewrites a stored property into a computed one, so
    // `bpm = clamp(bpm)` inside `bpm`'s own didSet re-enters the setter and
    // recurses until the stack guard page is hit. A plain stored property
    // would not — the macro is what removes the protection.

    private var storedBPM = 92
    private var storedBeatsPerBar = 4

    var bpm: Int {
        get { storedBPM }
        set {
            let clamped = min(max(newValue, Self.minBPM), Self.maxBPM)
            guard clamped != storedBPM else { return }
            storedBPM = clamped
            defaults.set(clamped, forKey: "metronomeBPM")
            reloadIfRunning()
        }
    }

    /// Beats to the bar; beat one is accented. Not in the handoff mock, which
    /// draws a fixed four — but the seed repertoire alone has a Sarabande and
    /// two Menuets in three, and a metronome that can only count four is a
    /// metronome you put down.
    var beatsPerBar: Int {
        get { storedBeatsPerBar }
        set {
            let clamped = min(max(newValue, 2), 6)
            guard clamped != storedBeatsPerBar else { return }
            storedBeatsPerBar = clamped
            defaults.set(clamped, forKey: "metronomeBeatsPerBar")
            reloadIfRunning()
        }
    }

    /// The Italian, in the composer's vocabulary rather than a number.
    /// Thresholds are the handoff's, exactly.
    var tempoWord: String {
        switch bpm {
        case ..<60: "largo"
        case ..<76: "adagio"
        case ..<96: "andante"
        case ..<112: "moderato"
        case ..<140: "allegro"
        default: "presto"
        }
    }

    // MARK: - Audio

    private static let claimID = "metronome"

    // @ObservationIgnored because the macro rewrites stored properties into
    // computed ones, and a computed property cannot be lazy. The same rewrite
    // is what makes the didSet above recurse — one macro, two traps.
    @ObservationIgnored
    private lazy var loop = LoopPlayer { [weak self] format in
        self?.makeBarBuffer(format: format)
    }

    private let defaults: UserDefaults

    // The click itself: a sine burst under a steep exponential decay. Short
    // enough to be a transient rather than a tone — a wood block, not a beep.
    private static let accentHz = 1_600.0
    private static let beatHz = 1_050.0
    private static let clickSeconds = 0.035
    private static let decay = 90.0
    private static let level = 0.5

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Through the setters, which do the clamping.
        if let stored = defaults.object(forKey: "metronomeBPM") as? Int {
            bpm = stored
        }
        if let stored = defaults.object(forKey: "metronomeBeatsPerBar") as? Int {
            beatsPerBar = stored
        }
    }

    // MARK: - Transport

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        guard !isRunning else { return }
        guard AudioSession.shared.claim(.play, by: Self.claimID) else { return }
        guard loop.start() else {
            // A metronome that cannot open the audio session simply does not
            // start. There is nothing useful to say and nothing to recover.
            AudioSession.shared.release(Self.claimID)
            return
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        loop.stop()
        AudioSession.shared.release(Self.claimID)
    }

    /// Tempo and meter changes take effect on the next bar by restarting the
    /// loop: the buffer IS the tempo, so there is nothing to adjust in place.
    private func reloadIfRunning() {
        loop.reload()
    }

    // MARK: - The lamps

    /// Which beat is sounding, straight from the audio clock — 0-based, and
    /// `nil` when nothing is running. Derived rather than counted, so it
    /// cannot drift away from what you are hearing.
    var currentBeat: Int? {
        guard isRunning, let seconds = loop.elapsedSeconds else { return nil }
        let beat = Int((seconds / beatDuration).rounded(.down))
        return ((beat % beatsPerBar) + beatsPerBar) % beatsPerBar
    }

    private var beatDuration: Double { 60.0 / Double(bpm) }

    // MARK: - Tap tempo

    private var taps: [Date] = []
    /// The handoff's window. Longer and a pause between phrases reads as a
    /// tempo; shorter and a slow largo cannot be tapped at all.
    private static let tapWindow: TimeInterval = 2.6

    /// Returns true once a tempo has actually been derived — two taps.
    ///
    /// `at` is injectable so a test can tap on a clock it controls; the
    /// alternative was a #if DEBUG twin of this method, which is exactly the
    /// arrangement where the tested code and the shipped code drift apart.
    @discardableResult
    func tap(at date: Date = Date()) -> Bool {
        taps = taps.filter { date.timeIntervalSince($0) < Self.tapWindow } + [date]
        guard taps.count >= 2 else { return false }
        let intervals = zip(taps.dropFirst(), taps).map { $0.timeIntervalSince($1) }
        let average = intervals.reduce(0, +) / Double(intervals.count)
        guard average > 0 else { return false }
        bpm = Int((60.0 / average).rounded())
        return true
    }

    // MARK: - The bar

    /// One bar, clicks written at their exact sample offsets.
    private func makeBarBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        guard rate > 0 else { return nil }
        let beatFrames = Int((rate * beatDuration).rounded())
        guard beatFrames > 0 else { return nil }
        let totalFrames = beatFrames * beatsPerBar

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)
        ) else { return nil }
        buffer.frameLength = AVAudioFrameCount(totalFrames)

        let channelCount = Int(format.channelCount)
        guard let channels = buffer.floatChannelData else { return nil }
        for channel in 0..<channelCount {
            channels[channel].update(repeating: 0, count: totalFrames)
        }

        let clickFrames = min(Int(rate * Self.clickSeconds), beatFrames)
        for beat in 0..<beatsPerBar {
            let offset = beat * beatFrames
            let frequency = beat == 0 ? Self.accentHz : Self.beatHz
            for i in 0..<clickFrames {
                let t = Double(i) / rate
                let value = Float(sin(2 * .pi * frequency * t) * exp(-t * Self.decay) * Self.level)
                for channel in 0..<channelCount {
                    channels[channel][offset + i] = value
                }
            }
        }
        return buffer
    }

    #if DEBUG
    /// Test hooks. The buffer is the tempo, so its length and where the
    /// transients sit is the only place correctness is observable.
    func testBarBuffer(sampleRate: Double = 44_100) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        else { return nil }
        return makeBarBuffer(format: format)
    }
    #endif
}
