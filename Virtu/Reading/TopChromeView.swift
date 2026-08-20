import SwiftUI

struct TopChromeView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        VStack {
            // Library and the mode toggle now live in the always-on controls
            // at the top-right (ReadingControlsView), so the chrome carries
            // only what it alone can: what you are looking at, and export.
            HStack(spacing: 16) {
                // Title block
                if let work = state.currentWork {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(work.composer) \u{2014} \(work.title)")
                            .font(VFont.nowPlayingTitle)
                            .foregroundStyle(theme.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        HStack(spacing: 0) {
                            if let program = state.currentProgram,
                               let position = state.programPosition {
                                Text("\(program.name) \u{00B7} \(position.index.romanNumeral) of \((position.count - 1).romanNumeral)")
                                    .font(VFont.metadata)
                                    .foregroundStyle(theme.accent)
                                Text("  \u{00B7}  ")
                                    .foregroundStyle(theme.muted)
                            }
                            if !work.catalogueNumber.isEmpty {
                                Text(work.catalogueNumber)
                                    .font(VFont.metadata)
                                    .foregroundStyle(theme.muted)
                                Text(" \u{00B7} ")
                                    .foregroundStyle(theme.muted)
                            }
                            if !work.edition.isEmpty {
                                Text(work.edition)
                                    .font(VFont.metadata)
                                    .foregroundStyle(theme.muted)
                                Text(" \u{00B7} ")
                                    .foregroundStyle(theme.muted)
                            }
                            if let part = state.currentPart {
                                Text(part.name)
                                    .font(VFont.metadata)
                                    .foregroundStyle(theme.muted)
                            }
                        }
                    }
                }

                Spacer()

                // Export button
                ExportButton()
            }
            .padding(.leading, 20)
            // Keep clear of the always-on controls above.
            .padding(.trailing, Tokens.readingControlsBand)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [theme.paper, theme.paper, theme.paper.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Spacer()
        }
        .transition(.opacity.animation(.easeOut(duration: 0.16)))
    }
}
