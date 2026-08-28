import SwiftUI

/// The Tools destination — the bench, not the bin.
///
/// It held the Recycle Bin until 2026-08-28, which was only ever a place to
/// put it: a bin is where deleted work waits, not something you reach for
/// mid-practice. The bin now has its own destination and this screen is what
/// the design handoff always drew here — the metronome, and in time the
/// tuning reference and page-turn preferences beside it.
struct ToolsView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Tools")
                    .screenEyebrow()
                    .padding(.bottom, 6)

                Text("On the stand.")
                    .font(VFont.body)
                    .foregroundStyle(theme.muted)
                    .padding(.bottom, 28)

                // The handoff sizes this card at 1.15fr of a 900pt grid; a
                // metronome stretched the full width of a 13" iPad is a
                // ribbon, not an instrument. The tuner lands beside it, which
                // is why this is a grid of one rather than a lone card.
                LazyVGrid(
                    columns: [GridItem(.flexible(maximum: 480), spacing: 20, alignment: .top)],
                    alignment: .leading,
                    spacing: 20
                ) {
                    MetronomeCard()
                }
            }
            .padding(Tokens.screenPadding)
        }
    }
}
