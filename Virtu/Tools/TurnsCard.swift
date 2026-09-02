import SwiftUI

/// Page turns, as the design handoff draws them on the Tools screen: a row
/// per preference, each a pill track with a knob, a label, and a hint that
/// says what the setting actually does at the stand.
///
/// The third card the handoff always had and the app never built, which is
/// why `Preferences.seamHoldSeconds`, `halfPageTurns` and `bluetoothPedal`
/// had nowhere to be set.
///
/// The handoff's first toggle is "Carry the last system over" — that is the
/// seam, and the seam is undecided (PLAN Part II, Decision 1). A switch for
/// behaviour that does not exist would be a lie in the UI, so the row lands
/// with the seam, if the seam ever lands.
struct TurnsCard: View {
    @Environment(\.theme) private var theme
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Page turns")
                .font(VFont.panelLabel)
                .foregroundStyle(theme.muted)
                .textCase(.uppercase)
                .tracking(1.5)
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 12) {
                row(
                    label: "Half-page turns",
                    hint: "Advance one page at a time inside a spread",
                    isOn: state.preferences.halfPageTurns
                ) { state.preferences.halfPageTurns.toggle() }

                row(
                    label: "Bluetooth pedal",
                    hint: "AirTurn and PageFlip pedals arrive as key presses",
                    isOn: state.preferences.bluetoothPedal
                ) { state.preferences.bluetoothPedal.toggle() }
            }
        }
        .padding(24)
        .plateCard()
    }

    private func row(
        label: String, hint: String, isOn: Bool, toggle: @escaping () -> Void
    ) -> some View {
        Button {
            toggle()
            Haptics.selection()
        } label: {
            HStack(alignment: .top, spacing: 14) {
                // 150ms ease-out, the design language's Drift curve: a switch
                // is an ambient state change, not a page turn.
                Capsule()
                    .fill(isOn ? theme.accent : theme.line2)
                    .frame(width: 38, height: 22)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle()
                            .fill(theme.plate)
                            .frame(width: 16, height: 16)
                            .padding(.horizontal, 3)
                    }
                    .animation(.easeOut(duration: 0.15), value: isOn)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(VFont.body)
                        .foregroundStyle(theme.ink)
                    Text(hint)
                        .font(VFont.metadata)
                        .foregroundStyle(theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(hint)
    }
}
