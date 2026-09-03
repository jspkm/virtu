import SwiftUI
import UIKit

/// The tuner: what it is hearing, and nothing else.
///
/// Everything that needs deciding — the note to sound, the A it is all
/// measured from, how black notes are spelled — lives on the Tuning fork card
/// beside this one. This card is a readout. Both the musician's hands are on
/// the instrument and the only question is what the needle says, so the one
/// setting that belongs to listening (which note to name it as) is offered
/// before you start and gone once you have.
struct TunerCard: View {
    @Environment(\.theme) private var theme
    @State private var tuner = Tuner.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tuning")
                .font(VFont.panelLabel)
                .foregroundStyle(theme.muted)
                .textCase(.uppercase)
                .tracking(1.5)
                .padding(.bottom, 16)

            modePicker.padding(.bottom, 18)

            switch tuner.mode {
            case .play:
                // Setting a note needs the note, the octave, the A it is
                // measured from and how it is spelled. All of it lives here,
                // and none of it is on screen while the tuner is listening.
                toneReading
                notes.padding(.top, 18)
                octaves.padding(.top, 6)
                calibration.padding(.top, 14)
                playTransport.padding(.top, 18)
            case .listen:
                // The settings stay: they are the question. You choose the
                // note you are tuning to, then listen to hear whether you are
                // there. What changes is that the reading and the needle sit
                // above them, answering it.
                heardReading
                deviation.padding(.top, 16)
                notes.padding(.top, 20)
                octaves.padding(.top, 6)
                calibration.padding(.top, 14)
                transport.padding(.top, 18)
            }

