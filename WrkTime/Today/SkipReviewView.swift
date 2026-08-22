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

                    // One compact row of reasons per move, not five tall rows
                    // each. Eight skipped moves used to mean forty tappable
                    // rows — a form where a question was wanted. The stated
                    // consequence still appears, but only for the reason she
                    // picks: that is the moment it is a fact about her plan
                    // rather than five hypotheticals.
                    ForEach(Array(skipped.enumerated()), id: \.offset) { index, move in
                        IndexedSection(number: String(format: "%02d", index + 1), label: "Why") {
                            SectionHead(title: move, note: reasons[move] == nil ? nil : "Noted")
                                .padding(.bottom, 8)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                                      spacing: 8) {
                                ForEach(SkipReason.allCases) { reason in
                                    reasonChip(reason, for: move)
                                }
                            }

                            if let picked = reasons[move] {
                                Text(picked.consequence)
                                    .font(.almanacBodySmall)
                                    .foregroundStyle(Palette.moss)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 8)
                            }
                            Rule().padding(.top, 12)
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

    /// The library's chip dialect: squared, outlined, ink-filled when chosen.
    private func reasonChip(_ reason: SkipReason, for move: String) -> some View {
        let chosen = reasons[move] == reason
        return Button {
            reasons[move] = chosen ? nil : reason
        } label: {
            Text(reason.label)
                .font(.almanacBodySmall)
                .foregroundStyle(chosen ? Palette.oat : Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(chosen ? Palette.ink : Color.clear)
                .overlay(Rectangle().strokeBorder(chosen ? Palette.ink : Palette.ruleFirm,
                                                  lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reason.label)
        .accessibilityHint(reason.consequence)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }

    private func save() {
        for (move, reason) in reasons {
            MovePreferences.record(reason, for: move, in: context)
        }
        onFinish()
        dismiss()
    }
}

