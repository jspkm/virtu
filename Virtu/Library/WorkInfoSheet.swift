import SwiftUI
import SwiftData

/// Edit a work's metadata after the fact — the same fields the import
/// confirmation offered, minus the file. Plain text fields, so the keyboard
/// (soft or hardware) does the editing.
struct WorkInfoSheet: View {
    let work: Work
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var composer = ""
    @State private var title = ""
    @State private var catalogueNumber = ""
    @State private var edition = ""
    @State private var partName = ""
    @State private var estimatedMinutes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Work") {
                    TextField("Composer", text: $composer)
                    TextField("Title", text: $title)
                    TextField("Catalogue number (e.g. BWV 1007)", text: $catalogueNumber)
                    TextField("Edition (e.g. Bärenreiter urtext)", text: $edition)
                }

                Section("Part") {
                    TextField("Part name (e.g. cello, piano)", text: $partName)
                    if let part = work.parts.first {
                        LabeledContent("Pages", value: "\(part.pageCount)")
                    }
                }

                Section {
                    TextField("Estimated minutes", text: $estimatedMinutes)
                        .keyboardType(.numberPad)
                } footer: {
                    Text("Programme entries start from this when the work is added to a set.")
                }
            }
            .navigationTitle("Edit info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(composer.isEmpty || title.isEmpty)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        composer = work.composer
        title = work.title
        catalogueNumber = work.catalogueNumber
        edition = work.edition
        partName = work.parts.first?.name ?? ""
        estimatedMinutes = work.estimatedMinutes.map(String.init) ?? ""
    }

    private func save() {
        work.composer = composer
        work.title = title
        work.catalogueNumber = catalogueNumber
        work.edition = edition
        if let part = work.parts.first, !partName.isEmpty {
            part.name = partName
        }
        work.estimatedMinutes = Int(estimatedMinutes.trimmingCharacters(in: .whitespaces))
        try? modelContext.save()
        dismiss()
    }
}
