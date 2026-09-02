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

            reading
            deviation.padding(.vertical, 18)
            references
            transport.padding(.top, 18)

            if tuner.micDenied {
                microphoneNote.padding(.top, 16)
            }
        }
        .padding(24)
        .plateCard()
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
                Text("\(Int(tuner.referenceHz)) Hz")
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

    // MARK: - The references

    private var references: some View {
        HStack(spacing: 6) {
            ForEach(Tuner.references, id: \.self) { hz in
                let selected = tuner.referenceHz == hz
                Button {
                    tuner.referenceHz = hz
                    Haptics.selection()
                } label: {
                    Text("A \(Int(hz))")
                        .font(VFont.mono(12))
                        .foregroundStyle(selected ? theme.paper : theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(selected ? theme.ink : theme.wash)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.smallControl))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tune to A \(Int(hz)) hertz")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 10) {
            Button {
                tuner.toggleSounding()
                Haptics.medium()
            } label: {
                Text(tuner.isSounding ? "Stop" : "Sound A")
                    .font(VFont.control)
                    .foregroundStyle(theme.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(tuner.isSounding ? theme.accent : theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.button))
            }
            .buttonStyle(.plain)

            Button {
                tuner.toggleListening()
                Haptics.light()
            } label: {
                Text(tuner.isListening ? "Listening" : "Listen")
                    .font(VFont.control)
                    .foregroundStyle(tuner.isListening ? theme.paper : theme.ink)
                    .fixedSize()
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
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
        return "Tuning to A \(Int(tuner.referenceHz)) hertz"
    }
}
