import SwiftUI

/// Chrome that more than one screen wears.
///
/// Both of these were hand-drawn at three call sites each before this file
/// existed, and they had already drifted: one card reached for `wash` where
/// the others used `plate`, and one eyebrow carried different padding. A
/// design system that has to be retyped is a design system that stops being
/// one.

private struct PlateCard: ViewModifier {
    /// Defaults to the plate. Passed explicitly only where a surface is
    /// deliberately a shade back from it — the Next Performance panel.
    let fill: Color?
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .background(fill ?? theme.plate)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.card)
                    .stroke(theme.line, lineWidth: 1)
            )
    }
}

private struct ScreenEyebrowStyle: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .font(VFont.screenEyebrow)
            .foregroundStyle(theme.accent)
            .textCase(.uppercase)
            .tracking(1.5)
    }
}

extension View {
    /// The app's one card: plate, 14pt corner, hairline rule.
    func plateCard(fill: Color? = nil) -> some View {
        modifier(PlateCard(fill: fill))
    }

    /// A screen's own name, in the eyebrow's voice (decided 2026-08-26, when
    /// the 38pt serif titles came out). Carries no padding — how much air a
    /// screen wants under its name is the screen's business.
    func screenEyebrow() -> some View {
        modifier(ScreenEyebrowStyle())
    }
}
