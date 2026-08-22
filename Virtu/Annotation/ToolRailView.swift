import SwiftUI

/// Study mode's single tool surface: docked to the right edge so it never
/// drifts over the notation being marked. Always at full strength — a toolbar
/// that fades is one you have to wake before you can use it, and the moment
/// you reach for a pencil is never the moment to be kept waiting.
/// Replaces both the M1 floating rail and the system PKToolPicker.
struct ToolRailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    /// The one options panel that can be out at a time. Every tool option in
    /// the app arrives the same way: long-press (or re-tap) a rail item, and
    /// its panel slides out attached to the rail's left edge. No sheets.
    @State private var activePanel: Panel?

    enum Panel: Equatable {
        case pencil
        case highlighter
        case eraser
        case lasso
        case color(slot: Int, tool: AppState.AnnotationTool)
    }

    /// The tool whose palette the swatch row shows and edits. Eraser and
    /// lasso carry no colour, so with either armed the row stands in for the
    /// pencil — and editing it edits the PENCIL's palette, never a palette
    /// that does not exist. (That non-existent palette was the bug: with the
    /// lasso armed, the colour grid opened against `.lasso`, and every tap
    /// hit `setPaletteSlot`'s guard and died silently.)
    private var paletteTool: AppState.AnnotationTool {
        state.tool == .highlighter ? .highlighter : .pencil
    }

    private let tools: [(AppState.AnnotationTool, String, String)] = [
        (.pencil, "pencil.tip", "Pencil"),
        (.highlighter, "highlighter", "Highlighter"),
        (.lasso, "lasso", "Lasso select"),
        (.eraser, "eraser", "Eraser"),
    ]

    var body: some View {
        HStack(spacing: 8) {
            Spacer()

            if let panel = activePanel {
                Group {
                    switch panel {
                    case .pencil:
                        PencilOptionsPanel(dismiss: { close() })
                    case .highlighter:
                        HighlighterOptionsPanel()
                    case .eraser:
                        EraserOptionsPanel()
                    case .lasso:
                        LassoOptionsPanel()
                    case .color(let slot, let tool):
                        ColorGridPanel(slot: slot, tool: tool)
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            rail
                .padding(.trailing, 12)
        }
        .frame(maxHeight: .infinity)
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.22), value: activePanel)
        // Pencil down on the page = back to work: any open options panel gets
        // out of the way without asking for a second tap.
        .onReceive(NotificationCenter.default.publisher(for: .virtuPencilOnPage)) { _ in
            guard activePanel != nil else { return }
            close()
        }
    }

    private var rail: some View {
        VStack(spacing: 8) {
            controlButton(icon: "arrow.uturn.backward", label: "Undo") {
                // The surface handles two-finger tap; this is the visible fallback.
                NotificationCenter.default.post(name: .virtuUndo, object: nil)
            }
            controlButton(icon: "arrow.uturn.forward", label: "Redo") {
                NotificationCenter.default.post(name: .virtuRedo, object: nil)
            }

            divider

            ForEach(tools, id: \.0.rawValue) { tool, icon, label in
                toolButton(tool: tool, icon: icon, label: label)
            }

            divider

            let palette = state.palette(for: paletteTool)
            ForEach(Array(palette.enumerated()), id: \.offset) { slot, hex in
                inkSwatch(slot: slot, hex: hex)
            }

            divider

            LayerStackView()
        }
        .padding(.vertical, 12)
        .frame(width: 56)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.accent.opacity(0.15), lineWidth: 1)
        )
    }

    private func close() {
        activePanel = nil
    }

    private func controlButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.rigid()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(theme.muted)
                .frame(width: 36, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func toolButton(tool: AppState.AnnotationTool, icon: String, label: String) -> some View {
        let isActive = state.tool == tool
        let panel = Self.panel(for: tool)

        // Built from bare gestures, not a Button: a SwiftUI Button swallows
        // the long press, which is why the pencil options never opened. Every
        // tool follows the pencil's grammar now — tap takes the tool, holding
        // it (or tapping it again once it is in your hand) opens its options.
        toolFace(icon: icon, isActive: isActive, showsMore: true, panel: panel)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.35) {
                Haptics.light()
                state.tool = tool
                activePanel = panel
            }
            .onTapGesture {
                Haptics.selection()
                if state.tool == tool {
                    activePanel = activePanel == panel ? nil : panel
                } else {
                    state.tool = tool
                    close()
                }
            }
            .accessibilityLabel(label)
            .accessibilityHint(Self.panelHint(for: tool))
    }

    private static func panel(for tool: AppState.AnnotationTool) -> Panel {
        switch tool {
        case .pencil: .pencil
        case .highlighter: .highlighter
        case .eraser: .eraser
        case .lasso: .lasso
        }
    }

    private static func panelHint(for tool: AppState.AnnotationTool) -> String {
        switch tool {
        case .pencil: "Thickness, line style and colour"
        case .highlighter: "Highlight height"
        case .eraser: "Eraser style and clearing"
        case .lasso: "Move or copy"
        }
    }

    private func toolFace(icon: String, isActive: Bool, showsMore: Bool, panel: Panel? = nil) -> some View {
        Image(systemName: icon)
            .font(.system(size: 17))
            .foregroundStyle(isActive ? theme.accent : theme.muted)
            .frame(width: 40, height: 40)
            .background(isActive ? theme.accent.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .leading) {
                // Points at where the options slide out from.
                if showsMore {
                    Image(systemName: activePanel == panel && panel != nil ? "chevron.right" : "chevron.left")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(isActive ? theme.accent : theme.muted)
                        .opacity(0.7)
                        .padding(.leading, 1)
                }
            }
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.line2)
            .frame(width: 28, height: 1)
            .padding(.vertical, 2)
    }

    /// Tap to draw with it. Tap it again once it is armed — or hold it — to
    /// change what it holds. The re-tap mirrors the tool buttons' grammar,
    /// and it means changing a colour never depends on a long-press landing.
    ///
    /// The first slot is the tool's own colour — graphite for the pencil,
    /// yellow for the highlighter — and it does not move. The other two are
    /// the musician's, and they are per tool: the highlighter's greens are not
    /// the pencil's, because a wash and a line want different colours.
    private func inkSwatch(slot: Int, hex: UInt32) -> some View {
        let isSelected = (state.toolColors[paletteTool] ?? 0) == hex
        let isFixed = slot == AppState.fixedSlot
        return Circle()
            .fill(Color(hex: hex))
            .frame(width: 26, height: 26)
            .overlay(
                Circle()
                    .stroke(theme.accent, lineWidth: isSelected ? 2 : 0)
                    .padding(-4)
            )
            .frame(width: 40, height: 34)   // the hit target a finger needs
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.selection()
                if isSelected, !isFixed {
                    activePanel = .color(slot: slot, tool: paletteTool)
                } else {
                    state.toolColors[paletteTool] = hex
                }
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                guard !isFixed else { return }
                Haptics.rigid()
                activePanel = .color(slot: slot, tool: paletteTool)
            }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isFixed ? "Ink, fixed" : "Ink \(slot + 1)")
            .accessibilityHint(isFixed ? "" : "Double tap and hold to change this colour")
            .accessibilityAction(named: "Change colour") {
                guard !isFixed else { return }
                activePanel = .color(slot: slot, tool: paletteTool)
            }
    }
}

