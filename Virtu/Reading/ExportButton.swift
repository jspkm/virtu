import SwiftUI
import PDFKit
import PencilKit

struct ExportButton: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    @State private var showShareSheet = false
    @State private var exportedURL: URL?

    var body: some View {
        // Same face as the rest of the bottom-right row it now sits in.
        ReadingIconButton(systemName: "square.and.arrow.up", label: "Share annotated PDF") {
            exportAnnotatedPDF()
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func exportAnnotatedPDF() {
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
                let layers = part.visibleLayerIndices.compactMap {
                    journal.load(partID: part.id, pageIndex: pageIdx, layer: $0)
                }
                InkRenderer.draw(layers, in: cgContext)
            }
        }

        try? data.write(to: url)
        exportedURL = url
        showShareSheet = true
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
