import Foundation

/// The last fortnight of recovery readings, one per day.
///
/// The app reads a `RecoverySnapshot` when Today or Signals opens and
/// kept none of them, so "red for three days" — the brief's reason to
/// withhold a step-up (§10) — could not be asked. This is the smallest
/// honest record of it: the guidance per calendar day, written whenever a
/// reading is taken, in `UserDefaults` because it is fourteen strings and
/// not a thing to sync or back up.
///
/// A day with no reading is not a red day. Missing data holds the plan as
/// written; it never counts against her.
enum RecoveryLog {
    static let key = "recoveryLogByDay"
    static let keptDays = 14

    /// Records today's reading. Later readings on the same day replace
    /// earlier ones — the evening's numbers are no truer than the morning's,
    /// but they are the latest.
    static func record(_ guidance: RecoverySnapshot.Guidance, on date: Date = .now,
                       defaults: UserDefaults = .standard) {
        var table = load(defaults)
        table[dayKey(date)] = label(guidance)
        let cutoff = Calendar.current.date(byAdding: .day, value: -keptDays, to: date)!
        table = table.filter { $0.key >= dayKey(cutoff) }
        defaults.set(table, forKey: key)
    }

    /// How many consecutive days, ending today, have read "ease". A day
    /// with no reading ends the streak.
    static func easeStreak(endingOn date: Date = .now,
                           defaults: UserDefaults = .standard) -> Int {
        let table = load(defaults)
        var streak = 0
        var day = date
        while table[dayKey(day)] == label(.ease) {
            streak += 1
            day = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    /// The brief's threshold.
    static let withholdAfterDays = 3
    static func isWithholding(on date: Date = .now, defaults: UserDefaults = .standard) -> Bool {
        easeStreak(endingOn: date, defaults: defaults) >= withholdAfterDays
    }

    private static func load(_ defaults: UserDefaults) -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func label(_ guidance: RecoverySnapshot.Guidance) -> String {
        switch guidance {
        case .hold: "hold"
        case .ease: "ease"
        case .push: "push"
        }
    }
}
