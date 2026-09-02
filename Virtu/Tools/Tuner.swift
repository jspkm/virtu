import AVFoundation
import Foundation

/// The tuner: sound the A, or listen to the string.
///
/// The design handoff draws the first half — a reference A with four buttons
/// under it — and PRD §14 has carried a `tuningPreset` for it the whole time.
/// The second half is what a working musician meant on 2026-08-27 by "can't
/// find the tuner": a thing that tells you how far off you are, not one that
/// only tells you what to aim at.
///
/// The two halves take turns, and that is not a limitation to be engineered
/// away. An iPad's microphone and its speaker are a hand apart; a tuner
/// sounding an A and listening at the same time hears its own drone and
/// reports, with total confidence, that you are perfectly in tune. A pitch
/// pipe and a tuner have always been two things you pick up one at a time.
///
/// Shared, not owned by the Tools screen — PRD §5 requires that leaving a
/// surface never stops a running tool, and the metronome already works that
/// way.
@Observable
final class Tuner {

    static let shared = Tuner()

    /// The handoff's four references, in the order it draws them: modern
    /// orchestral, standard, the one people ask for, and baroque.
    static let references: [Double] = [442, 440, 432, 415]

    /// Inside five cents the ear stops hearing the difference against a
    /// drone, and a needle that will not settle is a needle you stop
    /// believing. This is where the reading turns.
    static let inTuneCents = 5.0

    // Two ids, not one. The arbiter keys claims by owner, so a single id
    // means a release for either half drops both — harmless while the two are
    // mutually exclusive, and a silent bug the moment they are not.
    private static let droneClaimID = "tuner.drone"
    private static let micClaimID = "tuner.mic"

    private let defaults: UserDefaults

    // Clamped in an explicit setter over a private store, NOT in a didSet:
    // @Observable rewrites a stored property into a computed one, so writing
    // to a property inside its own didSet re-enters the setter and recurses.
    // The metronome learned this the hard way.
    private var storedReferenceHz = 442.0

    /// Which A everything is measured against. Snapped to one of the four —
    /// stored in hertz rather than as a preset index so that a future free
    /// reference is a wider setter, not a migration.
    var referenceHz: Double {
        get { storedReferenceHz }
        set {
            let nearest = Self.references.min {
                abs($0 - newValue) < abs($1 - newValue)
            } ?? 442
            guard nearest != storedReferenceHz else { return }
            storedReferenceHz = nearest
            defaults.set(nearest, forKey: "tunerReferenceHz")
            // The drone IS the reference, so changing it is a new loop.
            drone.reload()
        }
    }

    private(set) var isSounding = false
    private(set) var isListening = false

    /// True once the microphone has actually been refused, so the card can
    /// say so instead of leaving a dead button.
    private(set) var micDenied = false

    /// The frequency currently being heard, after smoothing. `nil` when
    /// nothing is.
    private(set) var heardHz: Double?

