import SwiftUI
import PDFKit
import PencilKit

struct ExportButton: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    @State private var showShareSheet = false
    @State private var showOptions = false
    @State private var exportedURL: URL?

    var body: some View {
        // Same face as the rest of the bottom-right row it now sits in.
        ReadingIconButton(systemName: "square.and.arrow.up", label: "Share annotated PDF") {
            showOptions = true
        }
        .confirmationDialog("Share", isPresented: $showOptions, titleVisibility: .hidden) {
            Button("Share the part") { exportAnnotatedPDF(includeRightPages: false) }
            Button("Share with Right Pages") { exportAnnotatedPDF(includeRightPages: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Right Pages are added at the end, in the order they sit beside the music.")
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ShareSheet(items: [url])
            }
        }
    }

    /// The part alone by default. The Right Pages are working notes, not part
    /// of the music — a stand partner expects a clean part at the original
    /// page size — so they ship only when asked for, and then as their own
    /// sheets at the end rather than repeated behind every system.
    private func exportAnnotatedPDF(includeRightPages: Bool) {
        guard let part = state.currentPart,
              let doc = PDFDocument(url: part.pdfURL) else { return }

        let journal = StrokeJournal.shared
        let title = state.currentWork?.title ?? "export"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(title)-annotated.pdf")

        let renderer = UIGraphicsPDFRenderer(bounds: .zero)
        let data = renderer.pdfData { context in
            for pageIdx in 0..<doc.pageCount {
                guard let page = doc.page(at: pageIdx) else { continue }
                let mediaBox = page.bounds(for: .mediaBox)

                let pageRect = CGRect(origin: .zero, size: mediaBox.size)
                context.beginPage(withBounds: pageRect, pageInfo: [:])

                let cgContext = context.cgContext
                cgContext.saveGState()

                // PDF pages have origin at bottom-left; flip for UIKit drawing
                cgContext.translateBy(x: 0, y: pageRect.height)
                cgContext.scaleBy(x: 1, y: -1)

                page.draw(with: .mediaBox, to: cgContext)

                cgContext.restoreGState()

                // Draw annotations on top (UIKit coordinates, origin top-left).
                // InkRenderer, not PKDrawing.image — PencilKit rasterization
                // is broken on iPadOS 26.x and would flatten blank ink.
                //
                // Visible layers only, bottom-up: what you exported is what you
                // were looking at. A hidden layer is hidden from the stand
                // partner you send this to as well.
                drawClippings(partID: part.id, pageIndex: pageIdx)
                let layers = part.visibleLayerIndices.compactMap {
                    journal.load(partID: part.id, pageIndex: pageIdx, layer: $0)
                }
                InkRenderer.draw(layers, in: cgContext)
            }

            if includeRightPages {
                drawRightPages(part: part, journal: journal, context: context)
            }
        }

        try? data.write(to: url)
        exportedURL = url
        showShareSheet = true
    }
}

/// Clippings render under the ink on export, exactly as they display: the
/// excerpt taped to the page, written over.
private func drawClippings(partID: UUID, pageIndex: Int) {
    for clipping in ClippingStore.shared.clippings(partID: partID, pageIndex: pageIndex) {
        ClippingStore.shared.image(for: clipping)?.draw(in: clipping.rect)
    }
}

private extension ExportButton {
    /// The Right Pages, in spread order, each at the size it was written at.
    /// One per spread now rather than one per part, so a reader can tell which
    /// stretch of music a sheet belongs to; a spread nobody wrote on is
    /// skipped rather than shipped blank.
    ///
    /// The space under the score contributes nothing: it is scroll headroom
    /// and holds no ink.
    func drawRightPages(
        part: Part, journal: StrokeJournal, context: UIGraphicsPDFRendererContext
    ) {
        guard let firstPage = PDFDocument(url: part.pdfURL)?.page(at: 0) else { return }
        let page = firstPage.bounds(for: .mediaBox).size
        let size = CGSize(width: page.width * Tokens.marginWidthFraction, height: page.height)
        let layers = part.visibleLayerIndices

        for slot in AnnotationLayers.rightPageIndices(pageCount: part.pageCount) {
            let sheet = layers.compactMap {
                journal.load(partID: part.id, pageIndex: slot, layer: $0)
            }
            let clippings = ClippingStore.shared.clippings(partID: part.id, pageIndex: slot)
            guard sheet.contains(where: { !$0.strokes.isEmpty }) || !clippings.isEmpty else { continue }
            context.beginPage(withBounds: CGRect(origin: .zero, size: size), pageInfo: [:])
            drawClippings(partID: part.id, pageIndex: slot)
            InkRenderer.draw(sheet, in: context.cgContext)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