// MARK: - Pencil options

/// Slides out to the left of the toolbar: nibs above, line styles below.
/// No headings — each control is a picture of the mark it makes, and a word
/// on top of that only takes up room the rail does not have.
private struct PencilOptionsPanel: View {
    let dismiss: () -> Void
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(AppState.nibWidths.enumerated()), id: \.offset) { index, width in
                thicknessDot(index: index, width: width)
            }

            Rectangle()
                .fill(theme.line2)
                .frame(width: 22, height: 1)
                .padding(.vertical, 2)

            ForEach(AppState.StrokeStyle.allCases, id: \.rawValue) { style in
                styleSwatch(style)
            }
        }
        .padding(.vertical, 12)
        .frame(width: 44)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.accent.opacity(0.15), lineWidth: 1)
        )
    }

    /// Each nib is drawn as a dot at its true relative size — the control
    /// shows you the mark, not a number describing it.
    private func thicknessDot(index: Int, width: CGFloat) -> some View {
        let isSelected = state.nibIndex == index
        return Button {
            Haptics.selection()
            state.nibIndex = index
        } label: {
            Circle()
                .fill(theme.ink)
                .frame(width: width * 2.2, height: width * 2.2)
                .frame(width: 30, height: 30)
                .background(isSelected ? theme.accent.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(theme.accent, lineWidth: isSelected ? 1.5 : 0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.nibLabel(width))
    }

    private static func nibLabel(_ width: CGFloat) -> String {
        let trimmed = width.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(width))
            : String(format: "%.1f", width)
        return "\(trimmed) point nib"
    }

    private func styleSwatch(_ style: AppState.StrokeStyle) -> some View {
        let isSelected = state.strokeStyle == style
        return Button {
            Haptics.selection()
            state.strokeStyle = style
        } label: {
            StyleSampleLine(style: style, color: theme.ink, nib: state.pencilWidth)
                .frame(width: 30, height: 26)
                .background(isSelected ? theme.accent.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(theme.accent, lineWidth: isSelected ? 1.5 : 0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.label)
    }
}

/// A miniature of what the style actually draws, at the selected nib. The
/// dotted geometry comes from InkRenderer itself — the swatch and the page
/// share one set of numbers, so they cannot drift apart.
private struct StyleSampleLine: View {
    let style: AppState.StrokeStyle
    let color: Color
    let nib: CGFloat

    var body: some View {
        Canvas { context, size in
            let y = size.height / 2
            var path = Path()
            path.move(to: CGPoint(x: 5, y: y))
            path.addLine(to: CGPoint(x: size.width - 5, y: y))

            switch style {
            case .solid:
                context.stroke(path, with: .color(color),
                               style: .init(lineWidth: nib, lineCap: .round))
            case .calligraphic:
                // A swell, the way a nib loads and lifts.
                var swell = Path()
                swell.move(to: CGPoint(x: 5, y: y))
                swell.addQuadCurve(
                    to: CGPoint(x: size.width - 5, y: y),
                    control: CGPoint(x: size.width / 2, y: y - 3))
                context.stroke(swell, with: .color(color),
                               style: .init(lineWidth: nib * 1.15, lineCap: .round))
            case .dotted:
                let g = InkRenderer.dottedGeometry(nib: nib)
                context.stroke(path, with: .color(color),
                               style: .init(lineWidth: g.width, lineCap: .round, dash: g.dash))
            case .fineDotted:
                let g = InkRenderer.fineDottedGeometry(nib: nib)
                context.stroke(path, with: .color(color),
                               style: .init(lineWidth: g.width, lineCap: .round, dash: g.dash))
            }
        }
    }
}

// MARK: - Layers

/// The layer stack, at the foot of the toolbar where the marking happens.
/// Tap a number to mark on it; tap its eye to hide it. Hide them all and the
/// engraving is clean — which is the entire point of the feature.
private struct LayerStackView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 3) {
            // Three layers, always — no label, no adding. The numbers are the
            // control; the eye appears only on layers that are showing.
            ForEach(1...AnnotationLayers.max, id: \.self) { index in
                layerRow(index)
            }
        }
    }

    // A pencil tip is exact where a finger gets UIKit's touch slop, so these
    // targets are sized for the pencil: at 22x26 the eye was a coin toss with
    // a Pencil and reliable with a finger, which is precisely backwards for a
    // Pencil-first app.
    private func layerRow(_ index: Int) -> some View {
        let isActive = state.activeLayer == index
        let isVisible = state.isLayerVisible(index)

        return HStack(spacing: 0) {
            Button {
                Haptics.selection()
                state.activateLayer(index)
            } label: {
                Text("\(index)")
                    .font(VFont.mono(11, weight: isActive ? .medium : .regular))
                    .foregroundStyle(
                        isActive ? theme.accent : (isVisible ? theme.muted : theme.faint)
                    )
                    .frame(width: 30, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Layer \(index)")
            .accessibilityAddTraits(isActive ? [.isSelected] : [])

            // A hidden layer shows NO eye at all — absence is the off state.
            // The button stays, full size, so the spot you tap to bring it
            // back is the spot the eye vanished from.
            Button {
                Haptics.selection()
                state.toggleLayerVisibility(index)
            } label: {
                Group {
                    if isVisible {
                        Image(systemName: "eye")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.muted)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 26, height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isVisible ? "Hide layer \(index)" : "Show layer \(index)")
        }
        .background(isActive ? theme.accent.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

extension Notification.Name {
    /// Posted by the reading surface the moment a pencil touches a page.
    static let virtuPencilOnPage = Notification.Name("virtuPencilOnPage")
    static let virtuUndo = Notification.Name("virtuUndo")
    static let virtuRedo = Notification.Name("virtuRedo")
    static let virtuClearHighlights = Notification.Name("virtuClearHighlights")
    static let virtuClearSpread = Notification.Name("virtuClearSpread")
}

// MARK: - Highlighter options

/// Four heights, each drawn as the wash it makes — the control is a picture
/// of the mark, exactly like the pencil's nib dots.
private struct HighlighterOptionsPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(AppState.highlighterWidths.enumerated()), id: \.offset) { index, width in
                let isSelected = state.highlighterWidthIndex == index
                Button {
                    Haptics.selection()
                    state.highlighterWidthIndex = index
                } label: {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: state.toolColors[.highlighter] ?? AppState.highlighterYellowHex))
                        .opacity(0.35)
                        .frame(width: 56, height: width * 0.6)
                        .frame(width: 72, height: 40)
                        .background(isSelected ? theme.accent.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(theme.accent, lineWidth: isSelected ? 1.5 : 0)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Int(width)) point highlight")
            }
        }
        .padding(.vertical, 12)
        .frame(width: 84)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.accent.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Eraser options

/// Two ways to take ink off, then the two bulk clears that used to hide in a
/// context menu.
private struct EraserOptionsPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            // Icons only, like the nib dots: the dashed eraser rubs out just
            // what it touches, the solid one takes the whole marking. Both
            // work on any ink — writing, highlight, all of it.
            modeIcon(.area, icon: "eraser.line.dashed")
            modeIcon(.stroke, icon: "eraser.fill")
        }
        .padding(.vertical, 12)
        .frame(width: 44)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.accent.opacity(0.15), lineWidth: 1)
        )
    }

    private func modeIcon(_ mode: AppState.EraserMode, icon: String) -> some View {
        let isSelected = state.eraserMode == mode
        return Button {
            Haptics.selection()
            state.eraserMode = mode
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(isSelected ? theme.accent : theme.muted)
                .frame(width: 30, height: 30)
                .background(isSelected ? theme.accent.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(theme.accent, lineWidth: isSelected ? 1.5 : 0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode == .area ? "Erase touched area" : "Erase whole marking")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Lasso options

/// Move is PencilKit's own selection-and-drag, untouched. Copy clips a region
/// of the page — ink and engraving alike — into a floating snapshot that can
/// be dropped anywhere, the Right Page included.
private struct LassoOptionsPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            // Lasso moves; the doubled sheet copies. Copy clips anything on
            // the page and drops it anywhere, the Right Page included.
            modeIcon(.move, icon: "lasso")
            modeIcon(.copy, icon: "doc.on.doc")
        }
        .padding(.vertical, 12)
        .frame(width: 44)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.accent.opacity(0.15), lineWidth: 1)
        )
    }

    private func modeIcon(_ mode: AppState.LassoMode, icon: String) -> some View {
        let isSelected = state.lassoMode == mode
        return Button {
            Haptics.selection()
            state.lassoMode = mode
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(isSelected ? theme.accent : theme.muted)
                .frame(width: 30, height: 30)
                .background(isSelected ? theme.accent.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(theme.accent, lineWidth: isSelected ? 1.5 : 0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode == .move ? "Move selection" : "Copy region")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Colour grid

/// The whole colour control: a grid, nothing else. No tabs, no titles, no
/// spectrum — a musician picking an ink wants a swatch, not a colour lab.
/// Below the grid sits the chosen colour at full size, wearing its sRGB hex
/// quietly at the bottom.
private struct ColorGridPanel: View {
    let slot: Int
    let tool: AppState.AnnotationTool
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    private static let columns = 10

    /// Apple-grid-shaped: a grayscale ramp on top, then hue rows from light
    /// tints to deep shades.
    private static let cells: [UInt32] = {
        var out: [UInt32] = []
        // Grayscale row, white to black.
        for i in 0..<columns {
            let v = 255 - Int(round(Double(i) * 255.0 / Double(columns - 1)))
            out.append(UInt32(v) << 16 | UInt32(v) << 8 | UInt32(v))
        }
        // Hue rows: 7 rows of brightness/saturation ramps across 10 hues.
        let rows: [(sat: Double, bri: Double)] = [
            (0.22, 1.00), (0.42, 1.00), (0.62, 0.98), (0.82, 0.94),
            (1.00, 0.86), (1.00, 0.66), (1.00, 0.46),
        ]
        for row in rows {
            for i in 0..<columns {
                let hue = Double(i) / Double(columns)
                let c = UIColor(hue: hue, saturation: row.sat, brightness: row.bri, alpha: 1)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                c.getRed(&r, green: &g, blue: &b, alpha: nil)
                let ch = { (v: CGFloat) in UInt32((max(0, min(1, v)) * 255).rounded()) }
                out.append(ch(r) << 16 | ch(g) << 8 | ch(b))
            }
        }
        return out
    }()

    private var current: UInt32 {
        state.palette(for: tool).indices.contains(slot) ? state.palette(for: tool)[slot] : 0
    }

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(20), spacing: 3), count: Self.columns),
                spacing: 3
            ) {
                ForEach(Array(Self.cells.enumerated()), id: \.offset) { _, hex in
                    let isSelected = hex == current
                    Button {
                        Haptics.selection()
                        state.setPaletteSlot(slot, to: hex, for: tool)
                    } label: {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: hex))
                            .frame(width: 20, height: 20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(isSelected ? theme.accent : Color.black.opacity(0.08),
                                            lineWidth: isSelected ? 2 : 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // The chosen colour, and its name in the one notation that
            // survives being written down.
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: current))
                .frame(height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.10), lineWidth: 0.5)
                )
                .overlay(alignment: .bottom) {
                    Text(String(format: "#%06X", current))
                        .font(VFont.catalogueNumber)
                        .foregroundStyle(.white.opacity(0.75))
                        .blendMode(.difference)
                        .padding(.bottom, 5)
                }
        }
        .padding(12)
        .frame(width: 254)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.accent.opacity(0.15), lineWidth: 1)
        )
        .accessibilityLabel("Colour grid")
    }
}