    /// What that frequency means against the A in force. Derived rather than
    /// stored, so tapping A 415 re-reads the string you are already holding
    /// instead of waiting for the next bow stroke.
    var reading: Pitch? {
        heardHz.map { Pitch(frequency: $0, referenceA: storedReferenceHz) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.object(forKey: "tunerReferenceHz") as? Double {
            referenceHz = stored          // through the setter, which snaps
        }
        drone.fadeOutSeconds = 0.04
    }

    // MARK: - Sounding the A

    // @ObservationIgnored because the macro rewrites stored properties into
    // computed ones, and a computed property cannot be lazy.
    @ObservationIgnored
    private lazy var drone = LoopPlayer { [weak self] format in
        self?.makeDroneBuffer(format: format)
    }

    /// A continuous tone is a much longer thing to be in a room than a click,
    /// so it sits well below the metronome's level.
    private static let droneLevel = 0.3

    /// The fundamental and four quiet partials. A bare sine is the worst
    /// possible thing to tune against — it has no beats to hear and it is
    /// hard to place in an octave. A few harmonics make it a reed, which is
    /// what an orchestra actually tunes to.
    private static let partials: [Double] = [1, 0.34, 0.18, 0.08, 0.04]

    func toggleSounding() {
        isSounding ? stopSounding() : startSounding()
    }

    func startSounding() {
        guard !isSounding else { return }
        stopListening()
        guard AudioSession.shared.claim(.play, by: Self.droneClaimID) else { return }
        guard drone.start() else {
            AudioSession.shared.release(Self.droneClaimID)
            return
        }
        isSounding = true
    }

    func stopSounding() {
        guard isSounding else { return }
        isSounding = false
        // The drone fades out over ~40ms, so `stop()` returns before the
        // engine has actually stopped. Releasing the session here would call
        // setActive(false) on a session still running I/O — which fails with
        // "is busy", is swallowed by the try?, and leaves the arbiter
        // believing it tore down a session that is still up. So the release
        // waits for the fade.
        drone.stop { [weak self] in
            AudioSession.shared.release(Self.droneClaimID)
            _ = self
        }
    }

    /// One loop of the reference tone.
    ///
    /// The loop holds a whole number of cycles, which is what makes the wrap
    /// silent: end at the same phase you began at and there is no
    /// discontinuity to hear. It is also why the pitch is exactly the number
    /// on the button — the period is set by arithmetic, not by rounding a
    /// buffer length to something convenient.
    private func makeDroneBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let hz = storedReferenceHz
        guard rate > 0, hz > 0 else { return nil }

        // About a second's worth, snapped to whole cycles.
        let cycles = max(1, Int(hz.rounded()))
        let frames = Int((Double(cycles) * rate / hz).rounded())
        guard frames > 0 else { return nil }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)
        ) else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)

        let channelCount = Int(format.channelCount)
        guard let channels = buffer.floatChannelData else { return nil }

        let norm = Self.partials.reduce(0, +)
        for i in 0..<frames {
            let t = Double(i) / rate
            var sum = 0.0
            for (index, amplitude) in Self.partials.enumerated() {
                sum += amplitude * sin(2 * .pi * hz * Double(index + 1) * t)
            }
            let value = Float(sum / norm * Self.droneLevel)
            for channel in 0..<channelCount {
                channels[channel][i] = value
            }
        }
        return buffer
    }

    // MARK: - Listening

    private let input = AVAudioEngine()
    // None of this is anything a view reads, and `window` in particular is
    // written from the tap's thread — observation machinery has no business
    // running there.
    /// Guards `window` and `detector`, which the tap thread reads and writes
    /// and main reassigns. `removeTap` does not promise that an in-flight
    /// callback has returned, so stopping and restarting — a headset arriving
    /// at a different sample rate, say — can reassign the buffer out from
    /// under a tap that is still inside it. Uncontended in the normal case.
    @ObservationIgnored private let analysisLock = NSLock()
    @ObservationIgnored private var tapInstalled = false
    @ObservationIgnored private var detector: PitchDetector?
    @ObservationIgnored private var window = [Float]()

    func toggleListening() {
        isListening ? stopListening() : startListening()
    }

    func startListening() {
        guard !isListening else { return }
        stopSounding()
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            beginListening()
        case .denied:
            micDenied = true
        case .undetermined:
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    granted ? self.beginListening() : (self.micDenied = true)
                }
            }
        @unknown default:
            micDenied = true
        }
    }

    private func beginListening() {
        micDenied = false
        // The category has to be `.playAndRecord` BEFORE the input node's
        // format is asked for; under `.playback` there is no input and the
        // format comes back as nothing.
        guard AudioSession.shared.claim(.record, by: Self.micClaimID) else { return }

        let node = input.inputNode
        let format = node.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            AudioSession.shared.release(Self.micClaimID)
            return
        }

        if tapInstalled {
            node.removeTap(onBus: 0)
            tapInstalled = false
        }
        analysisLock.lock()
        prepareAnalysis(sampleRate: format.sampleRate)
        analysisLock.unlock()

        node.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self] buffer, _ in
            self?.consume(buffer)
        }
        tapInstalled = true

        input.prepare()
        do {
            try input.start()
        } catch {
            node.removeTap(onBus: 0)
            tapInstalled = false
            AudioSession.shared.release(Self.micClaimID)
            return
        }
        isListening = true
    }

    func stopListening() {
        guard isListening else { return }
        isListening = false
        // Anything already computed against the old generation is stale.
        listenGeneration &+= 1
        if tapInstalled {
            input.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        input.stop()
        heardHz = nil
        recent.removeAll()
        outliers.removeAll()
        silentFrames = 0
        AudioSession.shared.release(Self.micClaimID)
    }

    /// Called on the tap's own thread. Slides the newest samples into the
    /// analysis window, runs the detector there — it is well under a
    /// millisecond and the alternative is copying the window to another
    /// queue — and publishes on the main thread.
    ///
    /// Not private, for the same reason `hear` is not: this is everything
    /// between a microphone buffer and a reading, and handing it buffers is
    /// the only way to exercise that without a microphone in the room.
    func consume(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        analysisLock.lock()
        defer { analysisLock.unlock() }
        prepareAnalysis(sampleRate: buffer.format.sampleRate)
        guard let detector else { return }
        let incoming = Int(buffer.frameLength)
        let size = window.count
        guard incoming > 0, size > 0 else { return }

        window.withUnsafeMutableBufferPointer { destination in
            guard let base = destination.baseAddress else { return }
            if incoming >= size {
                base.update(from: data + (incoming - size), count: size)
            } else {
                // Slide what is still current to the front, then append.
                memmove(base, base + incoming, (size - incoming) * MemoryLayout<Float>.size)
                (base + (size - incoming)).update(from: data, count: incoming)
            }
        }

        let hz = detector.frequency(in: window)
        let generation = listenGeneration
        DispatchQueue.main.async { [weak self] in
            self?.hear(hz, generation: generation)
        }
    }

    /// The analysis window and the detector that reads it, sized to whatever
    /// rate the hardware turned out to be running at. Rebuilt only when that
    /// rate changes, so it costs nothing per buffer.
    private func prepareAnalysis(sampleRate: Double) {
        guard sampleRate > 0 else { return }
        guard detector?.sampleRate != sampleRate else { return }
        let detector = PitchDetector(sampleRate: sampleRate)
        self.detector = detector
        // Sized by the detector, which needs a longer window at a higher rate
        // to still reach its lowest note.
        window = [Float](repeating: 0, count: detector.analysisFrames)
    }

    // MARK: - Steadying the needle

    @ObservationIgnored private var recent: [Double] = []
    @ObservationIgnored private var outliers: [Double] = []
    @ObservationIgnored private var silentFrames = 0

    /// How many silent analyses to sit through before the reading clears.
    /// About a third of a second — long enough that lifting the bow between
    /// strokes does not blank the card mid-adjustment.
    static let holdFrames = 8

    /// How many consecutive readings from somewhere else it takes to move.
    static let jumpFrames = 2

    /// Bumped by `stopListening`, so a reading computed before the stop can
    /// tell that it is stale.
    @ObservationIgnored private(set) var listenGeneration = 0

    /// One analysis in, the published reading out. Not private: the whole of
    /// the needle's behaviour lives here — what it ignores and what it
    /// follows — and it is the half of this class that can be tested without
    /// a microphone in the room.
    /// `generation` is what the tap held when it started analysing. A tap
    /// callback that was mid-analysis when Listen was switched off still has
    /// its main-queue hop in flight and lands *after* `stopListening` has
    /// cleared everything; without this it repopulates the reading and the
    /// card shows a phantom string for ever, because no further tap will
    /// arrive to clear it. Callers that are not the tap — tests, and anything
    /// driving the needle directly — pass nothing and are always current.
    func hear(_ hz: Double?, generation: Int? = nil) {
        if let generation, generation != listenGeneration { return }
        guard let hz else {
            silentFrames += 1
            if silentFrames > Self.holdFrames {
                recent.removeAll()
                outliers.removeAll()
                heardHz = nil
            }
            return
        }
        silentFrames = 0

        if let current = heardHz, abs(12 * log2(hz / current)) > 1 {
            // More than a semitone away is either a new string or one bad
            // frame, and on a bowed low string an octave slip is common
            // enough that the needle must not follow the first one it sees.
            // It follows the second.
            // Each candidate is checked against the previous candidate, not
            // only against the note we are on. Two readings that are both far
            // from the current note but far from *each other* are two
            // different artefacts, not a string change, and must not confirm
            // one another.
            if let previous = outliers.last, abs(12 * log2(hz / previous)) > 1 {
                outliers = [hz]
                return
            }
            outliers.append(hz)
            guard outliers.count >= Self.jumpFrames else { return }
            recent = outliers
            outliers.removeAll()
            heardHz = Self.median(of: recent)
            return
        }

        outliers.removeAll()
        recent.append(hz)
        if recent.count > 5 { recent.removeFirst() }
        // The median, not the mean: one wild frame inside the run should not
        // drag the needle a few cents, and with a median it does not move it
        // at all.
        heardHz = Self.median(of: recent)
    }

    private static func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    #if DEBUG
    /// Test hook. The drone's correctness is entirely in the buffer — that it
    /// holds whole cycles of exactly the frequency on the button — so the
    /// buffer is the only place to look.
    func testDroneBuffer(sampleRate: Double = 44_100) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        else { return nil }
        return makeDroneBuffer(format: format)
    }
    #endif
}
