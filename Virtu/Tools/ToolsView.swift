import SwiftUI

/// The Tools destination — the bench, not the bin.
///
/// It held the Recycle Bin until 2026-08-28, which was only ever a place to
/// put it: a bin is where deleted work waits, not something you reach for
/// mid-practice. The bin now has its own destination and this screen is what
/// the design handoff always drew here — the metronome and the tuning
/// reference, with page-turn preferences still to come beside them.
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

                // The handoff lays these out on a 900pt grid; a metronome
                // stretched the full width of a 13" iPad is a ribbon, not an
                // instrument, so the bench is capped there and the cards sit
                // side by side inside it.
                //
                // Adaptive rather than a fixed pair of columns: the
                // metronome's meter picker and 60pt figure need about 330pt
                // before they start colliding, and on a mini in portrait —
                // or in a narrow Stage Manager window — there is not that
                // much for two. Below the threshold they stack, which is the
                // right answer and not a compromise.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 330, maximum: 460), spacing: 20, alignment: .top)],
                    alignment: .leading,
                    spacing: 20
                ) {
                    MetronomeCard()
                    TunerCard()
                    ForkCard()
                    TurnsCard()
                }
                .frame(maxWidth: 900, alignment: .leading)
            }
            .padding(Tokens.screenPadding)
        }
    }
}
