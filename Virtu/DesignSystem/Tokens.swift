import SwiftUI

enum Tokens {

    // MARK: - Light palette ("paper")

    enum Light {
        static let paper    = Color(hex: 0xF2EFE8)
        static let plate    = Color(hex: 0xFFFDF8)
        static let ink      = Color(hex: 0x16151A)
        static let muted    = Color(hex: 0x75726B)
        static let faint    = Color(hex: 0xA9A49A)
        static let line     = Color(hex: 0xE0DBD1)
        static let line2    = Color(hex: 0xCFC9BD)
        static let accent   = Color(hex: 0xB33F26)
        static let blue     = Color(hex: 0x2B3E5E)
        static let wash     = Color(hex: 0xE9E5DC)
        static let notation = Color(hex: 0x1A1A1F)
        static let rail     = Color(hex: 0x161519)
        static let railInk  = Color(hex: 0xEDE9E1)
        static let railFaint = Color(hex: 0x8A857C)
    }

    // MARK: - Stage mode palette (dark)

    enum Stage {
        static let paper    = Color(hex: 0x0B0B0D)
        static let plate    = Color(hex: 0x131317)
        static let ink      = Color(hex: 0xE6E2DA)
        static let muted    = Color(hex: 0x8B877F)
        static let faint    = Color(hex: 0x63605A)
        static let line     = Color(hex: 0x26262B)
        static let line2    = Color(hex: 0x35353B)
        static let accent   = Color(hex: 0xD9694E)
        static let blue     = Color(hex: 0x7C93BC)
        static let wash     = Color(hex: 0x1A1A1F)
        static let notation = Color(hex: 0xC9C5BC)
        static let rail     = Color(hex: 0x0B0B0D)
        static let railInk  = Color(hex: 0xE6E2DA)
        static let railFaint = Color(hex: 0x6B6862)
    }

    // MARK: - Annotation inks

    static let inkRed   = Color(hex: 0xB33F26)
    static let inkBlue  = Color(hex: 0x2B3E5E)
    static let inkGreen = Color(hex: 0x2D6A3F)
    static let inkWhite = Color(hex: 0xEDE9E1)

    // MARK: - Radii

    enum Radius {
        static let pageThumbnail: CGFloat = 3
        static let scorePage: CGFloat = 4
        static let smallControl: CGFloat = 8
        static let button: CGFloat = 10
        static let toolButton: CGFloat = 11
        static let searchInput: CGFloat = 12
        static let seamStrip: CGFloat = 12
        static let card: CGFloat = 14
        static let floatingPanel: CGFloat = 16
        static let pill: CGFloat = 999
    }

    // MARK: - Spacing

    static let screenPadding = EdgeInsets(top: 34, leading: 40, bottom: 48, trailing: 40)
    static let gridUnit: CGFloat = 4

    // MARK: - Hit targets

    static let tapZoneWidth: CGFloat = 170
    static let railButtonSize = CGSize(width: 56, height: 48)
    static let annotationToolSize: CGFloat = 44
    // MARK: - Always-on reading controls (top right)
    //
    // Sized against each other rather than to a 44pt grid. At 44pt square the
    // two icons read as unrelated neighbours: the frames add ~29pt of air on
    // top of the gap itself. Narrow frames, tall touch area, and the visible
    // separation lands near half an icon — close enough to be a pair, far
    // enough that a hurried hand before a downbeat cannot hit the wrong one.
    // Real spacing, not padding inside the frames. Widening the frames alone
    // grew the *look* of a gap while leaving the targets edge to edge — so a
    // finger aimed at the mode toggle and landing a few points left hit
    // Library instead and navigated away. Which is what "cannot switch modes
    // with a finger" actually was. The gap between targets is now empty
    // screen: a near miss does nothing, and doing nothing is recoverable.
    // 34x44 hit fine with a pencil tip and badly with a finger — a fingertip
    // pad is ~18pt across and lands with real scatter, so the target is now
    // a full 52x56 with the same empty-screen gap between neighbours. The
    // glyphs grew with it, and they wear the translucent Repertoire red so
    // the extra size does not cost the page underneath.
    static let readingControlIcon = CGSize(width: 52, height: 56)
    static let readingControlGlyph: CGFloat = 23
    static let readingControlSpacing: CGFloat = 10

