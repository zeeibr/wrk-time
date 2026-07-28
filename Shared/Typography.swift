import SwiftUI
import UIKit

/// Almanac type. Three faces, strictly zoned:
///
/// - **Slab** for headings and the things you'd read aloud. Sturdy and warm
///   rather than precious — a fine old-style serif would tip the lane into
///   preciousness, which is the failure mode we designed away from.
/// - **UI** (system sans) for controls, body copy and anything interactive.
/// - **Mono** for every label, unit, index and timestamp. Never body copy.
///
/// Every size here is the design value at the default text size. Dynamic Type
/// scales from there. `Font.system(size:)` on its own is frozen, which used to
/// mean the slab headings grew at accessibility sizes while the body and the
/// labels beside them did not — the hierarchy inverted rather than enlarged.
enum Face {
    /// The design size scaled for the reader's text size.
    static func scaledValue(_ size: CGFloat, relativeTo style: UIFont.TextStyle) -> CGFloat {
        UIFontMetrics(forTextStyle: style).scaledValue(for: size)
    }

    static func slab(_ size: CGFloat, weight: Font.Weight = .regular,
                     relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Superclarendon", size: size, relativeTo: style)
            .weight(weight)
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular,
                   relativeTo style: UIFont.TextStyle = .body) -> Font {
        .system(size: scaledValue(size, relativeTo: style), weight: weight, design: .default)
    }

    /// Labels are already small and heavily tracked, so they scale against
    /// `.caption2` — the curve that grows least — and lean on the large content
    /// viewer rather than on becoming headline-sized.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular,
                     relativeTo style: UIFont.TextStyle = .caption2) -> Font {
        .system(size: scaledValue(size, relativeTo: style), weight: weight, design: .monospaced)
    }

    /// A size that has already been decided. Only the count needs this.
    static func fixed(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

extension Font {
    /// Display slab, for the one thing a screen is about. Computed rather than
    /// stored so a change of text size is picked up on the next render.
    static var almanacTitle: Font { Face.slab(28, relativeTo: .largeTitle) }
    static var almanacHeading: Font { Face.slab(21, relativeTo: .title2) }
    static var almanacMoveName: Font { Face.slab(19, relativeTo: .headline) }

    /// Body and controls.
    static var almanacBody: Font { Face.ui(15) }
    static var almanacBodySmall: Font { Face.ui(13, relativeTo: .footnote) }
    static var almanacButton: Font { Face.ui(16, weight: .semibold, relativeTo: .headline) }

    /// Labels. Always uppercase, always tracked — see `.almanacLabel()`.
    static var almanacLabel: Font { Face.mono(11) }
    static var almanacLabelSmall: Font { Face.mono(10) }

    /// The count — the largest mark in the product, and the frame a user sees a
    /// thousand times.
    ///
    /// Set in the slab, like every other figure in the approved mockup. It was
    /// SF Pro Light, which meant the app's signature screen could have belonged
    /// to any timer in the store: the slab appeared on three prose headlines
    /// while the numbers an almanac exists to record were set in the system
    /// face. Monospaced digits so nothing shifts width as it ticks down, which
    /// matters more here than anywhere else.
    ///
    /// It scales, but only so far. Past roughly a third larger, "0:00" stops
    /// fitting across the screen at all, and a clipped clock is worse than one
    /// that grew less than the body did. It starts at about seven times body
    /// size, so it needs headroom rather than multiplication.
    static func almanacCount(_ size: CGFloat) -> Font {
        let scaled = min(Face.scaledValue(size, relativeTo: .largeTitle), size * 1.35)
        return .custom("Superclarendon", fixedSize: scaled).monospacedDigit()
    }
}

extension View {
    /// A mono label: uppercase, tracked, and never larger than it needs to be.
    ///
    /// These are the smallest type in the app and they are tracked wide, so
    /// they deliberately scale least. The large content viewer is the sanctioned
    /// way out for type that genuinely cannot grow without breaking the layout.
    func almanacLabel(_ color: Color? = nil, small: Bool = false) -> some View {
        self
            .font(small ? .almanacLabelSmall : .almanacLabel)
            .textCase(.uppercase)
            .tracking(small ? 1.5 : 1.7)
            .foregroundStyle(color ?? Palette.mute)
            .accessibilityShowsLargeContentViewer()
    }

    /// Digits that line up in columns.
    func tabular() -> some View {
        monospacedDigit()
    }
}
