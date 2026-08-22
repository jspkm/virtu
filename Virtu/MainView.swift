import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    private static let settle = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.26)

    /// Reading is a full-bleed surface: the rail gets out of the way.
    private var railCollapsed: Bool {
        state.destination == .score && state.currentPart != nil
    }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                if !railCollapsed {
                    NavRailView()
                }

                Group {
                    switch state.destination {
                    case .library:
                        LibraryView()
                    case .score:
                        ReadingContainerView()
                    case .find:
                        FindStubView()
                    case .tools:
                        ToolsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if railCollapsed {
                ghostSliver

                if state.railExpanded {
                    // Tap-away catcher behind the overlaid rail.
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(Self.settle) { state.railExpanded = false }
                        }

                    NavRailView()
                        .shadow(color: .black.opacity(0.25), radius: 18, x: 6, y: 0)
                        .transition(.move(edge: .leading))
                        .task {
                            try? await Task.sleep(nanoseconds: 8_000_000_000)
                            guard !Task.isCancelled else { return }
                            withAnimation(Self.settle) { state.railExpanded = false }
                        }
                }
            }
        }
        .background(theme.paper)
        .ignoresSafeArea()
        .animation(Self.settle, value: railCollapsed)
        .animation(Self.settle, value: state.railExpanded)
        .onChange(of: state.destination) {
            state.railExpanded = false
        }
    }

    /// The design spec's "ghost edge": a 12pt sliver that whispers where the
    /// rail lives. Tap or swipe right to summon it.
    private var ghostSliver: some View {
        HStack {
            ZStack {
                theme.rail.opacity(0.08)
                Capsule()
                    .fill(theme.rail.opacity(0.35))
                    .frame(width: 3, height: 28)
            }
            .frame(width: 12)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(Self.settle) { state.railExpanded = true }
            }
            .gesture(
                DragGesture(minimumDistance: 15)
                    .onEnded { value in
                        if value.translation.width > 15 {
                            withAnimation(Self.settle) { state.railExpanded = true }
                        }
                    }
            )
            Spacer()
        }
        .ignoresSafeArea()
    }
}

struct FindStubView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            Text("Find & Import")
                .font(VFont.sectionHeading)
                .foregroundStyle(theme.ink)
            Text("Coming in M1")
                .font(VFont.metadata)
                .foregroundStyle(theme.muted)
        }
    }
}

