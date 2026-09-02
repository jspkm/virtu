import SwiftUI

/// The metronome, as drawn in the design handoff's Tools screen: the figure
/// in mono at 60pt, the Italian beside it in serif italic, a row of lamps, the
/// tempo slider, then Start and Tap tempo.
struct MetronomeCard: View {
    @Environment(\.theme) private var theme
    @State private var metronome = Metronome.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Metronome")
                .font(VFont.panelLabel)
                .foregroundStyle(theme.muted)
                .textCase(.uppercase)
                .tracking(1.5)
                .padding(.bottom, 16)

            reading
            lamps.padding(.vertical, 18)
            slider
            // Both rows are digits and the first four overlap, so each says
            // which question it answers. Without them "1 2 3 4" under
            // "1 2 3 4 5 6 7" is a guess.
            rowLabel("Beats to the bar").padding(.top, 16)
            meterPicker.padding(.top, 6)
            rowLabel("Rhythm").padding(.top, 12)
            rhythm.padding(.top, 6)
            transport.padding(.top, 18)
        }
        .padding(24)
        .plateCard()
    }

    // MARK: - The figure

    private var reading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(metronome.bpm)")
                .font(VFont.bpmTools)
                .foregroundStyle(theme.ink)
                // The figure must not jog sideways as it counts through 99.
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(metronome.tempoWord)
                .font(VFont.serifItalic(18))
                .foregroundStyle(theme.muted)

            Spacer()

            stepper("minus", enabled: metronome.bpm > Metronome.minBPM) {
                metronome.bpm -= 1
            }
            stepper("plus", enabled: metronome.bpm < Metronome.maxBPM) {
                metronome.bpm += 1
            }
        }
    }

    /// Single-BPM precision, which the slider cannot give: 485 BPM across a
    /// card's width is roughly two beats a point, so the slow end — where one
    /// beat matters most — is unreachable by dragging.
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
        .accessibilityLabel(symbol == "minus" ? "Slower" : "Faster")
    }

    /// Beats to the bar. A plain segmented row of figures — the numerator of
    /// the time signature, which is the only part a click can express.
    private var meterPicker: some View {
        HStack(spacing: 4) {
            ForEach(1...7, id: \.self) { count in
                let selected = metronome.beatsPerBar == count
                Button {
                    metronome.beatsPerBar = count
                    Haptics.selection()
                } label: {
                    Text("\(count)")
                        .font(VFont.mono(12))
                        .foregroundStyle(selected ? theme.paper : theme.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(selected ? theme.ink : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.smallControl))
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.Radius.smallControl)
                                .stroke(selected ? .clear : theme.line2, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(count) beats to the bar")
            }
        }
    }

    // MARK: - Lamps
    //
    // 60ms linear, per the design language's motion table — a lamp is an
    // indicator, not an animation, and anything slower lags the click it is
    // reporting. The beat comes from the audio clock (see Metronome), so this
    // only has to redraw often enough to catch it.

    private var lamps: some View {
        TimelineView(.animation) { _ in
            let beat = metronome.currentBeat
            HStack(spacing: 8) {
                ForEach(0..<metronome.beatsPerBar, id: \.self) { index in
                    Capsule()
                        .fill(fill(for: index, current: beat))
                        .frame(height: 6)
                        .animation(.linear(duration: 0.06), value: beat)
                }
            }
        }
        .frame(height: 6)
    }

    private func fill(for index: Int, current: Int?) -> Color {
        guard current == index else { return theme.line }
        // Beat one is the accent in the ear; it is the accent on screen too.
        return index == 0 ? theme.accent : theme.ink
    }

    // MARK: - Tempo

    /// Logarithmic, per PRD §5.1. Tempo perception is logarithmic, and a
    /// linear track across 485 BPM spends nine tenths of itself above 60 —
    /// the slow end, where a single beat matters most, would be a few points
    /// wide. Mapped this way the midpoint of the track is 87 BPM and a
    /// thousandth of the track is a tenth of a beat at 15.
    private var slider: some View {
        Slider(
            value: Binding(
                get: { log(Double(metronome.bpm)) },
                set: { metronome.bpm = Int(exp($0).rounded()) }
            ),
            in: log(Double(Metronome.minBPM))...log(Double(Metronome.maxBPM))
        )
        .tint(theme.accent)
        .accessibilityLabel("Tempo")
        .accessibilityValue("\(metronome.bpm) beats per minute, \(metronome.tempoWord)")
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(VFont.metadata)
            .foregroundStyle(theme.faint)
    }

    /// Six across. The beat's own division, as a third quieter click voice.
    private var rhythm: some View {
        HStack(spacing: 4) {
            ForEach(Subdivision.allCases) { option in
                let selected = metronome.subdivision == option
                Button {
                    metronome.subdivision = option
                    Haptics.selection()
                } label: {
                    Text(option.label)
                        .font(VFont.mono(11))
                        .foregroundStyle(selected ? theme.paper : theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(selected ? theme.ink : theme.wash)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.smallControl))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.spoken)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 10) {
            Button {
                metronome.toggle()
                Haptics.medium()
            } label: {
                Text(metronome.isRunning ? "Stop" : "Start")
                    .font(VFont.control)
                    .foregroundStyle(theme.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(metronome.isRunning ? theme.accent : theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.button))
            }
            .buttonStyle(.plain)

            Button {
                metronome.tap()
                Haptics.light()
            } label: {
                Text("Tap tempo")
                    .font(VFont.control)
                    .foregroundStyle(theme.ink)
                    .fixedSize()
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.button)
                            .stroke(theme.line2, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}