    /// Lifts the row clear of the very bottom edge, which iPadOS reserves for
    /// its own gesture.
    static let readingControlBottomInset: CGFloat = 12

    /// How far down from the top a touch still means "show me the score
    /// info", as a fraction of the view height.
    static let chromeSummonBand: CGFloat = 0.12

    // The controls live at the BOTTOM right, overlaying the page's own
    // printed margin. The top right belongs to iPadOS — wifi, battery, the
    // lot — so anything we put up there is read through somebody's icons.

    /// Horizontal band the row occupies, at its widest: share, Library, mode.
    /// Chrome keeps clear of it.
    static let readingControlsBand: CGFloat =
        readingControlIcon.width * 3 + readingControlSpacing * 2 + 12

    /// Room to leave for the status bar's own content. The clock and date sit
    /// at the leading edge, the radio and battery indicators at the trailing
    /// one, and neither is ours to move — so the title block starts inboard of
    /// the first and stops short of the second.
    static let statusBarLeadingInset: CGFloat = 190
    static let statusBarTrailingInset: CGFloat = 130

    // MARK: - Shared margins

    /// Scratch space beside the score, as a fraction of one page. A whole page
    /// of it, not a strip: this is where a fingering chart, the conductor's
    /// notes from Tuesday, or a worked-out bowing goes, and none of those fit
    /// in a gutter. Shared across the whole part, so it is written once rather
    /// than on every page.
    static let marginWidthFraction: CGFloat = 1.0

    /// Empty space below the score — headroom, not paper. Nothing is ever
    /// written here; it exists so the page can be pushed up far enough to
    /// reach and mark its lowest system instead of writing at the bezel.
    ///
    /// Fixed, and the same on every iPad — a fraction of the page was the wrong
    /// unit, because what this has to clear is a hand, and a hand is the same
    /// size on a mini and on a 13".
    ///
    /// For scale, measured off the Bach at iPad Pro 13" size (page 1333pt): the
    /// bare five-line staff is 33.5pt, one bar of ink with its stems, slurs and
    /// ornaments is 75pt, one bar's slot from system to system is 119pt. So 70
    /// is just under one bar of ink — enough to lift the lowest system clear of
    /// the bezel, and no more.
    static let bottomHeadroom: CGFloat = 70

    // MARK: - Rail

    static let railWidth: CGFloat = 76
}

// MARK: - Theme resolver

struct Theme {
    let paper: Color
    let plate: Color
    let ink: Color
    let muted: Color
    let faint: Color
    let line: Color
    let line2: Color
    let accent: Color
    let blue: Color
    let wash: Color
    let notation: Color
    let rail: Color
    let railInk: Color
    let railFaint: Color

    static let light = Theme(
        paper: Tokens.Light.paper, plate: Tokens.Light.plate,
        ink: Tokens.Light.ink, muted: Tokens.Light.muted,
        faint: Tokens.Light.faint, line: Tokens.Light.line,
        line2: Tokens.Light.line2, accent: Tokens.Light.accent,
        blue: Tokens.Light.blue, wash: Tokens.Light.wash,
        notation: Tokens.Light.notation, rail: Tokens.Light.rail,
        railInk: Tokens.Light.railInk, railFaint: Tokens.Light.railFaint
    )

    static let stage = Theme(
        paper: Tokens.Stage.paper, plate: Tokens.Stage.plate,
        ink: Tokens.Stage.ink, muted: Tokens.Stage.muted,
        faint: Tokens.Stage.faint, line: Tokens.Stage.line,
        line2: Tokens.Stage.line2, accent: Tokens.Stage.accent,
        blue: Tokens.Stage.blue, wash: Tokens.Stage.wash,
        notation: Tokens.Stage.notation, rail: Tokens.Stage.rail,
        railInk: Tokens.Stage.railInk, railFaint: Tokens.Stage.railFaint
    )
}

struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.light
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Color hex init

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    init(hex: UInt32) {
        self.init(hex: hex, opacity: 1)
    }

    /// Back to a 0xRRGGBB value for storage — the currency the ink model
    /// already speaks. Whatever wide-gamut colour the system picker hands
    /// back is clamped into it rather than rejected.
    var hexValue: UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return 0x26221E
        }
        let channel: (CGFloat) -> UInt32 = { UInt32((max(0, min(1, $0)) * 255).rounded()) }
        return channel(r) << 16 | channel(g) << 8 | channel(b)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
