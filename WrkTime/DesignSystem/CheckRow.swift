import SwiftUI

/// A selectable row: a mark, a title, and what choosing it actually changes.
///
/// The app's one radio vocabulary. It carries the pace choice and the
/// aim-for-a-date switch on block setup, and whether a routine is a fixed shape
/// or a written-out sequence in the builder — one control rather than a switch
/// stacked above a list of buttons. A filled square is also the same
/// vocabulary as a mark on the growth form, where an iOS switch is borrowed
/// chrome belonging to a different document.
///
/// (`Toggle` works fine here — an earlier note in this file claimed otherwise
/// on the strength of a simulator tap that silently fails on `UISwitch`. Use
/// a drag, not a tap, when driving a switch from automation.)
struct CheckRow: View {
    let title: String
    var note: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Rule()
                HStack(alignment: .top, spacing: 12) {
                    Rectangle()
                        .fill(selected ? Palette.moss : Color.clear)
                        .frame(width: 9, height: 9)
                        .overlay { Rectangle().strokeBorder(Palette.moss.opacity(0.55), lineWidth: 1) }
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.almanacBody)
                            .foregroundStyle(Palette.ink)
                        if let note {
                            Text(note)
                                .font(.almanacBodySmall)
                                .foregroundStyle(Palette.mute)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(note ?? "")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