            if tuner.micDenied {
                microphoneNote.padding(.top, 16)
            }
        }
        .padding(24)
        .plateCard()
    }

    /// The two things the hardware cannot do at once, named for what they are
    /// for. Sounding while listening would have the tuner hear its own tone
    /// through a microphone a hand from the speaker and report perfect tuning.
    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(Tuner.Mode.allCases, id: \.self) { option in
                let selected = tuner.mode == option
                Button {
                    tuner.mode = option
                    Haptics.selection()
                } label: {
                    Text(option == .play ? "Play a note" : "Listen")
                        .font(VFont.control)
                        .foregroundStyle(selected ? theme.paper : theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selected ? theme.ink : theme.wash)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.smallControl))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }

    // MARK: - Play a note

    private var toneReading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            toneGlyph
            Text("\(tuner.toneOctave)")
                .font(VFont.mono(13))
                .foregroundStyle(theme.muted)
            Spacer()
            spellingToggle
            Text(String(format: "%.1f Hz", tuner.toneHz))
                .font(VFont.mono(13))
                .foregroundStyle(theme.muted)
                .monospacedDigit()
                .padding(.leading, 8)
        }
    }

    private var toneGlyph: some View {
        let letters = tuner.spelling == .sharps ? Pitch.sharpLetters : Pitch.flatLetters
        let full = Pitch.name(pitchClass: tuner.tonePitchClass, spelling: tuner.spelling)
        let accidental = full.count > letters[tuner.tonePitchClass].count
            ? String(full.suffix(1)) : nil
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(letters[tuner.tonePitchClass]).font(VFont.tunerNote)
            if let accidental {
                Text(accidental).font(VFont.serif(24)).baselineOffset(9).padding(.leading, 1)
            }
        }
        .foregroundStyle(theme.ink)
    }

    private var notes: some View {
        VStack(spacing: 4) {
            ForEach([Array(0..<6), Array(6..<12)], id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { pitchClass in
                        pill(title: Pitch.name(pitchClass: pitchClass, spelling: tuner.spelling),
                             selected: tuner.tonePitchClass == pitchClass) {
                            tuner.tonePitchClass = pitchClass
                        }
                    }
                }
            }
        }
    }

    private var octaves: some View {
        HStack(spacing: 4) {
            ForEach(Tuner.toneOctaves, id: \.self) { octave in
                pill(title: "\(octave)", selected: tuner.toneOctave == octave) {
                    tuner.toneOctave = octave
                }
                .accessibilityLabel("Octave \(octave)")
            }
        }
    }

    private var calibration: some View {
        HStack(spacing: 8) {
            stepper("minus", enabled: tuner.referenceHz > Tuner.minReferenceHz) {
                tuner.referenceHz -= Tuner.referenceStep
            }
            Menu {
                ForEach(Tuner.references, id: \.self) { hz in
                    Button("A \(Self.hzLabel(hz)) Hz") { tuner.referenceHz = hz }
                }
            } label: {
                Text("A \(Self.hzLabel(tuner.referenceHz)) Hz")
                    .font(VFont.mono(13, weight: .medium))
                    .foregroundStyle(theme.ink)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(theme.wash)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.smallControl))
            }
            .accessibilityLabel("Reference pitch, A \(Self.hzLabel(tuner.referenceHz)) hertz")
            stepper("plus", enabled: tuner.referenceHz < Tuner.maxReferenceHz) {
                tuner.referenceHz += Tuner.referenceStep
            }
            if tuner.isOffStandardPitch {
                Button {
                    tuner.resetReference(); Haptics.selection()
                } label: {
                    Text("440").font(VFont.mono(12)).foregroundStyle(theme.accent)
                        .padding(.horizontal, 8).frame(height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset to concert pitch, A 440")
            }
        }
    }

    private var spellingToggle: some View {
        HStack(spacing: 4) {
            ForEach(Pitch.Spelling.allCases, id: \.self) { option in
                let selected = tuner.spelling == option
                Button {
                    tuner.spelling = option; Haptics.selection()
                } label: {
                    Text(option == .sharps ? "\u{266F}" : "\u{266D}")
                        .font(VFont.serif(15))
                        .foregroundStyle(selected ? theme.paper : theme.muted)
                        .frame(width: 30, height: 24)
                        .background(selected ? theme.ink : theme.wash)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.smallControl))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option == .sharps
                    ? "Name black notes as sharps" : "Name black notes as flats")
            }
        }
    }

    private var playTransport: some View {
        Button {
            tuner.toggleSounding(); Haptics.medium()
        } label: {
            Text(tuner.isSounding ? "Stop" : "Play")
                .font(VFont.control)
                .foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(tuner.isSounding ? theme.accent : theme.ink)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.button))
        }
        .buttonStyle(.plain)
    }

    private func pill(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action(); Haptics.selection()
        } label: {
            Text(title)
                .font(VFont.mono(12))
                .foregroundStyle(selected ? theme.paper : theme.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(selected ? theme.ink : theme.wash)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.smallControl))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func stepper(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action(); Haptics.selection()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(enabled ? theme.ink : theme.faint)
                .frame(width: 30, height: 30)
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.smallControl)
                    .stroke(theme.line2, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "minus" ? "Lower the reference" : "Raise the reference")
    }

    // MARK: - What it hears

    /// The heard note, its distance from the selection, and — when the two
    /// agree — the green.
    private var heardReading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let pitch = tuner.reading {
                heardGlyph(pitch)
                Text("\(pitch.octave)")
                    .font(VFont.mono(13))
                    .foregroundStyle(theme.muted)
                Text(Self.hertz(pitch.frequency))
                    .font(VFont.mono(13))
                    .foregroundStyle(theme.muted)
                    .monospacedDigit()
            } else {
                Text("\u{2014}")
                    .font(VFont.tunerNote)
                    .foregroundStyle(theme.faint)
                Text(tuner.isListening ? "listening" : "not listening")
                    .font(VFont.mono(13))
                    .foregroundStyle(theme.muted)
            }

            Spacer()

            if let pitch = tuner.reading {
                Text(Self.centsLabel(pitch.cents))
                    .font(VFont.mono(22, weight: .medium))
                    .foregroundStyle(tuner.matchesSelection ? theme.inTune : theme.muted)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenReading)
    }

    private func heardGlyph(_ pitch: Pitch) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(pitch.letter)
                .font(VFont.tunerNote)
            if let accidental = pitch.accidental {
                // No bundled face carries U+266F, so this one glyph comes from
                // the system's own cascade. Asking for it as its own Text is
                // what lets it be sized and lifted to sit against the letter.
                Text(accidental)
                    .font(VFont.serif(24))
                    .baselineOffset(9)
                    .padding(.leading, 1)
            }
        }
        .foregroundStyle(tuner.matchesSelection ? theme.inTune : theme.ink)
        .animation(.easeOut(duration: 0.18), value: tuner.matchesSelection)
    }

    // MARK: - The strip
    //
    // Fifty cents either side — a quarter tone, past which the note name has
    // already changed and the reading means nothing. The needle is
    // deliberately NOT smoothed here: the steadying happens in `Tuner.hear`,
    // on the data, because a view animation long enough to hide jitter is
    // also long enough to lag the string.

    private static let fullScaleCents = 50.0

    private var deviation: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.line)
                    .frame(height: 6)

                // The target: the note you selected, marked so it can be
                // aimed at rather than read. It is the thing that goes green.
                Capsule()
                    .fill(tuner.matchesSelection ? theme.inTune : theme.line2)
                    .frame(width: tuner.matchesSelection ? 4 : 2, height: 18)
                    .offset(x: width / 2 - (tuner.matchesSelection ? 2 : 1))
                    .animation(.easeOut(duration: 0.18), value: tuner.matchesSelection)

                if let pitch = tuner.reading {
                    Capsule()
                        .fill(tuner.matchesSelection ? theme.inTune : theme.ink)
                        .frame(width: 4, height: 22)
                        .offset(x: needleOffset(cents: pitch.cents, width: width))
                        .animation(.easeOut(duration: 0.18), value: tuner.matchesSelection)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 22)
        .animation(.linear(duration: 0.1), value: tuner.heardHz)
        .accessibilityHidden(true)
    }

    private func needleOffset(cents: Double, width: CGFloat) -> CGFloat {
        let clamped = max(-Self.fullScaleCents, min(Self.fullScaleCents, cents))
        let half = width / 2 - 2
        return width / 2 - 2 + CGFloat(clamped / Self.fullScaleCents) * half
    }

    // MARK: - Transport

    private var transport: some View {
        Button {
            tuner.toggleListening()
            Haptics.light()
        } label: {
            Text(tuner.isListening ? "Listening" : "Listen")
                .font(VFont.control)
                .foregroundStyle(tuner.isListening ? theme.paper : theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(tuner.isListening ? theme.accent : .clear)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.button))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.button)
                        .stroke(tuner.isListening ? .clear : theme.line2, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityHint(tuner.isListening
            ? "Stops listening" : "Listens and shows how far off you are")
    }

    /// Shown only after the microphone has actually been refused. A button
    /// that silently does nothing is worse than no button, and the fork still
    /// works — so say both.
    private var microphoneNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Virtu cannot hear the microphone. Turn it on in Settings to listen — playing a note works without it.")
                .font(VFont.metadata)
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .font(VFont.control)
            .foregroundStyle(theme.accent)
            .buttonStyle(.plain)
        }
    }

    // MARK: - Copy

    private static func hzLabel(_ hz: Double) -> String {
        hz == hz.rounded() ? String(Int(hz)) : String(format: "%.1f", hz)
    }

    private static func hertz(_ value: Double) -> String {
        String(format: "%.1f Hz", value)
    }

    /// A true minus sign, not a hyphen — the figure beside it is set in mono
    /// and a hyphen sits at the wrong height against it.
    private static func centsLabel(_ cents: Double) -> String {
        let rounded = Int(cents.rounded())
        if rounded == 0 { return "0¢" }
        return (rounded > 0 ? "+" : "\u{2212}") + "\(abs(rounded))¢"
    }

    private var spokenReading: String {
        guard let pitch = tuner.reading else {
            return tuner.isListening ? "Listening" : "Not listening"
        }
        return tuner.matchesSelection ? "\(pitch.spoken), matches your selection" : pitch.spoken
    }
}
