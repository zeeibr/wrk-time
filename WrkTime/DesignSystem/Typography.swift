import SwiftUI

/// Almanac type. Three faces, strictly zoned:
///
/// - **Slab** for headings and the things you'd read aloud. Sturdy and warm
///   rather than precious — a fine old-style serif would tip the lane into
///   preciousness, which is the failure mode we designed away from.
/// - **UI** (system sans) for controls, body copy and anything interactive.
/// - **Mono** for every label, unit, index and timestamp. Never body copy.
enum Face {
    static func slab(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Superclarendon", size: size, relativeTo: .body)
            .weight(weight)
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Font {
    /// Display slab, for the one thing a screen is about.
    static let almanacTitle = Face.slab(28)
    static let almanacHeading = Face.slab(21)
    static let almanacMoveName = Face.slab(19)

    /// Body and controls.
    static let almanacBody = Face.ui(15)
    static let almanacBodySmall = Face.ui(13)
    static let almanacButton = Face.ui(16, weight: .semibold)

    /// Labels. Always uppercase, always tracked — see `.almanacLabel()`.
    static let almanacLabel = Face.mono(11)
    static let almanacLabelSmall = Face.mono(10)

    /// The count. Monospaced digits so nothing shifts width as it ticks down,
    /// which matters more here than anywhere else in the app.
    static func almanacCount(_ size: CGFloat) -> Font {
        Face.ui(size, weight: .light).monospacedDigit()
    }
}

extension View {
    /// A mono label: uppercase, tracked, and never larger than it needs to be.
    func almanacLabel(_ color: Color? = nil, small: Bool = false) -> some View {
        self
            .font(small ? .almanacLabelSmall : .almanacLabel)
            .textCase(.uppercase)
            .tracking(small ? 1.5 : 1.7)
            .foregroundStyle(color ?? Palette.mute)
    }

    /// Digits that line up in columns.
    func tabular() -> some View {
        monospacedDigit()
    }
}
