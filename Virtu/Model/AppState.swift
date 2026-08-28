import SwiftUI
import SwiftData
import PencilKit

@Observable
final class AppState {

    /// Declaration order IS the nav rail's order.
    /// Tools sits immediately after Search; the Recycle Bin is its own
    /// destination below it, no longer riding inside Tools.
    enum Destination: String, CaseIterable {
        case library, score, tools, bin
    }

    /// The two explicit reading modes, separated by a hard wall.
    /// Perform: the page and nothing else — pencil inert, no tool UI, no chrome
    /// on center tap, no haptics, no animations beyond the page-turn crossfade.
    /// Study: the full annotation surface.
    /// Stage (dark theme) is orthogonal to this mode.
    enum ReadingMode: String {
        case perform, study
    }

    /// One pencil, recolored by swatches — not a drawer of near-identical
    /// pens. Highlighter for phrases, lasso to move, eraser to remove.
    enum AnnotationTool: String, CaseIterable {
        case pencil, highlighter, lasso, eraser
    }

    /// The four line styles offered in the pencil flyout.
    ///
    /// Each rides inside `PKStroke` as its ink type — there is nowhere else in
    /// a `PKDrawing` to record style, and a parallel store index-aligned to
    /// strokes would not survive lasso and erase. The last two are *carriers*
    /// only: `InkRenderer` is the sole rasterizer for display and export, so
    /// what a dotted stroke actually looks like is entirely ours.
    enum StrokeStyle: String, CaseIterable {
        case solid, calligraphic, dotted, fineDotted

        var inkType: PKInkingTool.InkType {
            switch self {
            case .solid: .pencil
            case .calligraphic: .fountainPen
            // Carriers are chosen for the width range they allow, measured
            // rather than assumed: .monoline stops at 4pt and .crayon STARTS
            // at 10pt, so using them for the two dotted styles capped the nib
            // ladder and made "fine" the fattest option of the four. .pen is
            // wide (0.9-25.7) and otherwise unused; .monoline's low ceiling
            // is exactly right for the finest style.
            case .dotted: .pen
            case .fineDotted: .monoline
            }
        }

        var label: String {
            switch self {
            case .solid: "Solid"
            case .calligraphic: "Calligraphic"
            // The case keeps its stored name; what it draws is dashes.
            case .dotted: "Dashed"
            case .fineDotted: "Fine dotted"
            }
        }
    }

    enum LibrarySort: String, CaseIterable {
        case recent, composer, programme

        var label: String {
            switch self {
            case .recent: "Recently played"
            case .composer: "By composer"
            case .programme: "By programme"
            }
        }
    }

    // Identity — the shelf belongs to someone.
    var shelfName: String {
        didSet { defaults.set(shelfName, forKey: "shelfName") }
    }
    var shelfRenameRequested = false

    var shelfTitle: String {
        shelfName.isEmpty ? "Your shelf" : "\(shelfName)\u{2019}s shelf"
    }

    var shelfInitials: String? {
        let parts = shelfName.split(separator: " ").prefix(2).compactMap { $0.first }
        guard !parts.isEmpty else { return nil }
        return parts.map(String.init).joined().uppercased()
    }

    // Navigation
    var destination: Destination = .library {
        didSet { persistSession() }
    }
    var currentWork: Work?
    var currentPart: Part? {
        didSet { persistSession() }
    }
    var librarySort: LibrarySort = .recent
    /// While reading, the nav rail collapses to a ghost sliver; this expands
    /// it temporarily as an overlay.
    var railExpanded: Bool = false

    // Program (set) reading: when non-nil, page turns flow across pieces.
    var currentProgram: Program?
    private var programParts: [Part] = []

    // Reading. `pageIndex` is the first visible page (0-based). `pagesPerView`
    // is 1 in portrait, 2 in landscape — set by the reading view from geometry.
    var pageIndex: Int = 0 {
        didSet { persistSession() }
    }
    var pagesPerView: Int = 2 {
        didSet { persistSession() }
    }
    var chromeVisible: Bool = true

    // Mode
    var readingMode: ReadingMode = .perform {
        didSet { persistSession() }
    }
    var annotating: Bool { readingMode == .study }

