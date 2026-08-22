import SwiftUI

/// The three voices of the app, per the design handoff: Newsreader (serif) for
/// titles and works, Archivo (sans) for UI, JetBrains Mono for numbers.
/// Static weights are bundled and selected by PostScript name.
enum VFont {
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = switch weight {
        case .medium, .semibold, .bold: "Newsreader-Medium"
        default: "Newsreader-Regular"
        }
        return .custom(name, size: size)
    }

    static func serifItalic(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Newsreader-Italic", size: size)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = switch weight {
        case .semibold, .bold: "Archivo-SemiBold"
        case .medium: "Archivo-Medium"
        default: "Archivo-Regular"
        }
        return .custom(name, size: size)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = switch weight {
        case .medium, .semibold, .bold: "JetBrainsMono-Medium"
        default: "JetBrainsMono-Regular"
        }
        return .custom(name, size: size)
    }

    // Named roles from the design handoff
    static let screenTitle = serif(38)
    static let sectionHeading = serif(20)
    static let workTitle = serif(17)
    static let scoreTitle = serif(15)
    static let nowPlayingTitle = serif(17)

    static let eyebrow = sans(10.5, weight: .semibold)
    /// Screen titles ("Your shelf", "Recycle bin"): the eyebrow's voice — 
    /// uppercase accent sans — a step larger, replacing the 38pt serif that
    /// out-shouted every page it sat on.
    static let screenEyebrow = sans(13, weight: .semibold)
    static let railLabel = sans(9.5, weight: .medium)
    static let panelLabel = sans(10.5, weight: .semibold)
    static let control = sans(13, weight: .medium)
    static let body = sans(13, weight: .regular)
    static let metadata = sans(11, weight: .regular)
    static let searchInput = sans(15)

    static let bpmPanel = mono(44, weight: .medium)
    static let bpmTools = mono(60, weight: .medium)
    static let catalogueNumber = mono(10.5)
    static let pageNumber = mono(9)
}

// MARK: - UIFont equivalents for UIKit contexts

enum VUIFont {
    static func serif(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let name = weight.rawValue >= UIFont.Weight.medium.rawValue ? "Newsreader-Medium" : "Newsreader-Regular"
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    static func sans(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let name: String
        if weight.rawValue >= UIFont.Weight.semibold.rawValue {
            name = "Archivo-SemiBold"
        } else if weight.rawValue >= UIFont.Weight.medium.rawValue {
            name = "Archivo-Medium"
        } else {
            name = "Archivo-Regular"
        }
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    static func mono(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let name = weight.rawValue >= UIFont.Weight.medium.rawValue ? "JetBrainsMono-Medium" : "JetBrainsMono-Regular"
        return UIFont(name: name, size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }
}
