import Testing
import Foundation
@testable import WrkTime

// MARK: - Two devices in one process

/// One end of the wire, with the three delivery guarantees stood up in
/// memory.
///
/// `sendLive` reaches the counterpart only while reachable — live or nothing,
/// as `sendMessage` is. `queue` holds until the counterpart is next running,
/// as `transferUserInfo` does. `publishContext` keeps one latest snapshot,
/// newer replacing older, as `updateApplicationContext` does. `flush` is the
/// counterpart waking up.
@MainActor
final class LoopbackTransport: LinkTransport {
    var onReceive: ((Data) -> Void)?
    weak var counterpart: LoopbackTransport?
    var reachable = true

    /// Waiting for the counterpart to run again.
    private(set) var queued: [Data] = []
    /// The one latest snapshot.
    private(set) var context: Data?
    /// Everything that went out live, whether or not it landed.
    private(set) var liveSent: [Data] = []

    var isReachable: Bool { reachable }

    func sendLive(_ data: Data) {
        liveSent.append(data)
        guard reachable else { return }
        counterpart?.onReceive?(data)
    }

    func queue(_ data: Data) { queued.append(data) }

    func publishContext(_ data: Data) { context = data }

    /// The counterpart woke up: everything held goes over, oldest first, and
    /// then the latest snapshot.
    func flush() {
        let held = queued
        queued = []
        for data in held { counterpart?.onReceive?(data) }
        if let context { counterpart?.onReceive?(context) }
    }
}

/// A phone and a watch, wired back to back.
@MainActor
final class LinkPair {
    let phoneSide = LoopbackTransport()
    let watchSide = LoopbackTransport()
    let phone: SessionLink
    let watch: SessionLink

    init(now: @escaping () -> Date = Date.init) {
        phoneSide.counterpart = watchSide
        watchSide.counterpart = phoneSide
        phone = SessionLink(transport: phoneSide, now: now)
        watch = SessionLink(transport: watchSide, now: now)
    }

    /// Out of range, both ways — reachability is a property of the pair.
    func disconnect() {
        phoneSide.reachable = false
        watchSide.reachable = false
    }

    /// Back in range: what was held is delivered.
    func reconnect() {
        phoneSide.reachable = true
        watchSide.reachable = true
        phoneSide.flush()
        watchSide.flush()
    }
}

// MARK: - Fixtures

@MainActor
private func named(_ name: String) -> Move {
    MoveLibrary.all.first { $0.name == name } ?? MoveLibrary.all[0]
}

@MainActor
private func intervals() -> IntervalRoutine {
    IntervalRoutine(name: "Link", work: 60, rest: 45, rounds: 3,
                    moves: [named("Beam front squat"), named("Ring row")])
}

/// A sets session: every work phase is an open set she ends.
@MainActor
private func sets() -> IntervalRoutine {
    IntervalRoutine(name: "Sets", work: 40, rest: 20, rounds: 0,
                    moves: [named("Kettlebell deadlift"), named("Dead bug")])
        .inMode(.reps, sets: 3)
}

/// The snapshot the owner would persist and announce at this instant.
@MainActor
private func snapshot(_ routine: IntervalRoutine, engine: IntervalEngine,
                      at now: Date, owner: DeviceRole = .phone,
                      running: Bool = true) -> ActiveSession {
    var session = ActiveSession(routine: routine,
                                startedAt: now.addingTimeInterval(-engine.elapsed),
                                elapsed: engine.elapsed,
                                running: running,
                                savedAt: now)
    session.owner = owner
    return session
}

// MARK: - Tests

@Suite("Session link")
@MainActor
struct SessionLinkTests {

    @Test("A running snapshot puts the mirror at the owner's phase and elapsed")
    func mirrorsTheOwner() throws {
        let clock = TestClock()
        let pair = LinkPair(now: clock.provider)
        let routine = intervals()

        let owner = IntervalEngine(routine: routine, now: clock.provider, autoTick: false)
        owner.start()
        clock.advance(95)          // 60 s of work, then 35 s into the rest
        owner.refresh()

        var received: ActiveSession?
        pair.watch.onMessage = { if case .running(let session, _) = $0 { received = session } }
        pair.phone.send(.running(snapshot(routine, engine: owner, at: clock.now), owner: .phone))

        let mirrored = try #require(received)
        #expect(mirrored.owner == .phone)

        let mirror = IntervalEngine(routine: mirrored.routine, now: clock.provider, autoTick: false)
        mirror.restore(to: mirrored.elapsedNow(clock.now), running: mirrored.running)

        #expect(mirror.currentIndex == owner.currentIndex)
        #expect(mirror.currentPhase?.isRest == true)
        #expect(abs(mirror.elapsed - owner.elapsed) < 0.001)
    }

