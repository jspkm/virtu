import SwiftUI

/// The tuning fork: the orchestra's A, and nothing else.
///
/// Deliberately not a second tuner. A fork is one pitch you strike without
/// deciding anything — that is the whole of its value, and giving it a note
/// picker would make it a worse copy of the card above it. Choosing a note
/// belongs to the tuner's Play mode; this is for the moment before a
/// rehearsal when someone says "give us an A".
///
/// It follows the calibration, so a baroque player's fork is a baroque fork.
/// It shares the tuner's one oscillator and audio-session claim, so sounding
/// it stops whatever else was sounding — and cannot run while the tuner
/// listens, because a microphone a hand from the speaker would hear it and
/// report perfect tuning.
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
                Text("A")
                    .font(VFont.tunerNote)
                    .foregroundStyle(theme.ink)
                Text("\(Tuner.forkOctave)")
                    .font(VFont.mono(13))
                    .foregroundStyle(theme.muted)
                Spacer()
                Text(String(format: "%.1f Hz", tuner.forkHz))
                    .font(VFont.mono(13))
                    .foregroundStyle(theme.muted)
                    .monospacedDigit()
            }

            Text("The A everyone tunes to, at the pitch you set above.")
                .font(VFont.metadata)
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Button {
                tuner.toggleSounding(.fork)
                Haptics.medium()
            } label: {
                Text(tuner.sounds(.fork) ? "Stop" : "Sound the A")
                    .font(VFont.control)
                    .foregroundStyle(theme.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(tuner.sounds(.fork) ? theme.accent : theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.button))
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
        }
        .padding(24)
        .plateCard()
    }
}