    // Annotation. Each ink tool remembers its own color; swatches recolor the
    // active tool. The pencil defaults to near-ink graphite — legibility on
    // engraving beats subtlety (a musician's HB, not a whisper).
    var tool: AnnotationTool = .pencil {
        didSet { persistToolSettings() }
    }

    /// What the pencil's barrel double-tap hands back. Two taps put the
    /// eraser in your hand; two more return whatever you were holding —
    /// forScore's behaviour, and what Apple's own "Switch to Eraser"
    /// preference describes. Not persisted: a launch that finds the eraser
    /// held gives the pencil back, which is the right guess.
    private var toolBeforeEraser: AnnotationTool = .pencil

    /// Study only. In Perform the pencil is inert, and a barrel tap that
    /// silently rearmed a tool nobody can see is worse than nothing.
    func togglePencilEraser() {
        guard annotating else { return }
        if tool == .eraser {
            tool = toolBeforeEraser
        } else {
            toolBeforeEraser = tool
            tool = .eraser
        }
    }
    var toolColors: [AnnotationTool: UInt32] = [
        .pencil: AppState.graphiteHex,
        .highlighter: AppState.highlighterYellowHex,
    ] {
        didSet { persistToolSettings() }
    }

    // MARK: - Ink palettes
    //
    // Three swatches per ink tool, and the pencil's three are not the
    // highlighter's three: a highlighter wants washes, a pencil wants ink.
    //
    // The first slot of each is FIXED. It is the colour the tool is for —
    // graphite for the pencil, yellow for the highlighter — and a musician who
    // never touches the other two should never be able to lose it. The other
    // two are the musician's own, changed by holding the swatch, and they
    // persist.

    /// Slot 0 of every palette, and the only slot that cannot be re-coloured.
    static let fixedSlot = 0

    static let highlighterYellowHex: UInt32 = 0xE8A33D

    static let defaultPalettes: [AnnotationTool: [UInt32]] = [
        //                fixed                red      ink blue
        .pencil: [AppState.graphiteHex, 0xC0392B, 0x2563C7],
        //                fixed yellow    bright green  faint sky
        .highlighter: [AppState.highlighterYellowHex, 0x7FBF3F, 0x5FB8DE],
    ]

    var toolPalettes: [AnnotationTool: [UInt32]] = AppState.defaultPalettes {
        didSet { persistToolSettings() }
    }

    /// The swatches to offer for a tool. Lasso and eraser carry no colour of
    /// their own, so they show the pencil's row rather than making the rail
    /// change height when you pick them up.
    func palette(for tool: AnnotationTool) -> [UInt32] {
        toolPalettes[tool] ?? toolPalettes[.pencil] ?? AppState.defaultPalettes[.pencil]!
    }

    /// Re-colour one slot. Slot 0 is the tool's own colour and refuses.
    func setPaletteSlot(_ index: Int, to hex: UInt32, for tool: AnnotationTool) {
        guard index != AppState.fixedSlot,
              var slots = toolPalettes[tool], slots.indices.contains(index) else { return }
        let wasActive = toolColors[tool] == slots[index]
        slots[index] = hex
        toolPalettes[tool] = slots
        // Re-colouring the swatch you are drawing with changes the ink in your
        // hand too. Anything else means picking the colour then picking it
        // again to use it.
        if wasActive { toolColors[tool] = hex }
    }

    /// Which of the four nibs is selected. Index 1 is the long-standing
    /// default and stays exactly where it was.
    var nibIndex: Int = 1 {
        didSet { persistToolSettings() }
    }

    /// How the eraser takes ink off the page.
    /// `area` rubs out only what the tip actually touches — a real eraser —
    /// and is the default. `stroke` removes the whole marking on contact,
    /// which was the old behaviour and is now the option.
    enum EraserMode: String, CaseIterable {
        case area, stroke
    }
    var eraserMode: EraserMode = .area {
        didSet { persistToolSettings() }
    }
    /// The rubbing tip. Asked for at ~5 points — a real eraser's precision —
    /// but PencilKit clamps a bitmap eraser to its own floor (16.4pt,
    /// measured), and normalizes the type to `.fixedWidthBitmap`. So this is
    /// the smallest tip the platform will give us; the constant records what
    /// we ask for, the test records what we get.
    static let areaEraserWidth: CGFloat = 5