    @Test("The snapshot is published as context as well as sent live")
    func contextAlwaysPublished() {
        let clock = TestClock()
        let pair = LinkPair(now: clock.provider)
        let routine = intervals()
        let owner = IntervalEngine(routine: routine, now: clock.provider, autoTick: false)
        owner.start()

        pair.phone.send(.running(snapshot(routine, engine: owner, at: clock.now), owner: .phone))
        #expect(pair.phoneSide.context != nil)
        #expect(pair.phoneSide.liveSent.count == 1)

        // Out of range there is nothing live to send, but the snapshot is
        // still the thing a watch reads when it wakes.
        pair.disconnect()
        clock.advance(30)
        owner.refresh()
        pair.phone.send(.running(snapshot(routine, engine: owner, at: clock.now), owner: .phone))
        #expect(pair.phoneSide.liveSent.count == 1)
        #expect(pair.phoneSide.context != nil)
    }

    @Test("A count made on the non-owner lands in the owner's counts")
    func repsReachTheOwner() {
        let pair = LinkPair()
        // Stands for `WorkoutTimerView.reps` — the same dictionary its own
        // stepper writes, which is the whole point: one place files a count.
        var counts: [Int: Int] = [:]
        pair.phone.onMessage = {
            if case .reps(let set, let count) = $0 { counts[set] = count }
        }

        pair.watch.send(.reps(setOrdinal: 2, count: 11))
        #expect(counts == [2: 11])
    }

    @Test("A count made out of range is queued and arrives on reconnect")
    func repsSurviveTheRange() {
        let pair = LinkPair()
        var counts: [Int: Int] = [:]
        pair.phone.onMessage = {
            if case .reps(let set, let count) = $0 { counts[set] = count }
        }

        pair.disconnect()
        pair.watch.send(.reps(setOrdinal: 1, count: 9))
        #expect(counts.isEmpty)
        #expect(pair.watchSide.queued.count == 1)
        #expect(pair.watchSide.liveSent.isEmpty)

        pair.reconnect()
        #expect(counts == [1: 9])
        #expect(pair.watchSide.queued.isEmpty)
    }

    @Test("A snapshot that went stale on the way is dropped, not mirrored")
    func staleRunningIsDropped() {
        let clock = TestClock()
        let pair = LinkPair(now: clock.provider)
        let routine = intervals()
        let owner = IntervalEngine(routine: routine, now: clock.provider, autoTick: false)
        owner.start()
        clock.advance(40)
        owner.refresh()

        // Paused, so the clock cannot also have run out — this is a test
        // about age alone.
        let session = snapshot(routine, engine: owner, at: clock.now, running: false)

        var seen: [SessionLinkMessage] = []
        pair.watch.onMessage = { seen.append($0) }

        clock.advance(ActiveSession.staleAfter + 60)
        pair.phone.send(.running(session, owner: .phone))
        #expect(seen.isEmpty)

        // And the live one is not dropped, so the rule is age and nothing else.
        pair.phone.send(.running(snapshot(routine, engine: owner, at: clock.now), owner: .phone))
        #expect(seen.count == 1)
    }

    @Test("Ending a set from the wrist advances the owner into the rest")
    func endSetFromTheOtherDevice() throws {
        let clock = TestClock()
        let pair = LinkPair(now: clock.provider)
        let routine = sets()
        let owner = IntervalEngine(routine: routine, now: clock.provider, autoTick: false)

        // The owner's handler, doing exactly what the local Done button does.
        pair.phone.onMessage = {
            if case .transport(.endSet) = $0 { owner.endSet() }
        }

        owner.start()
        clock.advance(30)
        owner.refresh()
        #expect(owner.currentPhase?.openEnded == true)
        let openSet = try #require(owner.currentIndex)

        pair.watch.send(.transport(.endSet))

        #expect(owner.currentPhase?.isRest == true)
        #expect(owner.currentIndex == openSet + 1)
        #expect(owner.elapsed > 30)
        // A set she ended is a set she did, and its real length is kept.
        #expect(owner.setDurations[0] == 30)

        // The next snapshot carries the advanced clock, so the wrist sees the
        // rest it just asked for.
        var received: ActiveSession?
        pair.watch.onMessage = { if case .running(let session, _) = $0 { received = session } }
        pair.phone.send(.running(snapshot(routine, engine: owner, at: clock.now), owner: .phone))

        let mirrored = try #require(received)
        #expect(mirrored.elapsed == owner.elapsed)
        let mirror = IntervalEngine(routine: mirrored.routine, now: clock.provider, autoTick: false)
        mirror.restore(to: mirrored.elapsedNow(clock.now), running: mirrored.running)
        #expect(mirror.currentPhase?.isRest == true)
    }

