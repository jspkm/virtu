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
            Button("Share the part") { exportAnnotatedPDF(includeMargins: false) }
            Button("Share with margin notes") { exportAnnotatedPDF(includeMargins: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Margin notes are added as one extra page at the end.")
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ShareSheet(items: [url])
            }
        }
    }

    /// The part alone by default. The shared margins are working notes, not
    /// part of the music — a stand partner expects a clean part at the
    /// original page size — so they ship only when asked for, and then as a
    /// single page at the end rather than repeated behind every system.
    private func exportAnnotatedPDF(includeMargins: Bool) {
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

            if includeMargins {
                drawMarginPage(part: part, journal: journal, context: context)
            }
        }

        try? data.write(to: url)
        exportedURL = url
        showShareSheet = true
    }
}

private extension ExportButton {
    /// One page carrying both margins in the arrangement they are written in.
    func drawMarginPage(
        part: Part, journal: StrokeJournal, context: UIGraphicsPDFRendererContext
    ) {
        let layers = part.visibleLayerIndices
        let side = layers.compactMap {
            journal.load(partID: part.id, pageIndex: AnnotationLayers.marginRightIndex, layer: $0)
        }
        let bottom = layers.compactMap {
            journal.load(partID: part.id, pageIndex: AnnotationLayers.marginBottomIndex, layer: $0)
        }
        guard side.contains(where: { !$0.strokes.isEmpty })
                || bottom.contains(where: { !$0.strokes.isEmpty }) else { return }

        guard let firstPage = PDFDocument(url: part.pdfURL)?.page(at: 0) else { return }
        let page = firstPage.bounds(for: .mediaBox).size
        let marginW = page.width * Tokens.marginWidthFraction
        let marginH = page.height * Tokens.marginHeightFraction
        let size = CGSize(width: marginW + page.width * 2, height: page.height + marginH)

        context.beginPage(withBounds: CGRect(origin: .zero, size: size), pageInfo: [:])
        let cg = context.cgContext

        // Laid out as written: the side margin outboard of where the spread
        // would be, the bottom margin across the foot, and the space the music
        // occupied left empty.
        cg.saveGState()
        cg.translateBy(x: page.width * 2, y: 0)
        InkRenderer.draw(side, in: cg)
        cg.restoreGState()

        cg.saveGState()
        cg.translateBy(x: 0, y: page.height)
        InkRenderer.draw(bottom, in: cg)
        cg.restoreGState()
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
