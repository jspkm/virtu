import Accelerate
import Foundation

// MARK: - What a heard frequency means

/// A frequency, read as a note.
///
/// Every part of this depends on which A you are tuning to, which is the
/// whole point of the four buttons on the card: the same string is a
/// perfectly in-tune D against A 415 and eleven cents sharp against A 442.
/// So the reference is carried here rather than baked in.
struct Pitch: Equatable {

    let frequency: Double
    let referenceA: Double

    /// MIDI number of the nearest equal-tempered note. A 440 is 69.
    let midi: Int

    /// Distance from that note. Negative is flat, positive is sharp.
    let cents: Double

    init(frequency: Double, referenceA: Double) {
        self.frequency = frequency
        self.referenceA = referenceA
        // Where this frequency falls on a continuous MIDI scale, then the
        // note it is nearest and how far off that leaves it.
        let exact = 69 + 12 * log2(frequency / referenceA)
        let nearest = exact.rounded()
        self.midi = Int(nearest)
        self.cents = (exact - nearest) * 100
    }

    /// Sharps, not flats. A tuner names a pitch, not a key — nothing here
    /// knows what you are playing, so there is no basis for choosing E flat
    /// over D sharp, and picking one and staying with it is the only honest
    /// option.
    private static let letters = ["C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B"]
    private static let accidentals: [String?] = [
        nil, "♯", nil, "♯", nil, nil, "♯", nil, "♯", nil, "♯", nil
    ]
    private static let spokenAccidentals: [String?] = [
        nil, " sharp", nil, " sharp", nil, nil, " sharp", nil, " sharp", nil, " sharp", nil
    ]

    private var pitchClass: Int { ((midi % 12) + 12) % 12 }

    var letter: String { Self.letters[pitchClass] }
    var accidental: String? { Self.accidentals[pitchClass] }

    /// Scientific pitch notation: middle C is C4, so the cello's A string is
    /// A3 and the violin's is A4. Worth showing — an octave error is the one
    /// mistake a tuner can make that looks exactly like being in tune.
    var octave: Int { Int(floor(Double(midi) / 12)) - 1 }

    var isInTune: Bool { abs(cents) <= Tuner.inTuneCents }

    /// "A sharp 3, seven cents sharp." For VoiceOver, and for anyone whose
    /// eyes are on the fingerboard.
    var spoken: String {
        let name = letter + (Self.spokenAccidentals[pitchClass] ?? "") + " \(octave)"
        let rounded = Int(cents.rounded())
        // Asks `isInTune` rather than re-deriving it: rounding first put a
        // 5.4-cent reading in tune for VoiceOver and out of tune on screen,
        // so a sighted and a blind musician got opposite answers from the
        // same needle.
        if isInTune { return "\(name), in tune" }
        return "\(name), \(abs(rounded)) cents \(rounded > 0 ? "sharp" : "flat")"
    }
}

// MARK: - Finding the pitch

/// YIN, to the level of detail a tuner needs.
///
/// Deliberately not an FFT. A 4096-sample window at 48kHz has bins about
/// 12Hz apart, and the job here is to resolve a *cent* — which on a cello's
/// bottom C is a fifth of a hertz. Interpolating an FFT peak that coarse is
/// guesswork. Autocorrelation resolves the *period* instead, YIN's cumulative
/// mean normalisation is what stops it answering an octave too low (the
/// classic autocorrelation failure, and exactly the one that matters on a
/// bowed low string), and a parabola through the minimum recovers sub-sample
/// precision from there.
///
/// Accelerate does the one expensive step, per PRD §10's "vImage / Accelerate,
/// no third-party CV dependency" — the same rule applied to audio.
struct PitchDetector {

    /// The analysis window at 44.1/48kHz — long enough to hold better than two
    /// periods of the lowest note we accept, which is what YIN needs to see.
    static let windowFrames = 4_096

    let sampleRate: Double

    /// Below the double bass's open E. Nothing musical lives under here, and
    /// everything under here is room rumble and handling noise.
    var lowestHz = 40.0

    /// Two octaves above the violin's top open string. Higher than any note
    /// anyone tunes, and low enough to reject a chair scrape.
    var highestHz = 1_500.0

    /// YIN's absolute threshold. Above it the window is not periodic enough
    /// to be one note, so the honest answer is silence rather than a guess.
    var aperiodicity = 0.15

    /// A last-resort ceiling for the case where nothing crossed the
    /// threshold at all. Anything less convincing than this is not a note.
    var weakestAccepted = 0.35

    /// Below this the room is quiet and the needle should not move.
    var silenceRMS: Float = 0.005

    /// How many frames an analysis needs at this sample rate.
    ///
    /// A fixed 4096 is enough to 48kHz and silently fatal above it: the lag
    /// search needs `rate / lowestHz` samples and the integration window needs
    /// more than that again, so at 88.2 or 96kHz — an iPad with a USB-C audio
    /// interface — a 4096-frame window cannot satisfy its own guard and every
    /// single analysis returns nil, with the card showing "listening" for ever
    /// and no way to tell why. The window grows with the rate instead.
    var analysisFrames: Int {
        max(Self.windowFrames, Int((sampleRate / lowestHz).rounded()) * 3)
    }

