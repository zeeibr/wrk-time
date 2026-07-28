import SwiftData
import SwiftUI

/// Where the eating window is actually set.
///
/// It did not exist. `FastWindow` was seeded once with a default window and a
/// last bite of "now", and nothing could ever change either — so the fasting
/// figure on Today counted up from an event that never happened, and the window
/// passed to the planner was an assumption nobody had made.
///
/// The screen holds the app's line on fasting: it records what you tell it and
/// hands it to the plan as one input among several. There is no streak, no
/// target, and no encouragement to extend anything.
struct EatingWindowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var windows: [FastWindow]

    @State private var lastBite = Date.now
    @State private var opens = Date.now
    @State private var closes = Date.now
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Masthead(context: "Window")
                        .padding(.top, 4)

                    IndexedSection(number: "01", label: "Last") {
                        SectionHead(title: "Last bite", note: elapsedNote)
                            .padding(.bottom, 10)

                        DatePicker("Last bite", selection: $lastBite,
                                   in: ...Date.now,
                                   displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                            .font(.almanacBody)
                            .tint(Palette.moss)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            lastBite = .now
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Just now")
                                    .font(.almanacBody)
                                Spacer()
                            }
                            .foregroundStyle(Palette.moss)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Rule()

                        Text("The clock on Today counts from here. It is a record of when you last ate, not a target to beat.")
                            .font(.almanacBodySmall)
                            .foregroundStyle(Palette.mute)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                    }

                    IndexedSection(number: "02", label: "Window") {
                        SectionHead(title: "When you eat", note: windowNote)
                            .padding(.bottom, 6)

                        TimeRow(label: "Opens", time: $opens)
                        TimeRow(label: "Closes", time: $closes)
                        Rule()

                        Text("Passed to the planner alongside sleep and attendance. It never changes what the sessions are — the plan does not train you differently because of when you eat.")
                            .font(.almanacBodySmall)
                            .foregroundStyle(Palette.mute)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 12)
                    }

                    PrimaryButton(title: "Save", subtitle: nil) { save() }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Palette.oat.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.mute)
                }
            }
        }
        .task { load() }
    }

    // MARK: - State

    private var window: FastWindow? { windows.first }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let window else { return }
        lastBite = window.lastBite
        opens = time(hour: window.windowOpensHour, minute: window.windowOpensMinute)
        closes = time(hour: window.windowClosesHour, minute: window.windowClosesMinute)
    }

    private func time(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    private var elapsedNote: String {
        let seconds = Int(Date.now.timeIntervalSince(lastBite))
        guard seconds > 0 else { return "Now" }
        return "\(seconds / 3600)h \(String(format: "%02d", (seconds % 3600) / 60))m"
    }

    /// States the length of the window, because that is the number she is
    /// actually choosing when she moves either end.
    private var windowNote: String {
        let calendar = Calendar.current
        let open = calendar.dateComponents([.hour, .minute], from: opens)
        let close = calendar.dateComponents([.hour, .minute], from: closes)
        let openMinutes = (open.hour ?? 0) * 60 + (open.minute ?? 0)
        let closeMinutes = (close.hour ?? 0) * 60 + (close.minute ?? 0)
        // A window that closes before it opens has crossed midnight rather than
        // become negative.
        let length = closeMinutes >= openMinutes
            ? closeMinutes - openMinutes
            : (24 * 60) - openMinutes + closeMinutes
        return "\(length / 60)h \(String(format: "%02d", length % 60))m"
    }

    private func save() {
        let calendar = Calendar.current
        let open = calendar.dateComponents([.hour, .minute], from: opens)
        let close = calendar.dateComponents([.hour, .minute], from: closes)

        let target = window ?? {
            let created = FastWindow()
            context.insert(created)
            return created
        }()

        target.lastBite = lastBite
        target.windowOpensHour = open.hour ?? 12
        target.windowOpensMinute = open.minute ?? 30
        target.windowClosesHour = close.hour ?? 20
        target.windowClosesMinute = close.minute ?? 30

        dismiss()
    }
}

private struct TimeRow: View {
    let label: String
    @Binding var time: Date

    var body: some View {
        VStack(spacing: 0) {
            Rule()
            HStack {
                Text(label)
                    .font(.almanacBody)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                DatePicker(label, selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(Palette.moss)
            }
            .padding(.vertical, 9)
        }
    }
}
