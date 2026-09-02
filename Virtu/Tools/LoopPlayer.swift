import AVFoundation

/// One synthesised buffer, looped on the audio clock.
///
/// Both practice tools are this same machine, which is why it is one file
/// rather than two copies. The click is a bar of audio with the beats AT
/// their sample offsets; the tuning drone is a whole number of cycles of a
/// tone. PRD §10 forbids a `Timer` for the first, and the same reasoning
/// forbids it for the second: the gap between two beats and the pitch of a
/// held A are properties of the buffer, not of when something happened to
/// fire.
///
/// The caller supplies the synthesis and nothing else. Everything here is
/// the plumbing that was already written once for the metronome — engine
/// setup, the loop, where the playhead is, and rebuilding all of it when the
/// hardware changes shape underneath.
///
/// Main-thread only, like the tools that call it.
final class LoopPlayer {

    /// Builds the loop for whatever format the output turns out to have.
    /// Called again on every start, so a tempo or a pitch change is simply a
    /// new buffer.
    private let makeBuffer: (AVAudioFormat) -> AVAudioPCMBuffer?

    /// How long to ramp the level down before stopping. A tone cut mid-cycle
    /// ticks; a click track is silence between the clicks and does not, so
    /// this is zero for the metronome and a few tens of milliseconds for the
    /// drone.
    var fadeOutSeconds: Double = 0

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var attached = false
    private var needsReconnect = true
    private(set) var isPlaying = false

    private var configurationObserver: NSObjectProtocol?

    init(makeBuffer: @escaping (AVAudioFormat) -> AVAudioPCMBuffer?) {
        self.makeBuffer = makeBuffer
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine, queue: .main
        ) { [weak self] _ in
            // Headphones in or out, or the session category changing because
            // the other tool just started. The engine's connections are gone
            // by the time this arrives; rebuild them, and pick the loop back
            // up if it was running. Without this, plugging in headphones
            // silently ends the click.
            guard let self else { return }
            self.needsReconnect = true
            guard self.isPlaying else { return }
            self.start()
        }
    }

    deinit {
        // A block observer outlives its object unless its token is handed
        // back — the two tools are shared and never die, but a LoopPlayer
        // built for anything else would leave one behind every time.
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }

    /// Starts, or restarts from the head of the loop. Returns false if the
    /// engine would not run or the buffer could not be built — in which case
    /// there is nothing useful to say and nothing to recover.
    @discardableResult
    func start() -> Bool {
        do {
            try configure()
        } catch {
            isPlaying = false
            return false
        }
        guard let format, let buffer = makeBuffer(format) else {
            isPlaying = false
            return false
        }
        player.stop()
        player.volume = 1
        player.scheduleBuffer(buffer, at: nil, options: [.loops])
        player.play()
        isPlaying = true
        return true
    }

    func stop() {
        guard isPlaying else { return }
        isPlaying = false

        guard fadeOutSeconds > 0 else {
            player.stop()
            engine.pause()
            return
        }

        fade(from: Self.fadeSteps, interval: fadeOutSeconds / Double(Self.fadeSteps))
    }

    private static let fadeSteps = 6

    /// One step of the ramp, then the next. Recursive rather than a loop
    /// because it has to yield the main thread between steps — and because
    /// every step is a chance to notice that the tool was started again, in
    /// which case `start()` has already put the level back and the only
    /// correct thing left to do is leave.
    private func fade(from step: Int, interval: Double) {
        guard !isPlaying else { return }
        guard step > 0 else {
            player.stop()
            player.volume = 1
            engine.pause()
            return
        }
        player.volume = Float(step - 1) / Float(Self.fadeSteps)
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.fade(from: step - 1, interval: interval)
        }
    }

    /// The buffer IS the tempo, and the pitch — so a change to either is a
    /// new loop, taking effect at the top of the next one.
    func reload() {
        guard isPlaying else { return }
        start()
    }

    /// Where the playhead is, in seconds since the loop began — straight from
    /// the audio clock, so what you see cannot disagree with what you hear.
    /// `nil` when nothing is running.
    var elapsedSeconds: Double? {
        guard isPlaying,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0
        else { return nil }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    private func configure() throws {
        let output = engine.outputNode.outputFormat(forBus: 0)
        // The simulator has been seen reporting a zero sample rate before the
        // engine has ever run; 44.1k is a safe floor and the loop is
        // synthesised at whatever rate we end up with.
        let rate = output.sampleRate > 0 ? output.sampleRate : 44_100

        if needsReconnect || format?.sampleRate != rate {
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)
            self.format = format
            if !attached {
                engine.attach(player)
                attached = true
            }
            engine.connect(player, to: engine.mainMixerNode, format: format)
            engine.prepare()
            needsReconnect = false
        }
        if !engine.isRunning {
            try engine.start()
        }
    }
}
