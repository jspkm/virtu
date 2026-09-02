import SwiftUI

/// The reading screen. Hosts the UIKit reading surface and layers SwiftUI
/// chrome over it. Owns the Perform/Study mode transition ("settle"),
/// Perform-mode hygiene (hidden status bar, no system overlays, screen kept
/// awake, faint page readout), and the Stage brightness suggestion.
struct ReadingContainerView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    /// Signature mode-transition motion from the design spec.
    private static let settle = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.26)

    private var performChromeToken: String {
        "\(state.readingMode.rawValue)-\(state.chromeVisible)"
    }

    var body: some View {
        if state.currentPart != nil {
            ZStack {
                theme.paper
                    .ignoresSafeArea()

                readingSurface

                if state.annotating {
                    ToolRailView()
                }

                if !state.annotating {
                    PageReadoutView()
                    FirstOpenHintView()
                }

                if state.chromeVisible {
                    TopChromeView()
                    BottomChromeView()
                }

                // Last, so the two always-available controls stay on top of
                // any chrome that happens to be up.
                ReadingControlsView()

                StageBrightnessToast()
            }
            // The status bar rides with the chrome: score info and clock
            // arrive together and leave together.
            .statusBarHidden(!state.chromeVisible)
            .persistentSystemOverlays(state.annotating ? .automatic : .hidden)
            .onAppear { ScreenWake.shared.claim("reading") }
            .onDisappear { ScreenWake.shared.release("reading") }
            .task(id: performChromeToken) {
                // Chrome is a visitor in BOTH modes: summoned by touching the
                // top of the score, gone again on its own. Nobody needs the
                // title of the piece they are playing for more than a glance.
                guard state.chromeVisible else { return }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.16)) { state.chromeVisible = false }
            }
        } else {
            noScoreView
        }
    }

    /// The page, both modes. The recess-and-accent-frame mode signal is gone:
    /// stacked with the page's own border it read as a nest of lines around
    /// the score, and the tool rail already says which mode you are in.
    private var readingSurface: some View {
        ReadingSurfaceView()
            .animation(Self.settle, value: state.annotating)
            .ignoresSafeArea(edges: state.annotating ? [] : .all)
    }

    private var noScoreView: some View {
        VStack(spacing: 12) {
            Text("No score open")
                .font(VFont.sectionHeading)
                .foregroundStyle(theme.ink)
            Text("Choose a work from the library.")
                .font(VFont.body)
                .foregroundStyle(theme.muted)
            Button("Go to Library") {
                state.destination = .library
            }
            .font(VFont.control)
            .foregroundStyle(theme.paper)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(theme.ink)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.button))
            .buttonStyle(.plain)
        }
    }
}

/// Perform mode's only persistent element: "12 / 34" bottom-center, dimming
/// from 40% to 15% opacity after 4s idle — never fully gone, because page-
/// position anxiety costs more than this sliver of chrome.
private struct PageReadoutView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    @State private var dimmed = false

    var body: some View {
        VStack {
            Spacer()
            Text(readout)
                .font(VFont.pageNumber)
                .foregroundStyle(theme.muted)
                .opacity(dimmed ? (state.stageMode ? 0.1 : 0.15) : (state.stageMode ? 0.2 : 0.4))
                .padding(.bottom, 10)
        }
        .allowsHitTesting(false)
        .task(id: state.pageIndex) {
            dimmed = false
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.18)) { dimmed = true }
        }
    }

    private var readout: String {
        let last = state.visiblePageIndices.upperBound
        return "\(state.pageIndex + 1)\(state.pagesPerView == 2 && last > state.pageIndex + 1 ? "–\(last)" : "") / \(state.pageCount)"
    }
}

/// The controls that are always available while reading: the Library, then the
/// reading-mode toggle, in the **bottom**-right margin — joined by Share
/// whenever the chrome is up.
///
/// Bottom because the top right is iPadOS's. The status bar is visible in
/// Study, so icons placed up there are read through the wifi and battery
/// indicators.
///
/// They persist in Perform as well as Study — a knowing exception to the M2
/// rule that Perform shows "the page and nothing else". A stranger handed the
/// iPad five minutes before a downbeat must be able to see the way out. What
/// pays for the exception is *position*, not faintness: the spread reserves a
/// margin band above it (`Tokens.readingControlMargin`), so these sit beside
/// the page and never over a note. Chrome that is off the score can afford to
/// be legible, and an icon you have to hunt for is worse than one you can see.
private struct ReadingControlsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        VStack {
            Spacer()

