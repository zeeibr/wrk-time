import SwiftUI

/// Almanac palette.
///
/// The app has two registers. In `document` you are reading — oat ground, ink
/// type, moss rules. In `field` you are working — the ground inverts, and the
/// only warm thing left is the draining saffron block behind the count.
enum Palette {
    /// Warm ground. Oat, not cream: it has green in it, so it sits under moss
    /// rules without the rules reading as grey.
    static let oat = Color(hex: 0xE9E5D9)
    /// Everything you read.
    static let ink = Color(hex: 0x0F1A15)
    /// Secondary type, laid-down marks, the closed part of a ring.
    static let moss = Color(hex: 0x35513F)
    /// Ghost rings and hairline icons **on oat**, and secondary type on the
    /// field ground only.
    ///
    /// On oat this measures 2.03:1 — not merely short of 4.5:1 but under the
    /// 3:1 floor for non-text too. It is therefore barred from carrying any
    /// text in the document register; reach for `mute` (5.28:1) instead, or
    /// better, let `Register.secondary` pick for you. On the field ground it is
    /// 6.95:1 and perfectly legible, which is why it lives on.
    static let sage = Color(hex: 0x8FA894)
    /// Muted body copy that still needs to be read. 5.28:1 on oat.
    static let mute = Color(hex: 0x4A6252)
    /// Today's mark, and the live round. Nothing else.
    ///
    /// A fill or a stroke, never type on oat — saffron on oat is 1.82:1. When
    /// saffron has to be *read* in the document register, use `saffronInk`.
    static let saffron = Color(hex: 0xD9A227)
    /// Saffron dark enough to read on oat, at 4.6:1. Same hue family, so it
    /// still says "live" without being illegible about it.
    static let saffronInk = Color(hex: 0x9A7112)

    /// The working ground. Near-black with the same green bias as the ink, so
    /// the register change reads as the same world seen at night.
    static let field = Color(hex: 0x101A14)

    /// Rules are moss at low alpha rather than a grey, so even the hairlines
    /// belong to the family.
    ///
    /// At their design alphas these measure 1.41:1, 1.91:1 and 1.74:1 — fine
    /// for decoration, and the reason each has an Increase Contrast variant.
    /// `ruleOnField` is not decoration at all: it is the only boundary the
    /// End and Skip controls have, so under Increase Contrast it has to clear
    /// 3:1 as a control edge.
    static let rule = Color(hex: 0x35513F, alpha: 0.22)
    static let ruleFirm = Color(hex: 0x35513F, alpha: 0.40)
    static let ruleOnField = Color(hex: 0xE9E5D9, alpha: 0.20)

    static func rule(increased: Bool) -> Color {
        Color(hex: 0x35513F, alpha: increased ? 0.70 : 0.22)      // 3.49:1
    }
    static func ruleFirm(increased: Bool) -> Color {
        Color(hex: 0x35513F, alpha: increased ? 0.85 : 0.40)      // 4.88:1
    }
    static func ruleOnField(increased: Bool) -> Color {
        Color(hex: 0xE9E5D9, alpha: increased ? 0.50 : 0.20)      // 4.41:1
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// Which register a surface is in. Views read this rather than hard-coding
/// colours, so the document/field flip is one value rather than a rewrite.
enum Register {
    case document
    case field

    var ground: Color { self == .document ? Palette.oat : Palette.field }
    var primary: Color { self == .document ? Palette.ink : Palette.oat }
    var secondary: Color { self == .document ? Palette.mute : Palette.sage }
    var rule: Color { self == .document ? Palette.rule : Palette.ruleOnField }
    var colorScheme: ColorScheme { self == .document ? .light : .dark }
}

private struct RegisterKey: EnvironmentKey {
    static let defaultValue: Register = .document
}

extension EnvironmentValues {
    var register: Register {
        get { self[RegisterKey.self] }
        set { self[RegisterKey.self] = newValue }
    }
}
