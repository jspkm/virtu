import UIKit

/// A clipping: a rectangle of the page — engraving and ink together — copied
/// with the lasso's Copy mode and dropped somewhere else, the Right Page
/// included. The excerpt a musician tapes into their part.
///
/// Clippings are page furniture, not strokes: they live beside the stroke
/// journal, never inside it. The journal's format and its stroke-loss
/// guarantees are untouched by this feature existing.
struct Clipping: Codable, Identifiable, Equatable {
    let id: UUID
    /// Journal-style page slot: real page index, or a Right Page slot.
    var pageIndex: Int
    /// Placement in PDF-point space (origin top-left), the same coordinate
    /// system strokes persist in — so rotation rescales a clipping exactly
    /// as it rescales ink.
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var imageFile: String

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// Sidecar store: one JSON manifest per part plus a PNG per clipping, under
/// Application Support. Writes are atomic and the PNG lands before the
/// manifest references it, so a crash can strand an orphan image but never a
/// manifest entry pointing at nothing.
final class ClippingStore {
    static let shared = ClippingStore()

    private var cache: [UUID: [Clipping]] = [:]
    private var imageCache = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "com.virtu.clippings", qos: .userInitiated)

    private let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Clippings", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private func manifestURL(partID: UUID) -> URL {
        directory.appendingPathComponent("\(partID.uuidString).json")
    }

    // MARK: - Reading

    func clippings(partID: UUID, pageIndex: Int) -> [Clipping] {
        all(partID: partID).filter { $0.pageIndex == pageIndex }
    }

    func all(partID: UUID) -> [Clipping] {
        if let hit = cache[partID] { return hit }
        let loaded = (try? Data(contentsOf: manifestURL(partID: partID)))
            .flatMap { try? JSONDecoder().decode([Clipping].self, from: $0) } ?? []
        cache[partID] = loaded
        return loaded
    }

    func image(for clipping: Clipping) -> UIImage? {
        let key = clipping.imageFile as NSString
        if let hit = imageCache.object(forKey: key) { return hit }
        guard let image = UIImage(contentsOfFile:
            directory.appendingPathComponent(clipping.imageFile).path) else { return nil }
        imageCache.setObject(image, forKey: key)
        return image
    }

    // MARK: - Writing

    @discardableResult
    func add(partID: UUID, pageIndex: Int, rect: CGRect, image: UIImage) -> Clipping? {
        guard let png = image.pngData() else { return nil }
        let id = UUID()
        let file = "\(id.uuidString).png"
        let clipping = Clipping(
            id: id, pageIndex: pageIndex,
            x: rect.origin.x, y: rect.origin.y,
            width: rect.width, height: rect.height,
            imageFile: file
        )
        var list = all(partID: partID)
        list.append(clipping)
        cache[partID] = list
        imageCache.setObject(image, forKey: file as NSString)
        queue.async { [directory, manifest = manifestURL(partID: partID)] in
            // Image first, then the manifest that points at it.
            try? png.write(to: directory.appendingPathComponent(file), options: .atomic)
            if let data = try? JSONEncoder().encode(list) {
                try? data.write(to: manifest, options: .atomic)
            }
        }
        return clipping
    }

    func remove(partID: UUID, clippingID: UUID) {
        var list = all(partID: partID)
        guard let idx = list.firstIndex(where: { $0.id == clippingID }) else { return }
        let removed = list.remove(at: idx)
        cache[partID] = list
        queue.async { [directory, manifest = manifestURL(partID: partID)] in
            if let data = try? JSONEncoder().encode(list) {
                try? data.write(to: manifest, options: .atomic)
            }
            try? FileManager.default.removeItem(
                at: directory.appendingPathComponent(removed.imageFile))
        }
    }

    /// Everything the part owns — the delete-work path.
    func deleteAll(partID: UUID) {
        let list = all(partID: partID)
        cache[partID] = []
        queue.async { [directory, manifest = manifestURL(partID: partID)] in
            try? FileManager.default.removeItem(at: manifest)
            for clipping in list {
                try? FileManager.default.removeItem(
                    at: directory.appendingPathComponent(clipping.imageFile))
            }
        }
    }
}