    /// The four highlighter heights. Index 0 is the original 14pt wash;
    /// the default is one step up — a phrase-wide band, not a text underline.
    static let highlighterWidths: [CGFloat] = [14, 28, 42, 56]
    var highlighterWidthIndex: Int = 1 {
        didSet { persistToolSettings() }
    }
    var highlighterWidth: CGFloat {
        AppState.highlighterWidths[
            min(max(highlighterWidthIndex, 0), AppState.highlighterWidths.count - 1)]
    }

    /// What the lasso does with what it catches.
    /// `move` is PencilKit's own selection-and-drag, unchanged. `copy` clips a
    /// region — ink AND engraving — into a floating snapshot the musician can
    /// drop anywhere, the Right Page included.
    enum LassoMode: String, CaseIterable {
        case move, copy
    }
    var lassoMode: LassoMode = .move {
        didSet { persistToolSettings() }
    }

    /// The four nibs. Fixed, and deliberately not per-style: deriving the
    /// ladder from each ink type's own range made the thickness shift under
    /// you when you changed line style, which is not something a nib does.
    /// Where an ink type cannot reach a width, PencilKit clamps it — but the
    /// selection stays put and returns intact when the style changes back.
    static let nibWidths: [CGFloat] = [1.5, 3.0, 5.0, 8.0]

    /// The width the pencil will actually draw at — the flyout previews this
    /// value, never the one that was asked for.
    var pencilWidth: CGFloat {
        AppState.nibWidths[min(max(nibIndex, 0), AppState.nibWidths.count - 1)]
    }
    var strokeStyle: StrokeStyle = .solid {
        didSet { persistToolSettings() }
    }

    static let graphiteHex: UInt32 = 0x26221E
    static let stageGraphiteHex: UInt32 = 0xDAD4C8

    // Stage mode (dark theme), orthogonal to reading mode.
    var stageMode: Bool = false {
        didSet { persistSession() }
    }
    var stageBrightnessSuggested: Bool = false

