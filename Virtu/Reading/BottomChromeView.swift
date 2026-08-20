import SwiftUI
import PDFKit

struct BottomChromeView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 14) {
                thumbnailStrip

                Text("Tap the edges to turn \u{00B7} two-finger double-tap to switch modes.")
                    .font(VFont.metadata)
                    .foregroundStyle(theme.faint)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [theme.paper.opacity(0), theme.paper, theme.paper],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .transition(.opacity.animation(.easeOut(duration: 0.16)))
    }

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    if let part = state.currentPart {
                        ForEach(0..<part.pageCount, id: \.self) { pageIdx in
                            let isCurrent = state.visiblePageIndices.contains(pageIdx)

                            Button {
                                Haptics.selection()
                                state.goToPage(pageIdx)
                            } label: {
                                VStack(spacing: 4) {
                                    PageThumbnailView(part: part, pageIndex: pageIdx, stage: state.stageMode)
                                        .frame(width: 38, height: isCurrent ? 54 : 48)
                                        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.pageThumbnail))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Tokens.Radius.pageThumbnail)
                                                .stroke(isCurrent ? theme.accent : theme.line2.opacity(0.55), lineWidth: isCurrent ? 1.5 : 1)
                                        )

                                    Rectangle()
                                        .fill(isCurrent ? theme.accent : Color.clear)
                                        .frame(width: 22, height: 2)

                                    Text("\(pageIdx + 1)")
                                        .font(VFont.pageNumber)
                                        .foregroundStyle(isCurrent ? theme.accent : theme.faint)
                                }
                            }
                            .buttonStyle(.plain)
                            .id(pageIdx)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .onAppear {
                proxy.scrollTo(state.pageIndex, anchor: .center)
            }
            .onChange(of: state.pageIndex) { _, newIndex in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }
}

/// Async page thumbnail, cached process-wide. Follows the Stage theme.
private struct PageThumbnailView: View {
    let part: Part
    let pageIndex: Int
    let stage: Bool
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(hex: stage ? 0x1A1814 : 0xEFEBE2)
            }
        }
        .task(id: "\(pageIndex)-\(stage)") {
            image = await ThumbnailStore.shared.thumbnail(part: part, pageIndex: pageIndex, stage: stage)
        }
    }
}

/// Renders and caches small page thumbnails for the scrubber and library.
actor ThumbnailStore {
    static let shared = ThumbnailStore()

    private var cache: [String: UIImage] = [:]
    private var documents: [UUID: PDFDocument] = [:]

    func thumbnail(part: Part, pageIndex: Int, stage: Bool = false) async -> UIImage? {
        let key = "\(part.id)-\(pageIndex)-\(stage ? "s" : "p")"
        if let hit = cache[key] { return hit }

        let doc: PDFDocument
        if let existing = documents[part.id] {
            doc = existing
        } else if let loaded = PDFDocument(url: part.pdfURL) {
            documents[part.id] = loaded
            doc = loaded
        } else {
            return nil
        }

        guard let page = doc.page(at: pageIndex) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale = 3.0
        let height = 54.0 * scale
        let width = height * (bounds.width / max(bounds.height, 1))
        var image = page.thumbnail(of: CGSize(width: width, height: height), for: .mediaBox)
        if stage {
            image = image.stageRemapped() ?? image
        }
        cache[key] = image
        return image
    }
}
