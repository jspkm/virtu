import SwiftUI
import PDFKit
import PencilKit

/// Builds the shareable artifacts. Sharing lives in the LIBRARY now — on the
/// long-press menu of a work or a set — not on the reading screen: the stand
/// is for reading, the shelf is for handing things to people.
enum ScoreExporter {

    /// One work: the part with every visible layer's ink and clippings
    /// flattened onto it, then its Right Pages (in spread order) wherever
    /// they carry anything.
    static func annotatedPDF(work: Work) -> URL? {
        guard let part = work.parts.first else { return nil }
        let renderer = UIGraphicsPDFRenderer(bounds: .zero)
        let data = renderer.pdfData { context in
            append(part: part, to: context)
        }
        return write(data, name: "\(work.title)-annotated")
    }

    /// One set: every work in programme order, each annotated exactly as it
    /// would be alone — the gig binder as one file.
    static func annotatedPDF(program: Program) -> URL? {
        let parts = program.sortedItems
            .compactMap(\.work)
            .filter { $0.deletedAt == nil }
            .compactMap { $0.parts.first }
        guard !parts.isEmpty else { return nil }
        let renderer = UIGraphicsPDFRenderer(bounds: .zero)
        let data = renderer.pdfData { context in
            for part in parts {
                append(part: part, to: context)
            }
        }
        return write(data, name: "\(program.name)-set")
    }

    private static func write(_ data: Data, name: String) -> URL? {
        let safe = name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safe.isEmpty ? "score" : safe).pdf")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private static func append(part: Part, to context: UIGraphicsPDFRendererContext) {
        guard let doc = PDFDocument(url: part.pdfURL) else { return }
        let journal = StrokeJournal.shared

        for pageIdx in 0..<doc.pageCount {
            guard let page = doc.page(at: pageIdx) else { continue }
            let mediaBox = page.bounds(for: .mediaBox)

            let pageRect = CGRect(origin: .zero, size: mediaBox.size)
            context.beginPage(withBounds: pageRect, pageInfo: [:])

            let cgContext = context.cgContext
            cgContext.saveGState()

            // PDF pages have origin at bottom-left; flip for UIKit drawing.
            cgContext.translateBy(x: 0, y: pageRect.height)
            cgContext.scaleBy(x: 1, y: -1)

            page.draw(with: .mediaBox, to: cgContext)

            cgContext.restoreGState()

            // Annotations on top (UIKit coordinates, origin top-left).
            // InkRenderer, not PKDrawing.image — PencilKit rasterization is
            // broken on iPadOS 26.x and would flatten blank ink.
            //
            // Visible layers only, bottom-up: what you share is what you were
            // looking at. A hidden layer is hidden from the stand partner you
            // send this to as well.
            drawClippings(partID: part.id, pageIndex: pageIdx)
            let layers = part.visibleLayerIndices.compactMap {
                journal.load(partID: part.id, pageIndex: pageIdx, layer: $0)
            }
            InkRenderer.draw(layers, in: cgContext)
        }

        appendRightPages(part: part, journal: journal, context: context)
    }

    /// The Right Pages, in spread order, each at the size it was written at.
    /// A spread nobody wrote on is skipped rather than shipped blank.
    private static func appendRightPages(
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

    /// Clippings render under the ink, exactly as they display: the excerpt
    /// taped to the page, written over.
    private static func drawClippings(partID: UUID, pageIndex: Int) {
        for clipping in ClippingStore.shared.clippings(partID: partID, pageIndex: pageIndex) {
            ClippingStore.shared.image(for: clipping)?.draw(in: clipping.rect)
        }
    }
}

/// The system share sheet: AirDrop, Messages, every app that takes a PDF,
/// and the Print / Save to Files row — all of it comes with the controller.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