    /// The frequency of the note in this window, or nil if there isn't one.
    func frequency(in samples: [Float]) -> Double? {
        let count = samples.count

        // The lag range worth searching, straight out of the note range.
        let tauMax = min(count / 2, Int(sampleRate / lowestHz))
        let tauMin = max(2, Int(sampleRate / highestHz))
        guard tauMax > tauMin + 2 else { return nil }

        // What is left over is the integration window: every lag is compared
        // over the same number of samples, which is what makes d(tau)
        // comparable across tau at all.
        let window = count - tauMax
        // Not an assertion: a caller may hand over a buffer sized for a
        // different rate, and the honest answer is "I cannot hear this"
        // rather than a crash or a wrong note.
        guard window > tauMax else { return nil }

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(count))
        guard rms > silenceRMS else { return nil }

        // In double precision from here. d(tau) is a difference of two large
        // and nearly equal sums — at the minimum they cancel to a thousandth
        // of their own size — and single precision loses the answer in the
        // subtraction.
        var signal = [Double](repeating: 0, count: count)
        vDSP_vspdp(samples, 1, &signal, 1, vDSP_Length(count))

        // A microphone's DC offset is a constant added to every sample, which
        // adds a constant to every correlation and flattens the minimum we
        // are trying to find.
        var mean = 0.0
        vDSP_meanvD(signal, 1, &mean, vDSP_Length(count))
        var offset = -mean
        vDSP_vsaddD(signal, 1, &offset, &signal, 1, vDSP_Length(count))

        // The one expensive step: every lag's correlation at once.
        //   correlation[tau] = sum over j < window of x[j] * x[j + tau]
        var correlation = [Double](repeating: 0, count: tauMax + 1)
        signal.withUnsafeBufferPointer { x in
            guard let base = x.baseAddress else { return }
            vDSP_convD(
                base, 1, base, 1, &correlation, 1,
                vDSP_Length(tauMax + 1), vDSP_Length(window)
            )
        }

        // The energy under each shifted window, by a running sum — the same
        // information, and O(n) instead of another correlation.
        var power = [Double](repeating: 0, count: tauMax + 1)
        var running = 0.0
        for j in 0..<window { running += signal[j] * signal[j] }
        power[0] = running
        for tau in 1...tauMax {
            running += signal[tau + window - 1] * signal[tau + window - 1]
            running -= signal[tau - 1] * signal[tau - 1]
            power[tau] = running
        }

        // d(tau), expanded so it can be assembled from what we already have:
        //   sum (x[j] - x[j+tau])^2  =  power[0] + power[tau] - 2*correlation[tau]
        var difference = [Double](repeating: 0, count: tauMax + 1)
        for tau in 0...tauMax {
            difference[tau] = power[0] + power[tau] - 2 * correlation[tau]
        }

        // The cumulative mean normalisation — the step that makes this YIN
        // rather than plain autocorrelation. Dividing each lag by the average
        // of every lag below it means a period's *first* dip wins over the
        // equally deep dip at twice the period, which is what keeps a low
        // bowed string from reading an octave down.
        var normalized = [Double](repeating: 1, count: tauMax + 1)
        var cumulative = 0.0
        for tau in 1...tauMax {
            cumulative += difference[tau]
            normalized[tau] = cumulative > 0 ? difference[tau] * Double(tau) / cumulative : 1
        }

        // The first lag convincing enough to be the period — first, not
        // smallest, for the same octave reason.
        var best = -1
        var tau = tauMin
        while tau <= tauMax {
            if normalized[tau] < aperiodicity {
                while tau + 1 <= tauMax && normalized[tau + 1] < normalized[tau] { tau += 1 }
                best = tau
                break
            }
            tau += 1
        }
        if best < 0 {
            var weakest = Double.greatestFiniteMagnitude
            for tau in tauMin...tauMax where normalized[tau] < weakest {
                weakest = normalized[tau]
                best = tau
            }
            guard weakest < weakestAccepted else { return nil }
        }
        guard best > 0 else { return nil }

        // A parabola through the minimum and its two neighbours. Without
        // this the period is an integer number of samples, which at 48kHz
        // quantises a violin's open E to about 8 cents — the whole error a
        // tuner exists to show.
        var period = Double(best)
        if best < tauMax {   // best >= tauMin >= 2, so best - 1 is always in range
            let before = normalized[best - 1]
            let at = normalized[best]
            let after = normalized[best + 1]
            let curvature = 2 * (before - 2 * at + after)
            if abs(curvature) > .ulpOfOne {
                period += (before - after) / curvature
            }
        }
        guard period > 0 else { return nil }

        let hz = sampleRate / period
        guard hz >= lowestHz, hz <= highestHz else { return nil }
        return hz
    }
}
