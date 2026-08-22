import SwiftUI
import SwiftData
import PDFKit

struct ImportMetadataSheet: View {
    let pdfURL: URL
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var composer = ""
    @State private var title = ""
    @State private var catalogueNumber = ""
    @State private var edition = ""
    @State private var partName = "score"
    @State private var pageCount = 0
    @State private var estimatedMinutes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    thumbnailPreview
                }

                Section("Work") {
                    TextField("Composer", text: $composer)
                    TextField("Title", text: $title)
                    TextField("Catalogue number (e.g. BWV 1007)", text: $catalogueNumber)
                    TextField("Edition (e.g. Bärenreiter urtext)", text: $edition)
                }

                Section("Part") {
                    TextField("Part name (e.g. cello, piano)", text: $partName)
                    LabeledContent("Pages", value: "\(pageCount)")
                }

                Section {
                    TextField("Estimated minutes", text: $estimatedMinutes)
                        .keyboardType(.numberPad)
                } footer: {
                    Text("Guessed from the page count \u{2014} correct it if you know better. Programme entries start from this.")
                }
            }
            .navigationTitle("Confirm import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add to library") { save() }
                        .disabled(composer.isEmpty || title.isEmpty)
                }
            }
        }
        .onAppear(perform: extractMetadata)
    }

    @ViewBuilder
    private var thumbnailPreview: some View {
        if let doc = PDFDocument(url: pdfURL),
           let page = doc.page(at: 0) {
            let image = page.thumbnail(of: CGSize(width: 300, height: 420), for: .mediaBox)
            HStack {
                Spacer()
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.scorePage))
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.scorePage)
                            .stroke(theme.line, lineWidth: 1)
                    )
                Spacer()
            }
        }
    }

    private func extractMetadata() {
        guard let doc = PDFDocument(url: pdfURL) else { return }
        pageCount = doc.pageCount

        if let attrs = doc.documentAttributes {
            if let pdfTitle = attrs[PDFDocumentAttribute.titleAttribute] as? String,
               !pdfTitle.isEmpty {
                title = pdfTitle
            }
            if let pdfAuthor = attrs[PDFDocumentAttribute.authorAttribute] as? String,
               !pdfAuthor.isEmpty {
                composer = pdfAuthor
            }
        }

        // Engraved parts rarely carry PDF attributes; the cover page usually
        // carries everything. First plausible line is the title, and the
        // composer is typically the line that reads as a name.
        if title.isEmpty || composer.isEmpty,
           let firstPageText = doc.page(at: 0)?.string {
            let lines = firstPageText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.count >= 3 && $0.count <= 70 }
            if title.isEmpty, let candidate = lines.first {
                title = candidate
            }
            if composer.isEmpty {
                // A name-shaped line: two to four capitalised words, no
                // digits. "Johann Sebastian Bach", "F. Schubert".
                composer = lines.dropFirst().first { line in
                    let words = line.split(separator: " ")
                    guard (2...4).contains(words.count),
                          line.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
                    return words.allSatisfy { $0.first?.isUppercase == true }
                } ?? ""
            }
        }

        // About three minutes of music to an engraved page — the seed
        // repertoire's own ratio. A guess to correct, not a fact.
        estimatedMinutes = String(max(pageCount * 3, 1))
    }

    private func save() {
        let work = Work(
            composer: composer,
            title: title,
            catalogueNumber: catalogueNumber,
            edition: edition
        )

        work.estimatedMinutes = Int(estimatedMinutes.trimmingCharacters(in: .whitespaces))

        let part = Part(
            name: partName,
            pdfFileName: pdfURL.lastPathComponent,
            pageCount: pageCount
        )
        work.parts.append(part)

        modelContext.insert(work)
        try? modelContext.save()
        dismiss()
    }
}
