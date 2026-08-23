import Foundation

/// The fact sheet the home-screen widget reads.
///
/// The widget runs in its own process and cannot open the store, so the app
/// writes this to the shared app group whenever it goes to background and
/// whenever a week is written — the two moments after which the widget could
/// otherwise be stale. It carries the whole week rather than just today, so
/// the midnight flip shows tomorrow's session without the app having been
/// opened.
struct TodaySnapshot: Codable {
    static let suite = "group.com.wrktime.app"
    static let key = "todaySnapshot"

    struct Day: Codable {
        var date: Date = .now
        /// Nil is a rest day, and a rest day is part of the plan.
        var title: String?
        var minutes: Int?
        var done: Bool = false
    }

    /// Today first, then the days after it.
    var days: [Day] = []
    /// Whether the morning practice was finished on the day this was written.
    /// Only meaningful for that day — the widget shows it fresh only then.
    var practiceDone: Bool = false
    var practiceMinutes: Int = 8
    var writtenOn: Date = .now
    var week: Int = 1
    var weekCount: Int = 12
    var marksThisWeek: Int = 0
    var marksTarget: Int = 4

    // MARK: - The session that is running

    /// The four facts a complication needs about a live session, and nothing
    /// more. Written by the watch, which is the only process that knows a
    /// session is running while the screen is off.
    ///
    /// Every one of them is Optional, and that is load-bearing twice over.
    /// This is JSON on disk and the synthesized decoder *throws* on a missing
    /// key, so a snapshot the phone wrote — it writes none of these — has to
    /// keep decoding. And nil is the honest reading of "nothing is running":
    /// the fields are cleared the moment the session ends, so a complication
    /// can never show a phase that finished an hour ago.
    var runningTitle: String?
    /// "Work", "Rest" or "Warm-up". The word the wrist reads, not a raw case.
    var runningPhase: String?
    /// When the current phase ends. Handed to the complication as a date so
    /// the *system* ticks the countdown — the same rule the Live Activity
    /// follows. Never a per-second timeline.
    var runningPhaseEnds: Date?
    /// When the whole session ends, on the schedule as written.
    var runningEnds: Date?

    /// Whether a session is running as far as this snapshot knows, judged
    /// against the clock rather than against the flag: a watch killed
    /// mid-session leaves the fields behind, and a phase that ended an hour
    /// ago is not a running session.
    func isRunning(at date: Date = .now) -> Bool {
        guard runningTitle != nil, let ends = runningEnds else { return false }
        return ends > date
    }

    func day(for date: Date, calendar: Calendar = .current) -> Day? {
        days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    static func load() -> TodaySnapshot? {
        guard let data = UserDefaults(suiteName: suite)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TodaySnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.suite)?.set(data, forKey: Self.key)
    }

    /// What the gallery preview shows — a plausible day, not her data.
    static var sample: TodaySnapshot {
        var snapshot = TodaySnapshot()
        snapshot.days = [Day(date: .now, title: "Full · mixed", minutes: 16)]
        snapshot.practiceDone = true
        snapshot.week = 2
        snapshot.marksThisWeek = 2
        snapshot.marksTarget = 4
        return snapshot
    }
}
