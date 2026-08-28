import SwiftUI

struct NavRailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 24)

            // Destinations
            ForEach(AppState.Destination.allCases, id: \.self) { dest in
                NavRailButton(
                    destination: dest,
                    isActive: state.destination == dest
                ) {
                    state.destination = dest
                    state.chromeVisible = true
                }
            }

            Spacer()

            // Stage toggle
            NavRailToggle(
                icon: state.stageMode ? "sun.max" : "moon",
                label: "Stage"
            ) {
                state.stageMode.toggle()
            }
            .padding(.bottom, 10)

            // Whose shelf this is. Tap to (re)name it.
            Button {
                state.destination = .library
                state.shelfRenameRequested = true
            } label: {
                Group {
                    if let initials = state.shelfInitials {
                        Text(initials)
                            .font(VFont.railLabel)
                            .tracking(0.5)
                    } else {
                        Image(systemName: "person")
                            .font(.system(size: 13))
                    }
                }
                .foregroundStyle(theme.railInk)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.10))
                .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Name your shelf")
            .padding(.bottom, 14)
        }
        .frame(width: Tokens.railWidth)
        .background(theme.rail)
    }
}

struct NavRailButton: View {
    let destination: AppState.Destination
    let isActive: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            // Icon only: the words under every icon made the rail read as a
            // settings screen. The icons carry it; accessibility keeps the
            // names.
            Image(systemName: iconName)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(isActive ? theme.railInk : theme.railFaint)
                .frame(width: 56, height: 40)
                .padding(.vertical, 6)
            .background(
                isActive
                    ? Color.white.opacity(0.10)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.button))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityName)
    }

    private var accessibilityName: String {
        switch destination {
        case .bin: "Recycle Bin"
        default: destination.rawValue.capitalized
        }
    }

    private var iconName: String {
        switch destination {
        case .library: "books.vertical"
        case .score: "music.note.list"
        // Named for what is actually behind it. When the tuning reference and
        // page-turn preferences join the metronome, this owes itself a
        // generic bench icon instead.
        case .tools: "metronome"
        case .bin: "trash"
        }
    }
}

struct NavRailToggle: View {
    let icon: String
    let label: String
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(theme.railFaint)
                .frame(width: 56, height: 40)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

