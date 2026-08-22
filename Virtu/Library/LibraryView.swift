import SwiftUI
import SwiftData

/// The shelf. Not a file browser — a musician's music cabinet: it knows whose
/// it is, what's in study, and what's coming up on stage.
struct LibraryView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    // Binned works are the Recycle Bin's business (under Tools), not the
    // shelf's.
    @Query(filter: #Predicate<Work> { $0.deletedAt == nil },
           sort: \Work.lastOpenedAt, order: .reverse) private var works: [Work]
    @Query private var programs: [Program]

    @State private var showImporter = false
    @State private var importedPDFURL: URL?
    @State private var showRename = false
    @State private var renameDraft = ""
    /// Identity-carrying route so the sheet content is rebuilt per invocation
    /// (a plain isPresented sheet can capture a stale target).
    private struct SetEditorRoute: Identifiable {
        let id = UUID()
        let program: Program?
    }
    @State private var setEditorRoute: SetEditorRoute?
    @State private var workEditorRoute: Work?

    private let columns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20),
    ]

    /// Dated sets by date, then undated collections by creation order.
    private var orderedPrograms: [Program] {
        programs.sorted { a, b in
            switch (a.date, b.date) {
            case let (x?, y?): x < y
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): a.createdAt < b.createdAt
            }
        }
    }

    private var nextProgram: Program? {
        orderedPrograms.first { ($0.date ?? .distantPast) >= .now }
    }

    private var upcomingCount: Int {
        let horizon = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
        return programs.filter {
            guard let date = $0.date else { return false }
            return date >= .now && date <= horizon
        }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                if let program = nextProgram {
                    NextPerformancePanel(program: program) {
                        setEditorRoute = SetEditorRoute(program: program)
                    }
                    .contextMenu {
                        Button {
                            setEditorRoute = SetEditorRoute(program: program)
                        } label: {
                            Label("Edit set", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            deleteSet(program)
                        } label: {
                            Label("Delete set", systemImage: "trash")
                        }
                    }
                    .padding(.bottom, 36)
                }

                allWorksSection
            }
            .padding(Tokens.screenPadding)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .sheet(item: $importedPDFURL) { url in
            ImportMetadataSheet(pdfURL: url)
        }
        .sheet(item: $setEditorRoute) { route in
            ProgramEditorSheet(program: route.program)
        }
        .sheet(item: $workEditorRoute) { work in
            WorkInfoSheet(work: work)
        }
        .alert("Whose shelf is this?", isPresented: $showRename) {
            TextField("Your name", text: $renameDraft)
            Button("Save") { state.shelfName = renameDraft.trimmingCharacters(in: .whitespaces) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your name personalises the library and appears nowhere else.")
        }
        .onChange(of: state.shelfRenameRequested) { _, requested in
            guard requested else { return }
            state.shelfRenameRequested = false
            renameDraft = state.shelfName
            showRename = true
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("Repertoire")
                    .font(VFont.eyebrow)
                    .foregroundStyle(theme.accent)
                    .textCase(.uppercase)
                    .tracking(1.5)

                Spacer()

                sortChips
            }

            Button {
                renameDraft = state.shelfName
                showRename = true
            } label: {
                Text(state.shelfTitle)
                    .font(VFont.screenTitle)
                    .foregroundStyle(theme.ink)
                    .tracking(-0.6)
            }
            .buttonStyle(.plain)

            Text(subtitle)
                .font(VFont.body)
                .foregroundStyle(theme.muted)
        }
        .padding(.bottom, 28)
    }

    private var subtitle: String {
        var parts: [String] = []
        if !works.isEmpty {
            let n = works.count
            parts.append("\(n.spelledOut.capitalized) work\(n == 1 ? "" : "s") in study.")
        }
        if upcomingCount > 0 {
            let n = upcomingCount
            parts.append("\(n.spelledOut.capitalized) performance\(n == 1 ? "" : "s") scheduled this month.")
        }
        return parts.joined(separator: " ")
    }

    private var sortChips: some View {
        HStack(spacing: 8) {
            ForEach(AppState.LibrarySort.allCases, id: \.self) { sort in
                let active = state.librarySort == sort
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { state.librarySort = sort }
                } label: {
                    Text(sort.label)
                        .font(VFont.control)
                        .foregroundStyle(active ? theme.paper : theme.muted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(active ? AnyShapeStyle(theme.ink) : AnyShapeStyle(Color.clear))
                        .overlay(Capsule().stroke(active ? Color.clear : theme.line2, lineWidth: 1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - All works

    @ViewBuilder
    private var allWorksSection: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("All works")
                .font(VFont.sectionHeading)
                .foregroundStyle(theme.ink)
            Rectangle()
                .fill(theme.line)
                .frame(height: 1)
            Text("\(works.count)")
                .font(VFont.catalogueNumber)
                .foregroundStyle(theme.faint)
            Button {
                showImporter = true
            } label: {
                Label("Import", systemImage: "plus")
                    .font(VFont.control)
                    .foregroundStyle(theme.muted)
            }
            .buttonStyle(.plain)

            Button {
                setEditorRoute = SetEditorRoute(program: nil)
            } label: {
                Label("New set", systemImage: "music.note.list")
                    .font(VFont.control)
                    .foregroundStyle(theme.muted)
            }
            .buttonStyle(.plain)
            .disabled(works.isEmpty)
        }
        .padding(.bottom, 16)

        if works.isEmpty {
            emptyState
        } else {
            switch state.librarySort {
            case .recent:
                workGrid(works)
            case .composer:
                ForEach(composerGroups, id: \.0) { composer, group in
                    sectionHeader(composer)
                    workGrid(group)
                }
            case .programme:
                ForEach(orderedPrograms) { program in
                    let group = program.sortedItems.compactMap(\.work).filter { $0.deletedAt == nil }
                    if !group.isEmpty {
                        HStack(spacing: 10) {
                            sectionHeader(
                                program.date.map { "\(program.name) \u{00B7} \($0.shortPerformanceDate)" }
                                    ?? program.name
                            )
                            Button {
                                setEditorRoute = SetEditorRoute(program: program)
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.faint)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .contextMenu {
                            Button {
                                setEditorRoute = SetEditorRoute(program: program)
                            } label: {
                                Label("Edit set", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleteSet(program)
                            } label: {
                                Label("Delete set", systemImage: "trash")
                            }
                        }
                        workGrid(group)
                    }
                }
                let unprogrammed = unprogrammedWorks
                if !unprogrammed.isEmpty {
                    sectionHeader("In study")
                    workGrid(unprogrammed)
                }
            }
        }
    }

    private var composerGroups: [(String, [Work])] {
        Dictionary(grouping: works) { $0.composer }
            .sorted { $0.key.split(separator: " ").last ?? "" < $1.key.split(separator: " ").last ?? "" }
    }

    private var unprogrammedWorks: [Work] {
        let programmed = Set(programs.flatMap { $0.items.compactMap { $0.work?.id } })
        return works.filter { !programmed.contains($0.id) }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(VFont.metadata)
            .foregroundStyle(theme.muted)
            .textCase(.uppercase)
            .tracking(1.2)
            .padding(.top, 10)
            .padding(.bottom, 12)
    }

    private func workGrid(_ items: [Work]) -> some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(items) { work in
                WorkCardView(work: work)
                    .onTapGesture { state.openWork(work) }
                    .contextMenu {
                        Button {
                            workEditorRoute = work
                        } label: {
                            Label("Edit info", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            binWork(work)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .padding(.bottom, 8)
    }

    /// Soft: the work moves to the Recycle Bin under Tools. Its PDF, ink and
    /// clippings stay on disk until the bin is emptied.
    private func binWork(_ work: Work) {
        work.deletedAt = .now
        if state.currentWork?.id == work.id {
            state.currentWork = nil
            state.currentPart = nil
        }
        try? modelContext.save()
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)

            VStack(spacing: 8) {
                Text("Bring in your first piece")
                    .font(VFont.sectionHeading)
                    .foregroundStyle(theme.ink)
                Text("Import a PDF from Files, forScore, or anywhere else.")
                    .font(VFont.body)
                    .foregroundStyle(theme.muted)
            }

            Button(action: { showImporter = true }) {
                Text("Choose file")
                    .font(VFont.control)
                    .foregroundStyle(theme.paper)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.button))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Deletes only the grouping. The works it pointed at stay on the shelf.
    private func deleteSet(_ program: Program) {
        if state.currentProgram?.id == program.id {
            state.currentProgram = nil
        }
        modelContext.delete(program)
        try? modelContext.save()
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let filename = "\(UUID().uuidString).pdf"
        let destination = Part.storageDirectory.appendingPathComponent(filename)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            importedPDFURL = destination
        } catch {
            print("Import failed: \(error)")
        }
    }
}

// MARK: - Next performance

/// The concert on the horizon, right at the top of the shelf: the programme in
/// order, and one button that opens the whole set for gig-day reading.
private struct NextPerformancePanel: View {
    let program: Program
    let onEdit: () -> Void
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    private var playableItems: [(Int, ProgramItem, Work)] {
        program.sortedItems.enumerated().compactMap { idx, item in
            item.work.map { (idx, item, $0) }
        }
    }

    var body: some View {
        // Two rows, so the programme never squeezes the score titles: what
        // and when on top, the scores below in a carousel that scrolls when
        // the shelf is narrower than the set.
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Next performance")
                        .font(VFont.eyebrow)
                        .foregroundStyle(theme.accent)
                        .textCase(.uppercase)
                        .tracking(1.5)
                    HStack(spacing: 9) {
                        Text(program.name)
                            .font(VFont.sectionHeading)
                            .foregroundStyle(theme.ink)
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 13))
                                .foregroundStyle(theme.faint)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit set")
                    }
                    if let date = program.date {
                        Text(date.performanceDateTime)
                            .font(VFont.catalogueNumber)
                            .foregroundStyle(theme.muted)
                    }
                }

                Spacer(minLength: 16)

                Button {
                    state.openProgram(program)
                } label: {
                    VStack(spacing: 4) {
                        Text("Open set")
                            .font(VFont.control)
                        Text("\(program.totalMinutes) min")
                            .font(VFont.metadata)
                            .opacity(0.7)
                        Text("\(playableItems.count) score\(playableItems.count == 1 ? "" : "s")")
                            .font(VFont.metadata)
                            .opacity(0.7)
                    }
                    .foregroundStyle(theme.paper)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .background(theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card - 4))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(playableItems, id: \.1.id) { idx, item, work in
                        Button {
                            state.openWork(work)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(idx.romanNumeral)
                                    .font(VFont.catalogueNumber)
                                    .foregroundStyle(theme.faint)
                                Text(work.shortTitle)
                                    .font(VFont.workTitle)
                                    .foregroundStyle(theme.ink)
                                    .lineLimit(1)
                                Text("\(work.composer.split(separator: " ").last.map(String.init) ?? work.composer) \u{00B7} \(item.durationMinutes) min")
                                    .font(VFont.metadata)
                                    .foregroundStyle(theme.muted)
                            }
                            .padding(14)
                            // Wide enough that a title reads; never squeezed —
                            // the carousel absorbs the overflow instead.
                            .frame(minWidth: 180, alignment: .leading)
                            .background(theme.plate)
                            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card - 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: Tokens.Radius.card - 4)
                                    .stroke(theme.line, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .background(theme.wash)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .stroke(theme.line, lineWidth: 1)
        )
    }
}

// MARK: - Helpers

extension Int {
    var spelledOut: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

extension Date {
    /// "14 SEP · 19:30"
    var performanceDateTime: String {
        let day = DateFormatter()
        day.dateFormat = "d MMM"
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        return "\(day.string(from: self).uppercased()) \u{00B7} \(time.string(from: self))"
    }

    /// "14 Sep"
    var shortPerformanceDate: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: self)
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
