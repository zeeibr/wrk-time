import SwiftUI

// MARK: - Rules

/// A hairline. Always exactly one device pixel, never a 1pt box that renders
/// fat on 3x. `firm` is the rule under a section head; plain is between rows.
struct Rule: View {
    var firm = false
    @Environment(\.register) private var register
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(colour)
            // A hairline stays a hairline; under Increase Contrast it darkens
            // rather than thickens, so the document keeps its weight.
            .frame(height: 1 / displayScale)
    }

    private var colour: Color {
        let increased = contrast == .increased
        if register == .field { return Palette.ruleOnField(increased: increased) }
        return firm ? Palette.ruleFirm(increased: increased)
                    : Palette.rule(increased: increased)
    }
}

// MARK: - Masthead

/// The running head every document screen opens with.
///
/// This is the wordmark, and it is deliberately not a logotype: an almanac
/// identifies itself the way a printed one does, with a masthead and a running
/// head on every page. The rule is part of it — the word never appears alone.
/// The right-hand side always states position in the block, because that is
/// what the reader wants to know before anything else on the page.
struct Masthead: View {
    var context: String?
    /// An optional control at the end of the running head. Today uses it for
    /// the way into settings — the one place in the app that needs a door, and
    /// a place a masthead can carry one without growing furniture.
    var onSettings: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Almanac")
                    .font(Face.mono(11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(3.1)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let context {
                    Text(context)
                        .font(Face.mono(11))
                        .textCase(.uppercase)
                        .tracking(1.3)
                        .foregroundStyle(Palette.mute)
                        .tabular()
                }
                if let onSettings {
                    Button(action: onSettings) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.mute)
                            .contentShape(Rectangle().inset(by: -12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                }
            }
            Rule(firm: true)
        }
    }
}

// MARK: - Marginal index

/// The running index down the left margin — borrowed from Baseline, where it
/// numbered the sections of a printed document. Here it names what you're
/// looking at without spending a heading on it.
struct MarginalIndex: View {
    let number: String
    let label: String

    /// A rotated label's height is the *unrotated* text's width, and only the
    /// layout system knows that. `rotationEffect` is a visual transform: it
    /// leaves the reserved bounds unrotated, so without measuring and swapping
    /// the axes the label draws back up over the number above it.
    @State private var labelLength: CGFloat = 0

    var body: some View {
        VStack(spacing: 8) {
            Text(number)
                .almanacLabel(Palette.mute, small: true)
                .tabular()
            Text(label)
                .almanacLabel(Palette.mute, small: true)
                .fixedSize()
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .task(id: proxy.size.width) { labelLength = proxy.size.width }
                    }
                }
                .rotationEffect(.degrees(-90))
                .frame(width: 12, height: labelLength)
        }
        .frame(width: 18, alignment: .top)
    }
}

/// A section of a document screen: marginal index on the left, content right.
struct IndexedSection<Content: View>: View {
    let number: String
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MarginalIndex(number: number, label: label)
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A section head: a slab title on the left, a mono note on the right, and a
/// firm rule under both.
struct SectionHead: View {
    let title: String
    var note: String?

    var body: some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.almanacHeading)
                    .foregroundStyle(Palette.ink)
                    // Without this the VoiceOver Headings rotor — the way a
                    // screen-reader user skims a long document screen — is
                    // empty on every screen in the app.
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let note {
                    Text(note).almanacLabel().tabular()
                }
            }
            Rule(firm: true)
        }
    }
}

// MARK: - Stats

/// A figure with its unit set apart in mono, so numbers stay comparable down a
/// column and units never compete with them.
struct Figure: View {
    let value: String
    var unit: String?
    var size: CGFloat = 26
    var color: Color = Palette.ink

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(Face.ui(size, weight: .regular))
                .tabular()
                .foregroundStyle(color)
            if let unit {
                Text(unit).almanacLabel(Palette.mute, small: true)
            }
        }
    }
}

/// A labelled cell — the unit of the stat rows on Today and Progress.
struct StatCell: View {
    let label: String
    let value: String
    var unit: String?
    var emphasis: Color = Palette.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).almanacLabel(small: true)
            Figure(value: value, unit: unit, size: 22, color: emphasis)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Controls

/// The one filled control per screen. Ink on oat in the document register,
/// because saffron is reserved for a live round and must never be spent on a
/// button that isn't running yet.
struct PrimaryButton: View {
    let title: String
    var subtitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.almanacButton)
                    if let subtitle {
                        Text(subtitle)
                            .font(.almanacLabelSmall)
                            .tracking(1.4)
                            .textCase(.uppercase)
                            .opacity(0.72)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .medium))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Palette.oat)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Palette.ink)
        }
        .buttonStyle(.plain)
        // The subtitle is a tracked, uppercased mono string ("8 ROUNDS · 13:15")
        // that reads badly aloud, and the arrow is decoration. Say the title,
        // then the detail, in that order.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle ?? "")
        .accessibilityAddTraits(.isButton)
    }
}

/// A round control for the field register — pause, skip, end.
struct FieldButton: View {
    let systemName: String
    var prominent = false
    var label: String
    /// The register's primary colour. This control is drawn in both layers of
    /// the knockout, so it cannot assume the dark ground — hard-coding oat here
    /// rendered it oat-on-oat, and invisible, wherever the field had drained
    /// past it.
    var foreground: Color = Palette.oat
    let action: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    /// This ring is a control boundary, not decoration, so Increase Contrast
    /// has to reach it — at the design alpha it is 1.74:1 against the field.
    private var edgeOpacity: Double {
        let increased = contrast == .increased
        if prominent { return increased ? 0.55 : 0.25 }
        return increased ? 0.80 : 0.45
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: prominent ? 22 : 17, weight: .medium))
                .foregroundStyle(prominent ? Palette.field : foreground)
                .frame(width: prominent ? 66 : 48, height: prominent ? 66 : 48)
                .background {
                    Circle()
                        .fill(prominent ? Palette.saffron : Color.clear)
                        .overlay {
                            Circle().strokeBorder(foreground.opacity(edgeOpacity),
                                                  lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Rows

/// One block of a session: index, glyph, name, equipment, trailing measure.
struct BlockRow: View {
    let index: Int
    let symbol: String
    let name: String
    let equipment: String
    let measure: String

    var body: some View {
        VStack(spacing: 0) {
            Rule()
            HStack(spacing: 9) {
                Text(String(format: "%02d", index))
                    .almanacLabel(Palette.mute, small: true)
                    .tabular()
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Palette.moss)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.almanacBody).foregroundStyle(Palette.ink)
                    Text(equipment).almanacLabel(Palette.mute, small: true)
                }
                Spacer(minLength: 8)
                Text(measure).almanacLabel(Palette.mute).tabular()
            }
            .padding(.vertical, 7)
        }
        // One row, one announcement. Left alone VoiceOver reads five separate
        // elements per move — including the raw SF Symbol name — so three
        // exercises cost fifteen swipes of mostly noise.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(index). \(name), \(equipment), \(measure)")
    }
}
