import SwiftUI

// MARK: - Rules

/// A hairline. Always exactly one device pixel, never a 1pt box that renders
/// fat on 3x. `firm` is the rule under a section head; plain is between rows.
struct Rule: View {
    var firm = false
    @Environment(\.register) private var register
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(firm ? Palette.ruleFirm : register.rule)
            .frame(height: 1 / displayScale)
    }
}

// MARK: - Marginal index

/// The running index down the left margin — borrowed from Baseline, where it
/// numbered the sections of a printed document. Here it names what you're
/// looking at without spending a heading on it.
struct MarginalIndex: View {
    let number: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Text(number)
                .almanacLabel(Palette.mute, small: true)
                .tabular()
            Text(label)
                .almanacLabel(Palette.sage, small: true)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 12)
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
                Text(title).font(.almanacHeading).foregroundStyle(Palette.ink)
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
                Text(unit).almanacLabel(Palette.sage, small: true)
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
            }
            .foregroundStyle(Palette.oat)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Palette.ink)
        }
        .buttonStyle(.plain)
    }
}

/// A round control for the field register — pause, skip, end.
struct FieldButton: View {
    let systemName: String
    var prominent = false
    var label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: prominent ? 22 : 17, weight: .medium))
                .foregroundStyle(prominent ? Palette.field : Palette.oat)
                .frame(width: prominent ? 66 : 48, height: prominent ? 66 : 48)
                .background {
                    Circle()
                        .fill(prominent ? Palette.saffron : Color.clear)
                        .overlay {
                            Circle().strokeBorder(
                                prominent ? Color.clear : Palette.ruleOnField,
                                lineWidth: 1
                            )
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
                    .almanacLabel(Palette.sage, small: true)
                    .tabular()
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Palette.moss)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.almanacBody).foregroundStyle(Palette.ink)
                    Text(equipment).almanacLabel(Palette.sage, small: true)
                }
                Spacer(minLength: 8)
                Text(measure).almanacLabel(Palette.mute).tabular()
            }
            .padding(.vertical, 7)
        }
    }
}
