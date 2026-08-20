import SwiftUI
import PencilKit

@Observable
final class AppState {

    enum Destination: String, CaseIterable {
        case library, score, find, tools
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
            case .dotted: .monoline
            case .fineDotted: .crayon
            }
        }

        var label: String {
            switch self {
            case .solid: "Solid"
            case .calligraphic: "Calligraphic"
            case .dotted: "Dotted"
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
    var destination: Destination = .library
    var currentWork: Work?
    var currentPart: Part?
    var librarySort: LibrarySort = .recent
    /// While reading, the nav rail collapses to a ghost sliver; this expands
    /// it temporarily as an overlay.
    var railExpanded: Bool = false

    // Program (set) reading: when non-nil, page turns flow across pieces.
    var currentProgram: Program?
    private var programParts: [Part] = []

    // Reading. `pageIndex` is the first visible page (0-based). `pagesPerView`
    // is 1 in portrait, 2 in landscape — set by the reading view from geometry.
    var pageIndex: Int = 0
    var pagesPerView: Int = 2
    var chromeVisible: Bool = true

    // Mode
    var readingMode: ReadingMode = .perform
    var annotating: Bool { readingMode == .study }

    // Annotation. Each ink tool remembers its own color; swatches recolor the
    // active tool. The pencil defaults to near-ink graphite — legibility on
    // engraving beats subtlety (a musician's HB, not a whisper).
    var tool: AnnotationTool = .pencil {
        didSet { persistToolSettings() }
    }
    var toolColors: [AnnotationTool: UInt32] = [
        .pencil: AppState.graphiteHex,
        .highlighter: 0xE8A33D,
    ] {
        didSet { persistToolSettings() }
    }

    /// Which of the four nibs is selected. Index 1 is the long-standing
    /// default and stays exactly where it was.
    var nibIndex: Int = 1 {
        didSet { persistToolSettings() }
    }

    /// The four nib widths offered in the flyout, for a given line style.
    ///
    /// Not a fixed ladder: PencilKit clamps a width outside its ink type's
    /// valid range *silently*, so a hard-coded 1.5pt "thinner" nib draws an
    /// identical mark to the 3pt default and nothing anywhere says so. The
    /// thin end is therefore whatever that style can actually reach, and the
    /// rest are forced strictly upward from it.
    static func nibWidths(for style: StrokeStyle) -> [CGFloat] {
        let range = style.inkType.validWidthRange
        let low = range.lowerBound, high = range.upperBound
        let widths = [low, 3.0, 5.0, 8.0].map { min(max($0, low), high) }

        // Some ink types have a narrow range (dotted tops out around 4pt), so
        // the preferred ladder collapses into duplicates. Where it does, spread
        // the four evenly across whatever room the ink actually has: four nibs
        // that differ is worth more than a 3pt default that cannot.
        let distinct = zip(widths, widths.dropFirst()).allSatisfy { $1 > $0 }
        guard !distinct else { return widths }
        return (0..<4).map { low + (high - low) * CGFloat($0) / 3 }
    }

    var nibWidths: [CGFloat] { AppState.nibWidths(for: strokeStyle) }

    /// The width the pencil will actually draw at — the flyout previews this
    /// value, never the one that was asked for.
    var pencilWidth: CGFloat {
        let widths = nibWidths
        return widths[min(max(nibIndex, 0), widths.count - 1)]
    }
    var strokeStyle: StrokeStyle = .solid {
        didSet { persistToolSettings() }
    }

    static let graphiteHex: UInt32 = 0x26221E
    static let stageGraphiteHex: UInt32 = 0xDAD4C8

    // Stage mode (dark theme), orthogonal to reading mode.
    var stageMode: Bool = false
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
        let colors = Dictionary(uniqueKeysWithValues: toolColors.map { ($0.key.rawValue, $0.value) })
        defaults.set(colors, forKey: "toolColors")
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
        if let stored = defaults.dictionary(forKey: "toolColors") as? [String: UInt32] {
            for (key, hex) in stored {
                if let toolKey = AnnotationTool(rawValue: key) { toolColors[toolKey] = hex }
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

    var layerCount: Int { currentPart?.layerCount ?? 1 }

    var activeLayer: Int { currentPart?.activeLayerIndex ?? AnnotationLayers.first }

    var visibleLayers: [Int] { currentPart?.visibleLayerIndices ?? [AnnotationLayers.first] }

    func isLayerVisible(_ index: Int) -> Bool {
        currentPart?.isLayerVisible(index) ?? true
    }

    /// Make a layer active. A hidden layer cannot be the active one — marking
    /// into ink you cannot see is never what anyone meant.
    func activateLayer(_ index: Int) {
        guard let part = currentPart, (1...part.layerCount).contains(index) else { return }
        part.activeLayerIndex = index
        part.hiddenLayerIndices.removeAll { $0 == index }
        layerRevision += 1
    }

    func toggleLayerVisibility(_ index: Int) {
        guard let part = currentPart, (1...part.layerCount).contains(index) else { return }
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

    @discardableResult
    func addLayer() -> Int? {
        guard let part = currentPart, part.layerCount < AnnotationLayers.max else { return nil }
        part.layerCount += 1
        part.activeLayerIndex = part.layerCount
        layerRevision += 1
        return part.layerCount
    }

    var canAddLayer: Bool { layerCount < AnnotationLayers.max }

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
        let parts = program.sortedItems.compactMap { $0.work?.parts.first }
        guard let first = parts.first else { return }
        currentProgram = program
        programParts = parts
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
        // Study starts with chrome up; Perform starts clean.
        chromeVisible = annotating
    }

    // MARK: - PencilKit tool construction

    /// The current tool as a PKTool. The pencil is deliberately dark and
    /// substantial: near-ink graphite at 95%, 3pt by default — legible from a
    /// music stand. Width and line style come from the flyout.
    func currentPKTool() -> PKTool {
        switch tool {
        case .eraser:
            return PKEraserTool(.vector)
        case .lasso:
            return PKLassoTool()
        case .pencil:
            return PKInkingTool(strokeStyle.inkType, color: inkColor(alpha: 0.95), width: pencilWidth)
        case .highlighter:
            return PKInkingTool(.marker, color: inkColor(alpha: stageMode ? 0.20 : 0.28), width: 14)
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
