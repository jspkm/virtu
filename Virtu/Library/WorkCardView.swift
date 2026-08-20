import SwiftUI
import PDFKit

struct WorkCardView: View {
    let work: Work
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Preview area
            ZStack(alignment: .bottom) {
                thumbnailView
                    .opacity(0.9)
                    .offset(y: -14)

                LinearGradient(
                    colors: [theme.plate.opacity(0), theme.plate],
                    startPoint: .init(x: 0.5, y: 0),
                    endPoint: .init(x: 0.5, y: 1)
                )
                .frame(height: 52)
            }
            .frame(height: 148)
            .clipped()

            Rectangle()
                .fill(theme.line)
                .frame(height: 1)

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

    @ViewBuilder
    private var thumbnailView: some View {
        if let part = work.parts.first,
           let doc = PDFDocument(url: part.pdfURL),
           let page = doc.page(at: 0) {
            let image = page.thumbnail(of: CGSize(width: 210, height: 297), for: .mediaBox)
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 210)
        } else {
            Rectangle()
                .fill(theme.wash)
                .frame(height: 210)
        }
    }
}

extension Date {
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: .now)
    }
}
