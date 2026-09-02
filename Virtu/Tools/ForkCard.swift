import SwiftUI

/// The tuning fork — a sounded reference, on its own card.
///
/// Separate from the tuner because giving a pitch and checking a pitch are
/// two different jobs, and the musician is doing exactly one of them at a
/// time. The model enforces that: sounding stops listening and listening
/// stops sounding, because an iPad's microphone and its speaker are a hand
/// apart and a tuner that hears its own fork reports, with total confidence,
/// that you are perfectly in tune.
struct ForkCard: View {
    @Environment(\.theme) private var theme
    @State private var tuner = Tuner.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tuning fork")
                .font(VFont.panelLabel)
                .foregroundStyle(theme.muted)
                .textCase(.uppercase)
                .tracking(1.5)
                .padding(.bottom, 16)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Pitch.name(pitchClass: tuner.forkPitchClass, spelling: tuner.spelling))
                    .font(VFont.tunerNote)
                    .foregroundStyle(theme.ink)
                Text("\(tuner.forkOctave)")
                    .font(VFont.mono(13))
                    .foregroundStyle(theme.muted)
                Spacer()
                Text(String(format: "%.1f Hz", tuner.forkHz))
                    .font(VFont.mono(13))
                    .foregroundStyle(theme.muted)
                    .monospacedDigit()
            }
            .padding(.bottom, 18)

            notes
            octaves.padding(.top, 8)

            Button {
                tuner.toggleSounding()
                Haptics.medium()
            } label: {
                Text(tuner.isSounding ? "Stop" : "Sound")
                    .font(VFont.control)
                    .foregroundStyle(theme.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(tuner.isSounding ? theme.accent : theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.button))
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
        }
        .padding(24)
        .plateCard()
    }

    /// Twelve across two rows of six — one row of twelve is unreadable at
    /// card width, and a scroller hides half the notes behind a gesture.
    private var notes: some View {
        VStack(spacing: 4) {
            ForEach([Array(0..<6), Array(6..<12)], id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { pitchClass in
                        let selected = tuner.forkPitchClass == pitchClass
                        Button {
                            tuner.forkPitchClass = pitchClass
                            Haptics.selection()
                        } label: {
                            Text(Pitch.name(pitchClass: pitchClass, spelling: tuner.spelling))
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
                }
            }
        }
    }

    private var octaves: some View {
        HStack(spacing: 4) {
            ForEach(Tuner.forkOctaves, id: \.self) { octave in
                let selected = tuner.forkOctave == octave
                Button {
                    tuner.forkOctave = octave
                    Haptics.selection()
                } label: {
                    Text("\(octave)")
                        .font(VFont.mono(12))
                        .foregroundStyle(selected ? theme.paper : theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selected ? theme.ink : theme.wash)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.smallControl))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Octave \(octave)")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}
