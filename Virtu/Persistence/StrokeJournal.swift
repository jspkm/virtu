import Foundation
import PencilKit

/// Durable ink. One record per (part, layer, page).
///
/// Format v2 adds two things to the v1 blob: the **layer** (in the key) and
/// the **authored page size** (in the record). The page size is not used by
/// anything today — it is stored because PRD 7.3 makes it the hinge of the
/// cross-edition thesis, and ink written before it is recorded can never get
/// it back.
///
/// Everything else about a stroke — width, colour, line style — rides inside
/// `PKStroke` itself, so no parallel store has to be kept aligned through
/// lasso and erase.
struct PageInkRecord: Codable {
    var schemaVersion: Int = 2
    var pageWidth: Double
    var pageHeight: Double
    var drawingData: Data

    var pageSize: CGSize { CGSize(width: pageWidth, height: pageHeight) }
}

final class StrokeJournal {
    static let shared = StrokeJournal()

    private let directory: URL
    private let journalDirectory: URL
    private let queue = DispatchQueue(label: "com.virtu.strokejournal", qos: .userInitiated)

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = appSupport.appendingPathComponent("Virtu/Drawings", isDirectory: true)
        journalDirectory = appSupport.appendingPathComponent("Virtu/Journal", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
        replayPendingJournals()
    }

    // MARK: - Public API

    func save(
        _ drawing: PKDrawing,
        partID: UUID,
        pageIndex: Int,
        layer: Int,
        pageSize: CGSize
    ) {
        let record = PageInkRecord(
            pageWidth: Double(pageSize.width),
            pageHeight: Double(pageSize.height),
            drawingData: drawing.dataRepresentation()
        )
        guard let payload = try? JSONEncoder().encode(record) else { return }
        let key = storageKey(partID: partID, pageIndex: pageIndex, layer: layer)

        queue.async { [weak self] in
            guard let self else { return }

            // 1. Write to journal first (append-only, atomic)
            let journalURL = self.journalURL(for: key)
            let entry = JournalEntry(timestamp: Date(), drawingData: payload)
            if let entryData = try? JSONEncoder().encode(entry) {
                let line = entryData + Data([0x0A]) // newline-delimited
                if FileManager.default.fileExists(atPath: journalURL.path) {
                    if let handle = try? FileHandle(forWritingTo: journalURL) {
                        handle.seekToEndOfFile()
                        handle.write(line)
                        try? handle.synchronize()
                        handle.closeFile()
                    }
                } else {
                    try? line.write(to: journalURL, options: .atomic)
                }
            }

            // 2. Write compacted record
            try? payload.write(to: self.recordURL(for: key), options: .atomic)

            // 3. Clear journal after successful compact write
            try? FileManager.default.removeItem(at: journalURL)
        }
    }

    func load(partID: UUID, pageIndex: Int, layer: Int) -> PKDrawing? {
        record(partID: partID, pageIndex: pageIndex, layer: layer).map(\.drawing) ?? nil
    }

    /// The full record, for callers that need the authored page size.
    func record(partID: UUID, pageIndex: Int, layer: Int) -> PageInkRecord? {
        let key = storageKey(partID: partID, pageIndex: pageIndex, layer: layer)
        if let data = try? Data(contentsOf: recordURL(for: key)),
           let record = try? JSONDecoder().decode(PageInkRecord.self, from: data) {
            return record
        }
        // Pre-layer ink belongs to layer 1. Read it forward rather than
        // migrating on launch: a rewrite pass over every page of every part is
        // exactly the moment a crash would cost someone their bowings.
        guard layer == AnnotationLayers.first,
              let data = try? Data(contentsOf: legacyURL(partID: partID, pageIndex: pageIndex))
        else { return nil }
        return PageInkRecord(pageWidth: 0, pageHeight: 0, drawingData: data)
    }

    func deleteAll(partID: UUID, pageCount: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            for pageIndex in 0..<pageCount {
                try? fm.removeItem(at: self.legacyURL(partID: partID, pageIndex: pageIndex))
                for layer in AnnotationLayers.first...AnnotationLayers.max {
                    let key = self.storageKey(partID: partID, pageIndex: pageIndex, layer: layer)
                    try? fm.removeItem(at: self.recordURL(for: key))
                    try? fm.removeItem(at: self.journalURL(for: key))
                }
            }
        }
    }

    // MARK: - Journal replay

    private func replayPendingJournals() {
        queue.async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(at: self.journalDirectory, includingPropertiesForKeys: nil) else { return }

            for journalURL in files where journalURL.pathExtension == "journal" {
                guard let journalData = try? Data(contentsOf: journalURL) else { continue }
                let lines = journalData.split(separator: 0x0A)
                guard let lastLine = lines.last,
                      let entry = try? JSONDecoder().decode(JournalEntry.self, from: Data(lastLine)) else {
                    try? fm.removeItem(at: journalURL)
                    continue
                }

                let key = journalURL.deletingPathExtension().lastPathComponent
                // A journal written before layers existed holds a raw drawing
                // and belongs at the v1 path, where the read-forward above
                // will find it. Zero strokes lost across the format change.
                let isLegacy = !key.contains("-L")
                let compactURL = isLegacy
                    ? self.directory.appendingPathComponent("\(key).pkdrawing")
                    : self.recordURL(for: key)

                let compactDate = (try? fm.attributesOfItem(atPath: compactURL.path)[.modificationDate] as? Date) ?? .distantPast

                if entry.timestamp > compactDate {
                    try? entry.drawingData.write(to: compactURL, options: .atomic)
                }

                try? fm.removeItem(at: journalURL)
            }
        }
    }

    // MARK: - Paths

    private func storageKey(partID: UUID, pageIndex: Int, layer: Int) -> String {
        "\(partID.uuidString)-L\(layer)-page\(pageIndex)"
    }

    private func recordURL(for key: String) -> URL {
        directory.appendingPathComponent("\(key).vink")
    }

    private func journalURL(for key: String) -> URL {
        journalDirectory.appendingPathComponent("\(key).journal")
    }

    /// v1 path: one drawing per page, no layer, no page size.
    private func legacyURL(partID: UUID, pageIndex: Int) -> URL {
        directory.appendingPathComponent("\(partID.uuidString)-page\(pageIndex).pkdrawing")
    }
}

private extension PageInkRecord {
    var drawing: PKDrawing? { try? PKDrawing(data: drawingData) }
}

private struct JournalEntry: Codable {
    let timestamp: Date
    let drawingData: Data
}
