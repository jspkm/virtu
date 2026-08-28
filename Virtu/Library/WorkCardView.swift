import SwiftUI

struct WorkCardView: View {
    let work: Work
    @Environment(\.theme) private var theme

    var body: some View {
        // No engraving preview: at card size every first page is the same
        // grey smudge, so it spent 148pt saying nothing the title does not.
        // Title and metadata carry the card.
        VStack(alignment: .leading, spacing: 6) {
            if let part = work.parts.first {
                // An unattributed import shows no composer line at all
                // rather than an empty one holding open a gap.
                if !work.composer.isEmpty {
                    Text(work.composer)
                        .font(VFont.metadata)
                        .foregroundStyle(theme.muted)
                }

                Text(work.title)
                    .font(VFont.workTitle)
                    .foregroundStyle(theme.ink)
                    .lineLimit(2)

                HStack(spacing: 0) {
                    if !work.catalogueNumber.isEmpty {
                        Text(work.catalogueNumber)
                            .font(VFont.catalogueNumber)
                            .foregroundStyle(theme.faint)
                        Text(" · ")
                            .font(VFont.metadata)
                            .foregroundStyle(theme.faint)
                    }
                    Text(part.name)
                        .font(VFont.metadata)
                        .foregroundStyle(theme.muted)
                }
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        // The card hugs its text now. A practice-progress rule used to run
        // along the bottom, held down there by a Spacer against a 118pt
        // floor — removed 2026-08-28, and with it the only reason the box
        // stood taller than what it says. maxHeight keeps a row level when a
        // two-line title sits beside a one-line one.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .plateCard()
    }
}
