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
    /// Ghost rings, hairline icons, disabled states. Never body text — it does
    /// not clear 4.5:1 on oat and is not allowed to try.
    static let sage = Color(hex: 0x8FA894)
    /// Muted body copy that still needs to be read.
    static let mute = Color(hex: 0x4A6252)
    /// Today's mark, and the live round. Nothing else.
    static let saffron = Color(hex: 0xD9A227)

    /// The working ground. Near-black with the same green bias as the ink, so
    /// the register change reads as the same world seen at night.
    static let field = Color(hex: 0x101A14)

    /// Rules are moss at low alpha rather than a grey, so even the hairlines
    /// belong to the family.
    static let rule = Color(hex: 0x35513F, alpha: 0.22)
    static let ruleFirm = Color(hex: 0x35513F, alpha: 0.40)

    /// Hairlines drawn on the field ground.
    static let ruleOnField = Color(hex: 0xE9E5D9, alpha: 0.20)
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
