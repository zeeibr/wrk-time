import Testing
import Foundation
import SwiftData
@testable import WrkTime

/// The two-writers defence.
///
/// CLAUDE.md names the bug this app keeps producing: *a side effect placed on
/// a path nobody exercises end to end, reporting success anyway.* Two devices
/// running the same code against the same synced store is the richest
/// possible source of it, and the failure would not look like a crash — it
/// would look like a workout she did once appearing twice on the growth form,
/// with both rows reporting success.
///
/// The whole defence is one rule: **a device records the session it started,
/// and no other.** Ownership travels in `ActiveSession.owner`, and the ending
/// path on both devices asks the same question before it writes anything.
/// These tests stand two stores and two links up side by side and check that
/// exactly one row exists, on the right device, in both directions.
@Suite("Ownership")
@MainActor
struct OwnershipTests {

    /// One device: its own store, its own end of the wire, and the ending
    /// path both real views implement.
    @MainActor
    final class Device {
        let role: DeviceRole
        let context: ModelContext
        let link: SessionLink
        /// Counts arriving from the other device, filed into the same
        /// dictionary this device's own stepper writes.
        var reps: [Int: Int] = [:]

        init(_ role: DeviceRole, link: SessionLink) throws {
            self.role = role
            self.link = link
            let container = try ModelContainer(
                for: Store.schema,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            context = ModelContext(container)
            link.onMessage = { [weak self] in self?.handle($0) }
        }

        /// The engine's `onEnded`, on this device.
        ///
        /// The guard is the defence. Without it both devices would write, and
        /// both would report having done so.
        func finished(_ session: ActiveSession, seconds: TimeInterval) {
            guard session.owner == role else { return }
            RoutineRuns.record(session.routine, source: .saved, seconds: seconds,
                               reps: countedReps(for: session), in: context)
            link.send(.ended(subjectID: session.sessionID, completed: true))
        }

        /// What arrives from the other device.
        func handle(_ message: SessionLinkMessage) {
            switch message {
            case .reps(let set, let count):
                reps[set] = count
            case .running, .ended, .transport, .whatIsRunning:
                // A mirror learns where the session is and what happened to
                // it. It writes nothing, ever.
                break
            }
        }

        private func countedReps(for session: ActiveSession) -> [Int] {
            guard !reps.isEmpty else { return [] }
            return (0..<session.routine.schedule.workPhaseCount).map { reps[$0] ?? 0 }
        }

        var runs: [RoutineRun] { RoutineRuns.all(in: context) }
    }

    private func devices() throws -> (phone: Device, watch: Device, pair: LinkPair) {
        let pair = LinkPair()
        return (try Device(.phone, link: pair.phone),
                try Device(.watch, link: pair.watch),
                pair)
    }

    private func routine() -> IntervalRoutine {
        IntervalRoutine(name: "Ownership", work: 40, rest: 20, rounds: 4,
                        moves: [MoveLibrary.all[0]])
    }

    private func session(owner: DeviceRole) -> ActiveSession {
        var session = ActiveSession(routine: routine(), startedAt: .now, elapsed: 0,
                                    running: true, savedAt: .now)
        session.setSubject(.routine)
        session.owner = owner
        return session
    }

    @Test("A watch-owned session is recorded on the watch and nowhere else")
    func watchOwned() throws {
        let (phone, watch, _) = try devices()
        let live = session(owner: .watch)

        // Both devices see the ending — the watch's engine ends it, and the
        // phone is told. Only one may write.
        watch.finished(live, seconds: 14 * 60)
        phone.finished(live, seconds: 14 * 60)

        #expect(watch.runs.count == 1)
        #expect(phone.runs.isEmpty)
        #expect(watch.runs.first?.name == "Ownership")
    }

    @Test("A phone-owned session is recorded on the phone and nowhere else")
    func phoneOwned() throws {
        let (phone, watch, _) = try devices()
        let live = session(owner: .phone)

        phone.finished(live, seconds: 14 * 60)
        watch.finished(live, seconds: 14 * 60)

        #expect(phone.runs.count == 1)
        #expect(watch.runs.isEmpty)
    }

    @Test("A session stored without an owner is the phone's, as every old one was")
    func legacyIsPhoneOwned() throws {
        let (phone, watch, _) = try devices()
        var live = session(owner: .phone)
        live.ownerRaw = nil

        watch.finished(live, seconds: 8 * 60)
        phone.finished(live, seconds: 8 * 60)

        #expect(phone.runs.count == 1)
        #expect(watch.runs.isEmpty)
    }

    @Test("A count made on the non-owner lands on the owner's one record")
    func countsTravelRatherThanForkTheRecord() throws {
        let (phone, watch, _) = try devices()
        let live = session(owner: .phone)

        // She counts on the wrist for a session her phone is running.
        watch.link.send(.reps(setOrdinal: 0, count: 10))
        watch.link.send(.reps(setOrdinal: 1, count: 9))
        #expect(phone.reps == [0: 10, 1: 9])
        // The watch filed nothing of its own on the way.
        #expect(watch.runs.isEmpty)

        phone.finished(live, seconds: 14 * 60)
        watch.finished(live, seconds: 14 * 60)

        #expect(phone.runs.count == 1)
        #expect(watch.runs.isEmpty)
        #expect(phone.runs.first?.repCounts == [10, 9, 0, 0])
    }
}
