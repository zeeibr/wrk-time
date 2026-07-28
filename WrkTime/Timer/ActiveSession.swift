import Foundation

/// A session that was running when the app stopped.
///
/// Without this, a phone call, a low-memory kill, or a swipe out of the app
/// switcher mid-workout loses the session outright — no record, no resume, and
/// no mark. That was demonstrably the behaviour: a session at round one of
/// eight with ten minutes left came back as an untouched Today screen.
///
/// The engine derives progress from wall-clock time against a fixed schedule,
/// so restoring one is genuinely cheap: keep the routine and how far in she
/// was, and the clock does the rest — including the minutes that passed while
/// the app was dead, which is the honest reading. She was not resting for
/// those; the workout simply carried on without a screen.
struct ActiveSession: Codable, Equatable, Sendable {
    var routine: IntervalRoutine
    /// When the session actually began, kept so a resumed session still writes
    /// truthful bounds to Health.
    var startedAt: Date
    /// Elapsed within the routine at the moment this was written.
    var elapsed: TimeInterval
    var running: Bool
    var savedAt: Date

    /// A session nobody came back to inside this window is not resumed. Coming
    /// back to a workout you abandoned two hours ago is starting a new one, and
    /// silently counting it would put a mark on the form that was not earned.
    static let staleAfter: TimeInterval = 2 * 3600

    /// Where the routine is *now*, counting the time the app was not running.
    func elapsedNow(_ now: Date = .now) -> TimeInterval {
        guard running else { return elapsed }
        return elapsed + now.timeIntervalSince(savedAt)
    }

    func isStale(_ now: Date = .now) -> Bool {
        now.timeIntervalSince(savedAt) > Self.staleAfter
    }

    /// True once the clock has run past the end while the app was away. The
    /// session is offered as finished-in-absentia rather than resumed, because
    /// there is nothing left to run.
    func ranOut(_ now: Date = .now) -> Bool {
        elapsedNow(now) >= routine.schedule.total
    }

    /// "Round 3 of 8, 6:12 left" — enough to recognise what you walked away
    /// from before deciding whether to pick it up.
    func summary(_ now: Date = .now) -> String {
        let schedule = routine.schedule
        let at = min(elapsedNow(now), schedule.total)
        let remaining = max(schedule.total - at, 0)
        guard let index = schedule.index(atElapsed: at) else {
            return routine.name
        }
        let round = schedule.phases[index].round
        return "Round \(round) of \(routine.rounds) · \(remaining.durationString) left"
    }
}

/// Where the in-flight session is kept.
///
/// `UserDefaults` rather than the SwiftData store on purpose: this is transient
/// process state, not part of the record. A session only becomes part of the
/// record by finishing, and writing an in-progress one into the synced store
/// would put a half-done workout on her other devices.
enum ActiveSessionStore {
    static let key = "activeSession"

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func save(_ session: ActiveSession) {
        guard let data = try? encoder.encode(session) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Returns the stored session, discarding it if it has gone stale.
    static func load(_ now: Date = .now) -> ActiveSession? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let session = try? decoder.decode(ActiveSession.self, from: data)
        else { return nil }

        // A session whose clock ran out while the app was gone is dropped
        // rather than offered. There is nothing left to run, and the one thing
        // the app must not do is decide on her behalf that she finished it —
        // a mark is a session seen through, and inventing one would make the
        // growth form a record of guesses.
        guard !session.isStale(now), !session.ranOut(now) else {
            clear()
            return nil
        }
        return session
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
