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
                label: "Stage",
                isActive: false
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
            VStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .regular))
                Text(destination.rawValue.capitalized)
                    .font(VFont.railLabel)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            .foregroundStyle(isActive ? theme.railInk : theme.railFaint)
            .frame(width: 56)
            .padding(.vertical, 8)
            .background(
                isActive
                    ? Color.white.opacity(0.10)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.button))
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch destination {
        case .library: "books.vertical"
        case .score: "pencil"
        case .find: "magnifyingglass"
        case .tools: "metronome"
        }
    }
}

struct NavRailToggle: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                Text(label)
                    .font(VFont.railLabel)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            .foregroundStyle(theme.railFaint)
            .frame(width: 56)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

