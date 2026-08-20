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
    }

    private func save() {
        let work = Work(
            composer: composer,
            title: title,
            catalogueNumber: catalogueNumber,
            edition: edition
        )

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
