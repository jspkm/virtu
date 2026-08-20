import SwiftUI
import SwiftData

/// Create or edit a set (a concert program): name it, date it, and put works
/// in playing order with their durations. Pass nil to create a new set.
struct ProgramEditorSheet: View {
    let program: Program?

    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Work.lastOpenedAt, order: .reverse) private var allWorks: [Work]

    private struct Entry: Identifiable {
        let id = UUID()
        var work: Work
        var minutes: Int
    }

    @State private var name = ""
    @State private var venue = ""
    @State private var scheduled = false
    @State private var date = ProgramEditorSheet.defaultDate
    @State private var entries: [Entry] = []
    @State private var confirmDelete = false

    private static var defaultDate: Date {
        let base = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
        return Calendar.current.date(bySettingHour: 19, minute: 30, second: 0, of: base) ?? base
    }

    private var availableWorks: [Work] {
        let used = Set(entries.map { $0.work.id })
        return allWorks.filter { !used.contains($0.id) }
    }

    private var totalMinutes: Int {
        entries.reduce(0) { $0 + $1.minutes }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Wigmore recital, Warm-ups)", text: $name)
                    TextField("Venue", text: $venue)
                    Toggle("Scheduled performance", isOn: $scheduled.animation())
                    if scheduled {
                        DatePicker("Date", selection: $date)
                    }
                } header: {
                    Text("Set")
                } footer: {
                    Text(scheduled
                        ? "Dated sets appear in the Next performance panel."
                        : "Without a date this is simply a collection \u{2014} warm-ups, audition excerpts, teaching material.")
                }

                Section {
                    if entries.isEmpty {
                        Text("No works yet — add them below in playing order.")
                            .foregroundStyle(theme.muted)
                    }
                    ForEach($entries) { $entry in
                        HStack(spacing: 12) {
                            Text(entryIndex($entry.wrappedValue).romanNumeral)
                                .font(VFont.catalogueNumber)
                                .foregroundStyle(theme.faint)
                                .frame(width: 28, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text($entry.wrappedValue.work.shortTitle)
                                Text($entry.wrappedValue.work.composer)
                                    .font(VFont.metadata)
                                    .foregroundStyle(theme.muted)
                            }

                            Spacer()

                            TextField("min", value: $entry.minutes, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 44)
                            Text("min")
                                .font(VFont.metadata)
                                .foregroundStyle(theme.muted)
                        }
                    }
                    .onMove { from, to in
                        entries.move(fromOffsets: from, toOffset: to)
                    }
                    .onDelete { offsets in
                        entries.remove(atOffsets: offsets)
                    }

                    if !availableWorks.isEmpty {
                        Menu {
                            ForEach(availableWorks) { work in
                                Button("\(work.composer) \u{2014} \(work.shortTitle)") {
                                    entries.append(Entry(work: work, minutes: 20))
                                }
                            }
                        } label: {
                            Label("Add work", systemImage: "plus")
                        }
                    }
                } header: {
                    HStack {
                        Text("Programme")
                        Spacer()
                        if entries.count > 1 {
                            EditButton()
                                .font(VFont.metadata)
                        }
                    }
                } footer: {
                    if totalMinutes > 0 {
                        Text("\(totalMinutes) minutes of music.")
                    }
                }

                if program != nil {
                    Section {
                        Button("Delete set", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .navigationTitle(program == nil ? "New set" : "Edit set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(program == nil ? "Create set" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || entries.isEmpty)
                }
            }
            .confirmationDialog(
                "Delete this set? The works stay in your library.",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete set", role: .destructive) {
                    if let program {
                        modelContext.delete(program)
                        try? modelContext.save()
                    }
                    dismiss()
                }
            }
        }
        .onAppear(perform: load)
    }

    private func entryIndex(_ entry: Entry) -> Int {
        entries.firstIndex { $0.id == entry.id } ?? 0
    }

    private func load() {
        guard let program else { return }
        name = program.name
        venue = program.venue
        if let existing = program.date {
            scheduled = true
            date = existing
        }
        entries = program.sortedItems.compactMap { item in
            item.work.map { Entry(work: $0, minutes: item.durationMinutes) }
        }
    }

    private func save() {
        let target: Program
        if let program {
            target = program
            target.name = name
            target.venue = venue
            target.date = scheduled ? date : nil
            for item in target.items {
                modelContext.delete(item)
            }
            target.items.removeAll()
        } else {
            target = Program(name: name, venue: venue, date: scheduled ? date : nil)
            modelContext.insert(target)
        }

        for (idx, entry) in entries.enumerated() {
            let item = ProgramItem(index: idx, durationMinutes: entry.minutes, work: entry.work)
            item.program = target
            modelContext.insert(item)
        }

        try? modelContext.save()
        dismiss()
    }
}
