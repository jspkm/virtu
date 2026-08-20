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
            .statusBarHidden(!state.annotating)
            .persistentSystemOverlays(state.annotating ? .automatic : .hidden)
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            .task(id: performChromeToken) {
                // Perform chrome is a visitor: summoned by long-press,
                // gone again after 8s.
                guard !state.annotating, state.chromeVisible else { return }
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.16)) { state.chromeVisible = false }
            }
        } else {
            noScoreView
        }
    }

    /// Study recesses the page slightly onto the "desk" and frames it with a
    /// hairline accent stroke — the always-visible mode signal.
    private var readingSurface: some View {
        ReadingSurfaceView()
            .scaleEffect(state.annotating ? 0.985 : 1.0)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(theme.accent.opacity(state.annotating ? (state.stageMode ? 0.5 : 0.35) : 0), lineWidth: 1.5)
                    .padding(4)
            )
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

/// The two controls that are always available while reading: the Library, then
/// the reading-mode toggle, in the top-right margin.
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
            HStack(spacing: 0) {
                Spacer()

                ReadingIconButton(systemName: "books.vertical", label: "Library") {
                    Haptics.selection()
                    state.destination = .library
                }

                ReadingIconButton(
                    systemName: state.annotating ? "music.note" : "pencil.tip",
                    label: state.annotating ? "Perform mode" : "Study mode"
                ) {
                    Haptics.light()
                    state.toggleMode()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                        Haptics.medium()
                    }
                }
            }
            .frame(height: Tokens.readingControlMargin)
            .padding(.trailing, 12)

            Spacer()
        }
    }
}

/// Full strength, always. A narrow frame with a tall touch area: the width is
/// what sets the visible gap between the pair, the height is what a pencil tip
/// needs to land on.
private struct ReadingIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    @Environment(\.theme) private var theme
    @State private var pressed = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: Tokens.readingControlGlyph))
            .foregroundStyle(pressed ? theme.accent : theme.ink)
            .frame(width: Tokens.readingControlIcon.width, height: Tokens.readingControlIcon.height)
            .contentShape(Rectangle())
            .scaleEffect(pressed ? 1.15 : 1.0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        withAnimation(.easeOut(duration: 0.12)) { pressed = true }
                    }
                    .onEnded { value in
                        withAnimation(.easeOut(duration: 0.12)) { pressed = false }
                        // A finger that slid off the control is a miss, not a tap.
                        let d = hypot(value.translation.width, value.translation.height)
                        guard d < 24 else { return }
                        action()
                    }
            )
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
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
                Text("Tap the edges to turn \u{00B7} tap \u{270E} top-right for Study")
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
