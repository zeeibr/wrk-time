import SwiftData
import SwiftUI

/// Asks why something got skipped, once, after the session is over.
///
/// **After, never during.** Interrupting a workout to ask how she feels about
/// a movement would be the app talking during the one part of the app that is
/// supposed to be quiet. The field register exists to be left alone.
///
/// Every option maps to a stated consequence, shown next to it, because a
/// question that silently rewrites the plan is worse than no question. Two of
/// the five deliberately change nothing: running out of time says nothing about
/// the move, and the app should not pretend otherwise by quietly demoting it.
///
/// Nothing here implies she failed. A skip is information — it is the most
/// useful thing a session produces, and the plan is better for having it.
struct SkipReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let skipped: [String]
    var onFinish: () -> Void = {}

    @State private var reasons: [String: SkipReason] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Masthead(context: "Session")
                        .padding(.top, 4)

                    Text(headline)
                        .font(.almanacTitle)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text("Knowing why is what lets next week be different. Skipping something is information, not a failure.")
                        .font(.almanacBody)
                        .foregroundStyle(Palette.mute)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(Array(skipped.enumerated()), id: \.offset) { index, move in
                        IndexedSection(number: String(format: "%02d", index + 1), label: "Why") {
                            SectionHead(title: move, note: reasons[move] == nil ? nil : "Noted")
                                .padding(.bottom, 4)

                            ForEach(SkipReason.allCases) { reason in
                                ReasonRow(reason: reason,
                                          selected: reasons[move] == reason) {
                                    reasons[move] = reason
                                }
                            }
                            Rule()
                        }
                    }

                    PrimaryButton(title: answeredAll ? "Save" : "Skip this",
                                  subtitle: nil) { save() }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Palette.oat.ignoresSafeArea())
        }
        // She has already finished a workout. Being trapped in a form is not
        // the reward for that, so the sheet is dismissible and answering is
        // optional — hence the button reading "Skip this" until it is not.
        .interactiveDismissDisabled(false)
    }

    private var headline: String {
        skipped.count == 1
            ? "You skipped one thing."
            : "You skipped \(skipped.count) things."
    }

    private var answeredAll: Bool {
        !skipped.isEmpty && skipped.allSatisfy { reasons[$0] != nil }
    }

    private func save() {
        for (move, reason) in reasons {
            MovePreferences.record(reason, for: move, in: context)
        }
        onFinish()
        dismiss()
    }
}

/// One reason, with what it will do stated beside it.
private struct ReasonRow: View {
    let reason: SkipReason
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
                        Text(reason.label)
                            .font(.almanacBody)
                            .foregroundStyle(Palette.ink)
                        Text(reason.consequence)
                            .font(.almanacBodySmall)
                            .foregroundStyle(selected ? Palette.moss : Palette.mute)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reason.label)
        .accessibilityValue(reason.consequence)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
