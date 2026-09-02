import SwiftUI
import UIKit

/// The tuner, as drawn in the design handoff's Tools screen: the letter in
/// serif at 40pt, the hertz beside it in mono, and the four references in a
/// row underneath. What the handoff could not draw is the half that listens,
/// which is added here as the deviation strip and the second transport
/// button.
///
/// The layout is the same shape as `MetronomeCard` on purpose — label,
/// reading, indicator, choices, transport — because the two sit side by side
/// and a bench of two instruments should look like a bench.
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
                toneReading
                notes.padding(.top, 18)
                octaves.padding(.top, 6)
                calibration.padding(.top, 14)
                playTransport.padding(.top, 18)
            case .listen:
                reading
                deviation.padding(.vertical, 18)
                calibration
                targetHeader.padding(.top, 16)
                target.padding(.top, 6)
                listenTransport.padding(.top, 18)
            }

            if tuner.micDenied {
                microphoneNote.padding(.top, 16)
            }
        }
        .padding(24)
        .plateCard()
    }

    /// The two things the hardware cannot do at once, named as the two things
    /// they are for: give me a pitch, or tell me mine. Sounding while
    /// listening would have the tuner hear its own tone through a microphone
    /// a hand away from the speaker and report perfect tuning.
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

    // MARK: - Play mode

    private var toneReading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            noteGlyphFor(pitchClass: tuner.tonePitchClass)
            Text("\(tuner.toneOctave)")
                .font(VFont.mono(13))
                .foregroundStyle(theme.muted)
            Spacer()
            Text(String(format: "%.1f Hz", tuner.toneHz))
                .font(VFont.mono(13))
                .foregroundStyle(theme.muted)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(Pitch.name(pitchClass: tuner.tonePitchClass, spelling: tuner.spelling)) "
            + "\(tuner.toneOctave), \(Int(tuner.toneHz)) hertz")
    }

    private func noteGlyphFor(pitchClass: Int) -> some View {
        let letters = tuner.spelling == .sharps ? Pitch.sharpLetters : Pitch.flatLetters
        let full = Pitch.name(pitchClass: pitchClass, spelling: tuner.spelling)
        let accidental = full.count > letters[pitchClass].count ? String(full.suffix(1)) : nil
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(letters[pitchClass])
                .font(VFont.tunerNote)
            if let accidental {
                Text(accidental)
                    .font(VFont.serif(24))
                    .baselineOffset(9)
                    .padding(.leading, 1)
            }
        }
        .foregroundStyle(theme.ink)
    }

    /// Twelve across two rows of six — one row of twelve is unreadable at
    /// card width, and a scroller hides half the notes behind a gesture.
    private var notes: some View {
        VStack(spacing: 4) {
            ForEach([Array(0..<6), Array(6..<12)], id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { pitchClass in
                        pill(
                            title: Pitch.name(pitchClass: pitchClass, spelling: tuner.spelling),
                            selected: tuner.tonePitchClass == pitchClass
                        ) { tuner.tonePitchClass = pitchClass }
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

    private func pill(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.selection()
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

    private var playTransport: some View {
        Button {
            tuner.toggleSounding(.tuner)
            Haptics.medium()
        } label: {
            Text(tuner.sounds(.tuner) ? "Stop" : "Play")
                .font(VFont.control)
                .foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(tuner.sounds(.tuner) ? theme.accent : theme.ink)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.button))
        }
        .buttonStyle(.plain)
    }

    // MARK: - The reading
    //
    // Three slots that never change size, so pressing Listen does not shuffle
    // the card underneath the finger that pressed it: the note, the frequency,
    // and — only once there is something to say — the cents.

    private var reading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let pitch = tuner.reading {
                noteGlyph(pitch)
                Text("\(pitch.octave)")
                    .font(VFont.mono(13))
                    .foregroundStyle(theme.muted)
                Text(Self.hertz(pitch.frequency))
                    .font(VFont.mono(13))
                    .foregroundStyle(theme.muted)
                    .monospacedDigit()
            } else if tuner.isListening {
                Text("—")
                    .font(VFont.tunerNote)
                    .foregroundStyle(theme.faint)
                Text("listening")
                    .font(VFont.mono(13))
                    .foregroundStyle(theme.muted)
            } else {
                // The handoff's resting state, exactly: the A you are tuning
                // to, and what it is worth in hertz.
                Text("A")
                    .font(VFont.tunerNote)
                    .foregroundStyle(theme.ink)
                Text("\(Self.hzLabel(tuner.referenceHz)) Hz")
                    .font(VFont.mono(13))
                    .foregroundStyle(theme.muted)
            }

            Spacer()

            if let pitch = tuner.reading {
                Text(Self.centsLabel(pitch.cents))
                    .font(VFont.mono(13, weight: .medium))
                    .foregroundStyle(pitch.isInTune ? theme.accent : theme.muted)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenReading)
    }

    private func noteGlyph(_ pitch: Pitch) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(pitch.letter)
                .font(VFont.tunerNote)
            if let accidental = pitch.accidental {
                // No bundled face carries U+266F, so this one glyph comes
                // from the system's own cascade. Asking for it as its own
                // Text is what lets it be sized and lifted to sit against
                // the letter instead of standing beside it at full height.
                Text(accidental)
                    .font(VFont.serif(24))
                    .baselineOffset(9)
                    .padding(.leading, 1)
            }
        }
        .foregroundStyle(pitch.isInTune ? theme.accent : theme.ink)
        .animation(.easeOut(duration: 0.18), value: pitch.isInTune)
    }

    // MARK: - The strip
    //
    // Fifty cents either side — a quarter tone, past which the note name has
    // already changed and the reading means nothing. The track is the
    // metronome's lamp, at the same 6pt, so the two cards share one bar of
    // furniture. The needle is deliberately NOT smoothed here: the steadying
    // happens in `Tuner.hear`, on the data, because a view animation long
    // enough to hide jitter is also long enough to lag the string.

    private static let fullScaleCents = 50.0

    private var deviation: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.line)
                    .frame(height: 6)

                // The target, marked so it can be aimed at rather than read.
                Capsule()
                    .fill(theme.line2)
                    .frame(width: 2, height: 14)
                    .offset(x: width / 2 - 1)

                if let pitch = tuner.reading {
                    Capsule()
                        .fill(pitch.isInTune ? theme.accent : theme.ink)
                        .frame(width: 4, height: 16)
                        .offset(x: needleOffset(cents: pitch.cents, width: width))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 16)
        .animation(.linear(duration: 0.1), value: tuner.heardHz)
        .accessibilityHidden(true)
    }

    private func needleOffset(cents: Double, width: CGFloat) -> CGFloat {
        let clamped = max(-Self.fullScaleCents, min(Self.fullScaleCents, cents))
        let half = width / 2 - 2
        return width / 2 - 2 + CGFloat(clamped / Self.fullScaleCents) * half
    }

    // MARK: - Calibration

    /// A = 442.0 Hz, with fine steppers, the named presets behind the figure,
    /// and a reset that exists only when it would do something.
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
                    tuner.resetReference()
                    Haptics.selection()
                } label: {
                    Text("440")
                        .font(VFont.mono(12))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset to concert pitch, A 440")
            }
        }
    }

    private func stepper(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.selection()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(enabled ? theme.ink : theme.faint)
                .frame(width: 30, height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.smallControl)
                        .stroke(theme.line2, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "minus" ? "Lower the reference" : "Raise the reference")
    }

    // MARK: - Target note

    private var targetHeader: some View {
        HStack {
            Text("Tuning to")
                .font(VFont.metadata)
                .foregroundStyle(theme.faint)
            Spacer()
            spellingToggle
        }
    }

    /// Auto first, because it is right most of the time; a pinned note is
    /// what you reach for when it is not — a string a semitone flat is named
    /// as the note below and reported nearly in tune.
    private var target: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                chip(title: "Auto", selected: tuner.targetPitchClass == nil) {
                    tuner.targetPitchClass = nil
                }
                ForEach(0..<12, id: \.self) { pitchClass in
                    chip(
                        title: Pitch.name(pitchClass: pitchClass, spelling: tuner.spelling),
                        selected: tuner.targetPitchClass == pitchClass
                    ) { tuner.targetPitchClass = pitchClass }
                }
            }
            .padding(.trailing, 2)
        }
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.selection()
        } label: {
            Text(title)
                .font(VFont.mono(12))
                .foregroundStyle(selected ? theme.paper : theme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(selected ? theme.ink : theme.wash)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.smallControl))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// Sharps or flats, applied everywhere a note is named.
    private var spellingToggle: some View {
        HStack(spacing: 4) {
            ForEach(Pitch.Spelling.allCases, id: \.self) { option in
                let selected = tuner.spelling == option
                Button {
                    tuner.spelling = option
                    Haptics.selection()
                } label: {
                    Text(option == .sharps ? "\u{266F}" : "\u{266D}")
                        .font(VFont.serif(15))
                        .foregroundStyle(selected ? theme.paper : theme.muted)
                        .frame(width: 30, height: 24)
                        .background(selected ? theme.ink : theme.wash)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.smallControl))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option == .sharps ? "Name black notes as sharps" : "Name black notes as flats")
            }
        }
    }

    // MARK: - Transport

    private var listenTransport: some View {
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
        .accessibilityHint(tuner.isListening ? "Stops listening" : "Listens and shows how far off you are")
    }

    /// Shown only after the microphone has actually been refused. A button
    /// that silently does nothing is worse than no button, and the half that
    /// sounds the A still works — so say both.
    private var microphoneNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Virtu cannot hear the microphone. Turn it on in Settings to use the tuner — sounding the A works without it.")
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
        if let pitch = tuner.reading { return pitch.spoken }
        if tuner.isListening { return "Listening" }
        return "Tuning to A \(Self.hzLabel(tuner.referenceHz)) hertz"
    }
}
