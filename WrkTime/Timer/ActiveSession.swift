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

    /// **What** was running, not just what it looked like.
    ///
    /// This carried only the routine, and the routine is a shape — a practice,
    /// a planned session and a saved timer routine are indistinguishable once
    /// they are one. So finishing a resumed run had nothing to go on and
    /// assumed today's planned session. Interrupt the morning practice, come
    /// back and finish it, and the app marked a *session* complete that she had
    /// never started, wrote it to Health, and recorded no practice — a mark on
    /// the growth form for work that did not happen, which is the one thing
    /// interrupted-session recovery must never do.
    ///
    /// Optional for the reason every stored field here is: this is JSON on
    /// disk, and the synthesized decoder throws on a missing non-optional key.
    /// A session written by the previous build decodes with nil, and nil means
    /// "unknown" rather than any particular kind.
    var kindRaw: String?
    /// Which planned session this is, when it is one.
    var sessionID: UUID?

    /// What a resumed run should be recorded as.
    enum Subject: Equatable {
        /// A planned session, named by id rather than by "whatever is today".
        case session(UUID)
        case practice
        /// A saved timer routine, which earns no mark and no practice row.
        case routine
        /// Written before this was recorded. Treated as a session for
        /// continuity with what the old build would have done, but only ever
        /// against today's session — never a practice, so the worst case is
        /// the old behaviour rather than a new one.
        case unknown
    }

    var subject: Subject {
        switch kindRaw {
        case "session": sessionID.map(Subject.session) ?? .unknown
        case "practice": .practice
        case "routine": .routine
        default: .unknown
        }
    }

    mutating func setSubject(_ subject: Subject) {
        switch subject {
        case .session(let id): kindRaw = "session"; sessionID = id
        case .practice: kindRaw = "practice"; sessionID = nil
        case .routine: kindRaw = "routine"; sessionID = nil
        case .unknown: kindRaw = nil; sessionID = nil
        }
    }

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
            // Ran out while the app was away. Naming the routine twice — the
            // card already shows its name — said nothing; how far it got is the
            // thing worth knowing.
            return "Finished while you were away · \(schedule.total.durationString)"
        }
        // Never `routine.rounds`: the practice is built with zero rounds, so
        // this read "Round 4 of 0", and a written-out sequence keeps its count
        // in `roundCount`. `position` also knows a flow movement is not a round.
        return schedule.phases[index]
            .position(rounds: routine.roundCount, flowCount: schedule.flowPhaseCount)
            + " · \(remaining.durationString) left"
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
