import SwiftUI

/// Study mode's single tool surface: docked to the right edge so it never
/// drifts over the notation being marked. Always at full strength — a toolbar
/// that fades is one you have to wake before you can use it, and the moment
/// you reach for a pencil is never the moment to be kept waiting.
/// Replaces both the M1 floating rail and the system PKToolPicker.
struct ToolRailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    @State private var showPencilOptions = false

    private let tools: [(AppState.AnnotationTool, String, String)] = [
        (.pencil, "pencil.tip", "Pencil"),
        (.highlighter, "highlighter", "Highlighter"),
        (.lasso, "lasso", "Lasso select"),
        (.eraser, "eraser", "Eraser"),
    ]

    private let inks: [(UInt32, String)] = [
        (AppState.graphiteHex, "Graphite"),
        (0xC0392B, "Red"),
        (0x2B3E5E, "Blue"),
        (0x2D6A3F, "Green"),
    ]

    var body: some View {
        HStack(spacing: 8) {
            Spacer()

            if showPencilOptions {
                PencilOptionsPanel(dismiss: { close() })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            rail
                .padding(.trailing, 12)
        }
        .frame(maxHeight: .infinity)
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.22), value: showPencilOptions)
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
                if tool == .eraser {
                    toolButton(tool: tool, icon: icon, label: label)
                        .contextMenu {
                            Button("Clear highlighter on this spread") {
                                NotificationCenter.default.post(name: .virtuClearHighlights, object: nil)
                            }
                            Button("Clear this spread", role: .destructive) {
                                NotificationCenter.default.post(name: .virtuClearSpread, object: nil)
                            }
                        }
                } else {
                    toolButton(tool: tool, icon: icon, label: label)
                }
            }

            divider

            ForEach(inks, id: \.0) { hex, label in
                inkSwatch(hex: hex, label: label)
            }
            customInkSwatch

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
        showPencilOptions = false
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

        if tool == .pencil {
            // Built from bare gestures, not a Button: a SwiftUI Button
            // swallows the long press, which is why the options never opened.
            toolFace(icon: icon, isActive: isActive, showsMore: true)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.35) {
                    Haptics.light()
                    state.tool = .pencil
                    showPencilOptions = true
                }
                .onTapGesture {
                    Haptics.selection()
                    if state.tool == .pencil {
                        // Tapping the pencil already in your hand opens its
                        // options. A long press nobody can see is a feature
                        // nobody has.
                        showPencilOptions.toggle()
                    } else {
                        state.tool = .pencil
                    }
                }
                .accessibilityLabel(label)
                .accessibilityHint("Thickness, line style and colour")
        } else {
            Button {
                Haptics.selection()
                state.tool = tool
                close()
            } label: {
                toolFace(icon: icon, isActive: isActive, showsMore: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
        }
    }

    private func toolFace(icon: String, isActive: Bool, showsMore: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 17))
            .foregroundStyle(isActive ? theme.accent : theme.muted)
            .frame(width: 40, height: 40)
            .background(isActive ? theme.accent.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .leading) {
                // Points at where the options slide out from.
                if showsMore {
                    Image(systemName: showPencilOptions ? "chevron.right" : "chevron.left")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(isActive ? theme.accent : theme.muted)
                        .opacity(0.7)
                        .padding(.leading, 1)
                }
            }
    }

    /// The fifth colour: whatever the musician wants. Sits with the presets
    /// rather than inside the pencil options, because a colour is a colour —
    /// there is no reason four of them live in one place and the rest in
    /// another.
    private var customInkSwatch: some View {
        let current = state.toolColors[state.tool] ?? AppState.graphiteHex
        let isCustom = state.tool != .eraser && !inks.contains { $0.0 == current }
        return ColorPicker(
            "Choose colour",
            selection: Binding(
                get: { Color(hex: current) },
                set: { newValue in
                    guard state.tool != .eraser else { return }
                    state.toolColors[state.tool] = newValue.hexValue
                }
            ),
            supportsOpacity: false
        )
        .labelsHidden()
        .frame(width: 26, height: 26)
        .overlay(
            Circle()
                .stroke(theme.accent, lineWidth: isCustom ? 2 : 0)
                .padding(-4)
        )
        .accessibilityLabel("Choose colour")
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.line2)
            .frame(width: 28, height: 1)
            .padding(.vertical, 2)
    }

    private func inkSwatch(hex: UInt32, label: String) -> some View {
        let isSelected = (state.toolColors[state.tool] ?? 0) == hex && state.tool != .eraser
        return Button {
            Haptics.selection()
            if state.tool != .eraser {
                state.toolColors[state.tool] = hex
            }
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 26, height: 26)
                .overlay(
                    Circle()
                        .stroke(theme.accent, lineWidth: isSelected ? 2 : 0)
                        .padding(-4)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
            Text("Layer")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(theme.muted)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.bottom, 2)

            // Ten layers would otherwise push the toolbar past the height of
            // an iPad mini in landscape.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(1...max(state.layerCount, 1), id: \.self) { index in
                        layerRow(index)
                    }
                }
            }
            .frame(maxHeight: 214)
            .fixedSize(horizontal: false, vertical: state.layerCount < 6)

            if state.canAddLayer {
                Button {
                    Haptics.selection()
                    state.addLayer()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.muted)
                        .frame(width: 48, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add layer")
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

            Button {
                Haptics.selection()
                state.toggleLayerVisibility(index)
            } label: {
                Image(systemName: isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(isVisible ? theme.muted : theme.faint)
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
    static let virtuUndo = Notification.Name("virtuUndo")
    static let virtuRedo = Notification.Name("virtuRedo")
    static let virtuClearHighlights = Notification.Name("virtuClearHighlights")
    static let virtuClearSpread = Notification.Name("virtuClearSpread")
}