    @Test("Transport actions all reach the owner's engine")
    func transportActions() {
        let clock = TestClock()
        let pair = LinkPair(now: clock.provider)
        let routine = intervals()
        let owner = IntervalEngine(routine: routine, now: clock.provider, autoTick: false)
        pair.phone.onMessage = {
            guard case .transport(let action) = $0 else { return }
            switch action {
            case .pause: owner.pause()
            case .resume: owner.resume()
            case .skip: owner.skip()
            case .endSet: owner.endSet()
            case .end: owner.end(reason: .abandoned)
            }
        }

        owner.start()
        pair.watch.send(.transport(.pause))
        #expect(owner.status == .paused)
        pair.watch.send(.transport(.resume))
        #expect(owner.status == .running)
        pair.watch.send(.transport(.skip))
        #expect(owner.currentPhase?.isRest == true)
        pair.watch.send(.transport(.end))
        #expect(owner.status == .finished)
        #expect(owner.endReason == .abandoned)
    }

    @Test("The link knows a session is over, so a late count can be dropped")
    func liveUntilEnded() {
        let clock = TestClock()
        let pair = LinkPair(now: clock.provider)
        let routine = intervals()
        let owner = IntervalEngine(routine: routine, now: clock.provider, autoTick: false)
        owner.start()

        #expect(pair.watch.isLive == false)
        pair.phone.send(.running(snapshot(routine, engine: owner, at: clock.now), owner: .phone))
        #expect(pair.watch.isLive)
        #expect(pair.watch.announced?.owner == .phone)
        // The owner stops believing it too, on the way out.
        #expect(pair.phone.isLive)

        pair.phone.send(.ended(subjectID: nil, completed: true))
        #expect(pair.watch.isLive == false)
        #expect(pair.phone.isLive == false)

        // The message still arrives in order; dropping it is the consumer's
        // decision, made against `isLive`, not something the wire guesses.
        var late: [SessionLinkMessage] = []
        pair.phone.onMessage = { late.append($0) }
        pair.watch.send(.reps(setOrdinal: 0, count: 8))
        #expect(late == [.reps(setOrdinal: 0, count: 8)])
        #expect(pair.phone.isLive == false)
    }

    @Test("An asked-for answer only goes live; it is never queued")
    func questionsAreNotQueued() {
        let pair = LinkPair()
        pair.disconnect()
        pair.watch.send(.whatIsRunning)
        #expect(pair.watchSide.queued.isEmpty)

        // And the ending is queued as well as sent, because missing it leaves
        // a mirror counting down a workout that is over.
        pair.phone.send(.ended(subjectID: nil, completed: false))
        #expect(pair.phoneSide.queued.count == 1)
    }

    @Test("A session stored before the watch existed is phone-owned")
    func legacySessionsArePhoneOwned() throws {
        let routine = intervals()
        var session = ActiveSession(routine: routine, startedAt: .now, elapsed: 30,
                                    running: true, savedAt: .now)
        session.owner = .watch

        let data = try JSONEncoder().encode(session)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["ownerRaw"] as? String == "watch")

        // Exactly what every session on disk today looks like: no such key.
        object.removeValue(forKey: "ownerRaw")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(ActiveSession.self, from: legacy)

        #expect(decoded.ownerRaw == nil)
        #expect(decoded.owner == .phone)
    }

    @Test("A device with nothing to talk to sends into the void without throwing")
    func disconnectedIsHarmless() {
        let link = SessionLink(transport: DisconnectedTransport())
        var seen = 0
        link.onMessage = { _ in seen += 1 }
        link.send(.whatIsRunning)
        link.send(.reps(setOrdinal: 0, count: 5))
        link.send(.ended(subjectID: nil, completed: true))
        #expect(seen == 0)
    }
}
