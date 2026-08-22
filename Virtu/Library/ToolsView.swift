import SwiftUI
import SwiftData

/// The Tools destination. Today it holds one tool: the Recycle Bin. A deleted
/// work lands here rather than vanishing — nothing on disk is touched until
/// the musician empties it, explicitly, from this screen.
struct ToolsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Work> { $0.deletedAt != nil })
    private var binnedRaw: [Work]
    /// Most recently binned first. Sorted here because SortDescriptor does
    /// not take an optional Date key path.
    private var binned: [Work] {
        binnedRaw.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }
    @Query private var programs: [Program]

    @State private var confirmEmpty = false
    @State private var confirmDeleteOne: Work?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Tools")
                    .font(VFont.eyebrow)
                    .foregroundStyle(theme.accent)
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .padding(.bottom, 9)

                Text("Recycle Bin")
                    .font(VFont.screenTitle)
                    .foregroundStyle(theme.ink)
                    .tracking(-0.6)
                    .padding(.bottom, 6)

                Text(binned.isEmpty
                    ? "Deleted works wait here until you empty the bin."
                    : "Restoring puts a work back on the shelf. Deleting here is forever — the PDF, every marking, and every clipping go with it.")
                    .font(VFont.body)
                    .foregroundStyle(theme.muted)
                    .padding(.bottom, 28)

                if binned.isEmpty {
                    emptyState
                } else {
                    binList

                    Button(role: .destructive) {
                        confirmEmpty = true
                    } label: {
                        Label("Empty bin", systemImage: "trash")
                            .font(VFont.control)
                            .foregroundStyle(Color(hex: 0xC0392B))
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                }
            }
            .padding(Tokens.screenPadding)
        }
        .confirmationDialog(
            "Permanently delete everything in the bin? This cannot be undone.",
            isPresented: $confirmEmpty, titleVisibility: .visible
        ) {
            Button("Delete \(binned.count) work\(binned.count == 1 ? "" : "s") forever",
                   role: .destructive) {
                binned.forEach(destroy)
            }
        }
        .confirmationDialog(
            "Permanently delete \u{201C}\(confirmDeleteOne?.title ?? "")\u{201D}? This cannot be undone.",
            isPresented: Binding(
                get: { confirmDeleteOne != nil },
                set: { if !$0 { confirmDeleteOne = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete forever", role: .destructive) {
                if let work = confirmDeleteOne { destroy(work) }
                confirmDeleteOne = nil
            }
        }
    }

    private var binList: some View {
        VStack(spacing: 0) {
            ForEach(binned) { work in
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(work.title)
                            .font(VFont.workTitle)
                            .foregroundStyle(theme.ink)
                        Text("\(work.composer)\(work.deletedAt.map { " \u{00B7} deleted \($0.relativeDescription)" } ?? "")")
                            .font(VFont.metadata)
                            .foregroundStyle(theme.muted)
                    }

                    Spacer()

                    Button("Restore") { restore(work) }
                        .font(VFont.control)
                        .foregroundStyle(theme.ink)
                        .buttonStyle(.plain)

                    Button {
                        confirmDeleteOne = work
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: 0xC0392B))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete forever")
                }
                .padding(.vertical, 13)

                Rectangle()
                    .fill(theme.line)
                    .frame(height: 1)
            }
        }
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 28))
                    .foregroundStyle(theme.faint)
                Text("The bin is empty.")
                    .font(VFont.body)
                    .foregroundStyle(theme.faint)
            }
            .padding(.vertical, 48)
            Spacer()
        }
    }

    private func restore(_ work: Work) {
        work.deletedAt = nil
        try? modelContext.save()
    }

    /// The point of no return: PDF, stroke journal (Right Pages included),
    /// clippings, programme references, then the model itself.
    private func destroy(_ work: Work) {
        for part in work.parts {
            StrokeJournal.shared.deleteAll(partID: part.id, pageCount: part.pageCount)
            ClippingStore.shared.deleteAll(partID: part.id)
            try? FileManager.default.removeItem(at: part.pdfURL)
        }
        // Deleting the Work nullifies ProgramItem.work; a programme entry
        // pointing at nothing is noise, so take the items with it.
        for program in programs {
            for item in program.items where item.work?.id == work.id {
                modelContext.delete(item)
            }
        }
        modelContext.delete(work)
        try? modelContext.save()
    }
}