    /// Injectable so tests get their own store: tool settings now persist,
    /// and a shared one lets a test that writes a colour silently decide what
    /// an unrelated test sees.
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shelfName = defaults.string(forKey: "shelfName") ?? ""
        restoreToolSettings()
    }

    // MARK: - Session restore
    //
    // Reported 2026-08-27: "it goes back to the first page after I leave the
    // app." Nothing about *where you were* was ever written down, so any
    // relaunch — a crash, or iPadOS reclaiming the app while you were in
    // three others — put you back on the shelf, and reopening put you on
    // page one. A music stand does not close the book when you look away.
    //
    // The snapshot is deliberately small and entirely re-derivable: if the
    // work has been binned or deleted since, restore simply declines and you
    // land on the shelf, which is the old behaviour.

    private struct SessionSnapshot: Codable {
        var destination: String
        var workID: UUID?
        var partID: UUID?
        var programID: UUID?
        var pageIndex: Int
        /// Restored so `goToPage`'s landscape parity lock does not re-clamp a
        /// portrait position: left on page 8 in portrait, a relaunch that
        /// assumed landscape would put you on page 7.
        var pagesPerView: Int
        var readingMode: String
        var stageMode: Bool
    }

    private static let sessionKey = "session"
    private var restoringSession = false
    private var didRestoreSession = false
    /// Held separately from `currentProgram` so the snapshot can be written
    /// without keeping a SwiftData object alive for the encoder.
    private var currentProgramID: UUID?

    private func persistSession() {
        guard !restoringSession else { return }
        let snapshot = SessionSnapshot(
            destination: destination.rawValue,
            workID: currentWork?.id,
            partID: currentPart?.id,
            programID: currentProgramID,
            pageIndex: pageIndex,
            pagesPerView: pagesPerView,
            readingMode: readingMode.rawValue,
            stageMode: stageMode
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.sessionKey)
    }

    /// Put the musician back where they were. Called once, at launch, after
    /// the store is up.
    func restoreSession(context: ModelContext) {
        guard !didRestoreSession else { return }
        didRestoreSession = true
        guard let data = defaults.data(forKey: Self.sessionKey),
              let snapshot = try? JSONDecoder().decode(SessionSnapshot.self, from: data)
        else { return }

        restoringSession = true
        defer {
            restoringSession = false
            persistSession()
        }

        // Stage is orthogonal to everything below and survives even a restore
        // that finds no score: coming back to a bright screen in a dark pit
        // is the same betrayal as coming back to page one.
        stageMode = snapshot.stageMode

        guard snapshot.destination == Destination.score.rawValue,
              let workID = snapshot.workID,
              let work = fetchWork(id: workID, context: context),
              work.deletedAt == nil
        else {
            destination = Destination(rawValue: snapshot.destination) ?? .library
            // A destination that needs a score but has none is just the shelf.
            if destination == .score { destination = .library }
            return
        }

        // A programme reopens as a programme, so page turns still run across
        // its pieces. A programme emptied since is downgraded to the work.
        if let programID = snapshot.programID,
           let program = fetchProgram(id: programID, context: context) {
            let parts = program.sortedItems
                .compactMap(\.work)
                .filter { $0.deletedAt == nil }
                .compactMap { $0.parts.first }
            if !parts.isEmpty {
                currentProgram = program
                currentProgramID = programID
                programParts = parts
            }
        }

        currentWork = work
        currentPart = work.parts.first { $0.id == snapshot.partID } ?? work.parts.first
        guard currentPart != nil else { return }

        readingMode = ReadingMode(rawValue: snapshot.readingMode) ?? .perform
        chromeVisible = false
        destination = .score
        // The reading view overwrites this from real geometry on its first
        // layout; until then the last launch's value is a better guess than
        // the default, and it decides how goToPage clamps.
        pagesPerView = max(1, min(snapshot.pagesPerView, 2))
        // Clamped through goToPage: the part may have been re-imported
        // shorter since.
        goToPage(snapshot.pageIndex)
    }

    // Fetched whole and filtered in Swift rather than by #Predicate.
    // `#Predicate { $0.id == id }` over these models traps inside SwiftData
    // (verified 2026-08-27 — EXC_BREAKPOINT, not a throw, so it cannot even
    // be caught): our `id` is a plain stored UUID living alongside
    // PersistentModel's own identity. A shelf is tens of works, and this runs
    // once per launch.
    private func fetchWork(id: UUID, context: ModelContext) -> Work? {
        let all = (try? context.fetch(FetchDescriptor<Work>())) ?? []
        return all.first { $0.id == id }
    }

    private func fetchProgram(id: UUID, context: ModelContext) -> Program? {
        let all = (try? context.fetch(FetchDescriptor<Program>())) ?? []
        return all.first { $0.id == id }
    }

    // MARK: - Tool persistence
    //
    // PRD 7.4: tool and colour selection persist across launches. Reaching for
    // a red pencil and finding graphite is a small betrayal, repeated daily.

    private var restoringTools = false

    private func persistToolSettings() {
        guard !restoringTools else { return }
        defaults.set(tool.rawValue, forKey: "tool")
        defaults.set(strokeStyle.rawValue, forKey: "strokeStyle")
        defaults.set(nibIndex, forKey: "nibIndex")
        defaults.set(eraserMode.rawValue, forKey: "eraserMode")
        defaults.set(highlighterWidthIndex, forKey: "highlighterWidthIndex")
        defaults.set(lassoMode.rawValue, forKey: "lassoMode")
        let colors = Dictionary(uniqueKeysWithValues: toolColors.map { ($0.key.rawValue, $0.value) })
        defaults.set(colors, forKey: "toolColors")
        let palettes = Dictionary(uniqueKeysWithValues: toolPalettes.map { ($0.key.rawValue, $0.value) })
        defaults.set(palettes, forKey: "toolPalettes")
    }

    private func restoreToolSettings() {
        restoringTools = true
        defer { restoringTools = false }
        if let raw = defaults.string(forKey: "tool"), let value = AnnotationTool(rawValue: raw) {
            tool = value
        }
        if let raw = defaults.string(forKey: "strokeStyle"), let value = StrokeStyle(rawValue: raw) {
            strokeStyle = value
        }
        if defaults.object(forKey: "nibIndex") != nil {
            nibIndex = defaults.integer(forKey: "nibIndex")
        }
        if let raw = defaults.string(forKey: "eraserMode"), let value = EraserMode(rawValue: raw) {
            eraserMode = value
        }
        if defaults.object(forKey: "highlighterWidthIndex") != nil {
            highlighterWidthIndex = defaults.integer(forKey: "highlighterWidthIndex")
        }
        if let raw = defaults.string(forKey: "lassoMode"), let value = LassoMode(rawValue: raw) {
            lassoMode = value
        }
        if let stored = defaults.dictionary(forKey: "toolColors") as? [String: UInt32] {
            for (key, hex) in stored {
                if let toolKey = AnnotationTool(rawValue: key) { toolColors[toolKey] = hex }
            }
        }
        if let stored = defaults.dictionary(forKey: "toolPalettes") as? [String: [UInt32]] {
            for (key, slots) in stored {
                guard let toolKey = AnnotationTool(rawValue: key),
                      let fresh = AppState.defaultPalettes[toolKey],
                      slots.count == fresh.count else { continue }
                // The fixed slot is restored from the defaults, never from the
                // store: a build that changes a tool's own colour must move it
                // for everyone, not just for a fresh install.
                var restored = slots
                restored[AppState.fixedSlot] = fresh[AppState.fixedSlot]
                toolPalettes[toolKey] = restored
            }
        }
    }

    // MARK: - Layers
    //
    // Layer state lives on the Part so a score reopens exactly as it was left.
    // `layerRevision` exists because the reading surface is UIKit: mutating a
    // SwiftData model does not reliably re-run the representable's update, and
    // ink that does not follow the layer you just chose is a bug you would
    // find at a rehearsal rather than a desk.
    var layerRevision: Int = 0

    /// Exactly three, for every part, always.
    var layerCount: Int { AnnotationLayers.max }

    /// Clamped: a part persisted under the old ten-layer cap can carry an
    /// activeLayerIndex the three-layer world cannot ink on — unclamped, the
    /// pencil goes silently dead.
    var activeLayer: Int {
        min(max(currentPart?.activeLayerIndex ?? AnnotationLayers.first,
                AnnotationLayers.first), AnnotationLayers.max)
    }

    var visibleLayers: [Int] { currentPart?.visibleLayerIndices ?? [AnnotationLayers.first] }

    func isLayerVisible(_ index: Int) -> Bool {
        currentPart?.isLayerVisible(index) ?? true
    }

    /// Make a layer active. A hidden layer cannot be the active one — marking
    /// into ink you cannot see is never what anyone meant.
    func activateLayer(_ index: Int) {
        guard let part = currentPart, (1...AnnotationLayers.max).contains(index) else { return }
        part.activeLayerIndex = index
        part.hiddenLayerIndices.removeAll { $0 == index }
        layerRevision += 1
    }

    func toggleLayerVisibility(_ index: Int) {
        guard let part = currentPart, (1...AnnotationLayers.max).contains(index) else { return }
        if part.isLayerVisible(index) {
            part.hiddenLayerIndices.append(index)
            // Hiding the layer you are marking on would leave the pencil
            // writing into the void; step down to the nearest visible one.
            if part.activeLayerIndex == index,
               let fallback = part.visibleLayerIndices.last {
                part.activeLayerIndex = fallback
            }
        } else {
            part.hiddenLayerIndices.removeAll { $0 == index }
        }
        layerRevision += 1
    }

    var theme: Theme {
        stageMode ? .stage : .light
    }

    var pageCount: Int {
        currentPart?.pageCount ?? 1
    }

    var visiblePageIndices: Range<Int> {
        pageIndex..<min(pageIndex + pagesPerView, pageCount)
    }

    /// Position of the current work within the open program, if any.
    var programPosition: (index: Int, count: Int)? {
        guard currentProgram != nil, !programParts.isEmpty,
              let idx = programParts.firstIndex(where: { $0.id == currentPart?.id })
        else { return nil }
        return (idx, programParts.count)
    }

    func openWork(_ work: Work) {
        currentProgram = nil
        programParts = []
        currentProgramID = nil
        currentWork = work
        currentPart = work.parts.first
        work.lastOpenedAt = Date()
        pageIndex = 0
        readingMode = .perform
        chromeVisible = false
        destination = .score
    }

    /// Gig-day flow: open the whole set. Page turns run across pieces — the
    /// last page of one work turns into the first page of the next.
    func openProgram(_ program: Program) {
        // Binned works are off the stand too: opening a set must not
        // resurrect something the musician deleted.
        let parts = program.sortedItems
            .compactMap(\.work)
            .filter { $0.deletedAt == nil }
            .compactMap { $0.parts.first }
        guard let first = parts.first else { return }
        currentProgram = program
        programParts = parts
        currentProgramID = program.id
        currentPart = first
        currentWork = first.work
        first.work?.lastOpenedAt = Date()
        pageIndex = 0
        readingMode = .perform
        chromeVisible = false
        destination = .score
    }

    func turn(_ direction: Int) {
        let target = pageIndex + direction * pagesPerView
        if target >= pageCount {
            advanceInProgram(1)
        } else if target < 0 {
            advanceInProgram(-1)
        } else {
            goToPage(target)
        }
    }

    private func advanceInProgram(_ direction: Int) {
        guard let idx = programParts.firstIndex(where: { $0.id == currentPart?.id }),
              programParts.indices.contains(idx + direction)
        else { return }

        let part = programParts[idx + direction]
        currentPart = part
        currentWork = part.work
        part.work?.lastOpenedAt = Date()
        if direction > 0 {
            pageIndex = 0
        } else {
            goToPage(part.pageCount - 1)
        }
        recordProgress()
    }

    func goToPage(_ index: Int) {
        var target = max(0, min(index, pageCount - 1))
        if pagesPerView == 2 {
            target -= target % 2
        }
        pageIndex = target
        recordProgress()
    }

    private func recordProgress() {
        guard let part = currentPart else { return }
        part.furthestPageIndex = max(part.furthestPageIndex, visiblePageIndices.upperBound - 1)
    }

    /// Called by the reading view when its geometry changes orientation.
    func setPagesPerView(_ count: Int) {
        guard count != pagesPerView else { return }
        pagesPerView = count
        goToPage(pageIndex)
    }

    func toggleChrome() {
        chromeVisible.toggle()
    }

    func toggleMode() {
        readingMode = annotating ? .perform : .study
        // Both modes start clean. The title is a visitor in Study as well —
        // summoned by touching the top of the score, gone again on its own.
        chromeVisible = false
    }

    // MARK: - PencilKit tool construction

    /// The current tool as a PKTool. The pencil is deliberately dark and
    /// substantial: near-ink graphite at 95%, 3pt by default — legible from a
    /// music stand. Width and line style come from the flyout.
    func currentPKTool() -> PKTool {
        switch tool {
        case .eraser:
            switch eraserMode {
            case .area: return PKEraserTool(.bitmap, width: AppState.areaEraserWidth)
            case .stroke: return PKEraserTool(.vector)
            }
        case .lasso:
            // Copy mode never reaches PencilKit — the reading surface runs its
            // own marquee when it is armed — but the canvas still holds a
            // lasso so nothing inks if a touch does slip through.
            return PKLassoTool()
        case .pencil:
            return PKInkingTool(strokeStyle.inkType, color: inkColor(alpha: 0.95), width: pencilWidth)
        case .highlighter:
            return PKInkingTool(.marker, color: inkColor(alpha: stageMode ? 0.20 : 0.28), width: highlighterWidth)
        }
    }

    private func inkColor(alpha: CGFloat) -> UIColor {
        var hex = toolColors[tool] ?? Self.graphiteHex
        // The default graphite flips to warm chalk in Stage, where dark ink
        // would vanish on the remapped page.
        if hex == Self.graphiteHex && stageMode {
            hex = Self.stageGraphiteHex
        }
        return UIColor(hex: hex).withAlphaComponent(alpha)
    }
}