            HStack(spacing: Tokens.readingControlSpacing) {
                Spacer()

                // No share here: the stand is for reading. Sharing lives on
                // the long-press menus in the Library.
                ReadingIconButton(systemName: "books.vertical", label: "Library") {
                    Haptics.selection()
                    state.destination = .library
                }

                ReadingIconButton(
                    systemName: state.annotating ? "music.note" : "pencil.tip",
                    label: state.annotating ? "Perform mode" : "Study mode"
                ) {
                    // One knock, now. The second one landed 260ms later to
                    // mark the end of the settle, which read as the switch
                    // itself being late.
                    Haptics.medium()
                    state.toggleMode()
                }
            }
            .frame(height: Tokens.readingControlIcon.height)
            .padding(.trailing, 12)
            .padding(.bottom, Tokens.readingControlBottomInset)
        }
    }
}

/// Full strength, always, and a plain Button rather than a hand-rolled
/// DragGesture — the machinery that makes a tap forgiving (touch slop, press
/// tracking, cancellation on drag-away) is exactly what a bare drag gesture
/// does not have, and a finger needs all of it.
struct ReadingIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: Tokens.readingControlGlyph))
        }
        .buttonStyle(ReadingIconButtonStyle())
        .accessibilityLabel(label)
    }
}

private struct ReadingIconButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // The Repertoire red, translucent: big enough to hit with a
            // finger, quiet enough that the system under it stays readable.
            .foregroundStyle(theme.accent.opacity(configuration.isPressed ? 0.95 : 0.55))
            .frame(
                width: Tokens.readingControlIcon.width,
                height: Tokens.readingControlIcon.height
            )
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 1.15 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Shown once, ever: the first time a score opens, a quiet line above the page
/// readout teaches the two gestures that matter. Fades after 8s and never
/// returns.
private struct FirstOpenHintView: View {
    @Environment(\.theme) private var theme
    @State private var visible = false

    var body: some View {
        VStack {
            Spacer()
            if visible {
                Text("Tap the edges to turn \u{00B7} \u{270E} bottom-right for Study \u{00B7} touch the top for score info")
                    .font(VFont.metadata)
                    .foregroundStyle(theme.muted)
                    .opacity(0.75)
                    .padding(.bottom, 30)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .task {
            guard !UserDefaults.standard.bool(forKey: "performHintSeen") else { return }
            UserDefaults.standard.set(true, forKey: "performHintSeen")
            withAnimation(.easeIn(duration: 0.4)) { visible = true }
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.6)) { visible = false }
        }
    }
}

/// One-time, non-blocking suggestion when entering Stage with a bright screen.
/// Never adjusts silently — the ramp only happens on explicit tap.
private struct StageBrightnessToast: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    @State private var visible = false

    var body: some View {
        VStack {
            if visible {
                HStack(spacing: 12) {
                    Text("Stage looks best around 30% brightness.")
                        .font(VFont.metadata)
                        .foregroundStyle(theme.ink)
                    Button("Adjust") {
                        UIScreen.main.brightness = 0.3
                        withAnimation { visible = false }
                    }
                    .font(VFont.control)
                    .foregroundStyle(theme.accent)
                    .buttonStyle(.plain)
                    Button {
                        withAnimation { visible = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.faint)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(theme.plate)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(theme.line2, lineWidth: 1))
                .padding(.top, 24)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .onChange(of: state.stageMode) { _, isStage in
            guard isStage, !state.stageBrightnessSuggested, UIScreen.main.brightness > 0.4 else { return }
            state.stageBrightnessSuggested = true
            withAnimation(.easeOut(duration: 0.26)) { visible = true }
            Task {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                withAnimation { visible = false }
            }
        }
    }
}
