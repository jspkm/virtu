import Foundation
import SwiftData
import PDFKit

enum SeedData {

    private static let works: [(composer: String, title: String, catalogue: String, edition: String, partName: String, filename: String, minutes: Int)] = [
        ("J. S. Bach", "Cello Suite no. 1 in G major", "BWV 1007", "Barenreiter, Schwemer/Woodfull-Harris", "cello", "bach-cello-suite-1", 18),
        ("Franz Schubert", "String Quintet in C major", "D. 956", "Barenreiter urtext", "cello II", "schubert-string-quintet", 52),
        ("Johannes Brahms", "Piano Quartet no. 1 in G minor", "Op. 25", "Henle", "viola", "brahms-piano-quartet-1", 40),
    ]

    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Work>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }

        var seeded: [Work] = []
        for entry in works {
            guard let bundleURL = Bundle.main.url(
                forResource: entry.filename,
                withExtension: "pdf"
            ) else { continue }

            let storedName = "\(UUID().uuidString).pdf"
            let destination = Part.storageDirectory.appendingPathComponent(storedName)

            guard let _ = try? FileManager.default.copyItem(at: bundleURL, to: destination),
                  let doc = PDFDocument(url: destination) else { continue }

            let work = Work(
                composer: entry.composer,
                title: entry.title,
                catalogueNumber: entry.catalogue,
                edition: entry.edition
            )
            let daysAgo = Double([1, 7, 21][works.firstIndex(where: { $0.filename == entry.filename }) ?? 0])
            work.lastOpenedAt = Date(timeIntervalSinceNow: -daysAgo * 86400)

            let part = Part(
                name: entry.partName,
                pdfFileName: storedName,
                pageCount: doc.pageCount
            )
            work.parts.append(part)
            context.insert(work)
            seeded.append(work)
        }

        // A first program so the shelf opens with a concert on the horizon:
        // the three seed works as a recital set, four weeks out at 19:30.
        if seeded.count == works.count {
            var date = Calendar.current.date(byAdding: .day, value: 28, to: .now) ?? .now
            date = Calendar.current.date(bySettingHour: 19, minute: 30, second: 0, of: date) ?? date

            let program = Program(name: "Wigmore recital", venue: "Wigmore Hall", date: date)
            context.insert(program)
            for (idx, work) in seeded.enumerated() {
                let item = ProgramItem(index: idx, durationMinutes: works[idx].minutes, work: work)
                item.program = program
                context.insert(item)
            }
        }

        try? context.save()
    }
}
