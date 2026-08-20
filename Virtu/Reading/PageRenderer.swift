import UIKit
import PDFKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Renders PDF pages to bitmaps ahead of need so a page turn is pure
/// compositing, never a live PDF decode (latency budget: <120ms).
/// Also produces the Stage variant: a luminance remap (not an invert-and-forget)
/// — paper drops to near-black #0A0908, notation lifts to warm white #EDE7DC.
final class PageRenderer {

    let document: PDFDocument
    let pageSize: CGSize

    private let cache = NSCache<NSString, UIImage>()
    private let renderQueue = DispatchQueue(label: "com.virtu.pageRenderer", qos: .userInitiated)
    private var inFlight = Set<String>()
    private let inFlightLock = NSLock()

    init?(url: URL) {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { return nil }
        self.document = doc
        self.pageSize = doc.page(at: 0)?.bounds(for: .mediaBox).size ?? CGSize(width: 595, height: 842)
        cache.countLimit = 12
    }

    var pageCount: Int { document.pageCount }

    /// Cached image if available; triggers a background render if not.
    func image(at index: Int, height: CGFloat, stage: Bool, completion: ((UIImage) -> Void)? = nil) -> UIImage? {
        let key = cacheKey(index: index, height: height, stage: stage)
        if let hit = cache.object(forKey: key as NSString) {
            return hit
        }
        renderAsync(index: index, height: height, stage: stage, completion: completion)
        return nil
    }

    /// Synchronous render for when the image is needed right now (first display).
    func imageNow(at index: Int, height: CGFloat, stage: Bool) -> UIImage? {
        let key = cacheKey(index: index, height: height, stage: stage)
        if let hit = cache.object(forKey: key as NSString) {
            return hit
        }
        guard let rendered = render(index: index, height: height, stage: stage) else { return nil }
        cache.setObject(rendered, forKey: key as NSString)
        return rendered
    }

    /// Pre-render neighbours so upcoming turns composite instantly.
    func prefetch(around index: Int, span: Int, height: CGFloat, stage: Bool) {
        for i in (index - span)...(index + span) where i >= 0 && i < pageCount {
            renderAsync(index: i, height: height, stage: stage, completion: nil)
        }
    }

    // MARK: - Internals

    private func cacheKey(index: Int, height: CGFloat, stage: Bool) -> String {
        "\(index)-\(Int(height.rounded()))-\(stage ? "s" : "p")"
    }

    private func renderAsync(index: Int, height: CGFloat, stage: Bool, completion: ((UIImage) -> Void)?) {
        let key = cacheKey(index: index, height: height, stage: stage)
        inFlightLock.lock()
        let alreadyRunning = inFlight.contains(key)
        if !alreadyRunning { inFlight.insert(key) }
        inFlightLock.unlock()
        guard !alreadyRunning else { return }

        renderQueue.async { [weak self] in
            guard let self else { return }
            let rendered = self.render(index: index, height: height, stage: stage)
            self.inFlightLock.lock()
            self.inFlight.remove(key)
            self.inFlightLock.unlock()
            guard let rendered else { return }
            self.cache.setObject(rendered, forKey: key as NSString)
            if let completion {
                DispatchQueue.main.async { completion(rendered) }
            }
        }
    }

    private func render(index: Int, height: CGFloat, stage: Bool) -> UIImage? {
        guard index >= 0, index < pageCount, let page = document.page(at: index) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.height > 0, height > 0 else { return nil }

        let scale = UIScreen.main.scale
        let pixelHeight = height * scale
        let pixelWidth = pixelHeight * (bounds.width / bounds.height)
        let size = CGSize(width: pixelWidth, height: pixelHeight)

        let paper = page.thumbnail(of: size, for: .mediaBox)
        guard stage else {
            return UIImage(cgImage: paper.cgImage ?? UIImage().cgImage!, scale: scale, orientation: .up)
        }
        return paper.stageRemapped() ?? paper
    }
}
