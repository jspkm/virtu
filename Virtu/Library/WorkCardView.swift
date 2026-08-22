import SwiftUI

struct WorkCardView: View {
    let work: Work
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // No engraving preview: at card size every first page is the same
            // grey smudge, so it spent 148pt saying nothing the title does
            // not. Title and metadata carry the card.
            // Body
            VStack(alignment: .leading, spacing: 6) {
                if let part = work.parts.first {
                    Text(work.composer)
                        .font(VFont.metadata)
                        .foregroundStyle(theme.muted)

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

                Spacer()

                // Practice progress: how far into the part you've been,
                // and when you last had it on the stand.
                if let part = work.parts.first {
                    HStack(spacing: 12) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(theme.line)
                                    .frame(height: 2)
                                Capsule()
                                    .fill(theme.accent)
                                    .frame(
                                        width: geo.size.width * progressFraction(part),
                                        height: 2
                                    )
                            }
                            .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 8)

                        Text(work.lastOpenedAt.relativeDescription)
                            .font(VFont.catalogueNumber)
                            .foregroundStyle(theme.faint)
                            .fixedSize()
                    }
                }
            }
            .padding(EdgeInsets(top: 15, leading: 16, bottom: 16, trailing: 16))
            // A consistent card height keeps grid rows level now that no
            // preview establishes one.
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        }
        .background(theme.plate)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .stroke(theme.line, lineWidth: 1)
        )
    }

    private func progressFraction(_ part: Part) -> CGFloat {
        guard part.pageCount > 1 else { return part.furthestPageIndex > 0 ? 1 : 0 }
        return CGFloat(min(part.furthestPageIndex, part.pageCount - 1)) / CGFloat(part.pageCount - 1)
    }

}

extension Date {
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: .now)
    }
}
