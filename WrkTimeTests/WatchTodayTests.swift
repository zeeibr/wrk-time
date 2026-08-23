import Foundation
import SwiftData
import Testing
@testable import WrkTime

/// What the wrist offers when today's own session is not the question.
///
/// The selection itself is `TodayView.offeredSession` — a computed property on
/// a view, so until now it could only be checked by building the view. The
/// watch needs the same answer, and two spellings of one question is the shape
/// this app has produced four times. `DayOffer.next` is the one spelling, and
/// these pin it to the behaviour the phone shipped.
@Suite("What the day still offers")
struct WatchTodayTests {

    private func store() throws -> ModelContext {
        let container = try ModelContainer(
            for: PlannedSession.self, Block.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private let today = Calendar.current.startOfDay(for: Date(timeIntervalSinceReferenceDate: 800_000_000))
    private var weekStart: Date {
        Calendar.current.date(byAdding: .day, value: -3, to: today)!
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: today)!
    }

    @discardableResult
    private func session(_ context: ModelContext, _ offset: Int,
                         done: Bool = false) -> PlannedSession {
        let row = PlannedSession(scheduledFor: day(offset), title: "Day \(offset)",
                                 routine: IntervalRoutine(name: "Day \(offset)", work: 40,
                                                          rest: 20, rounds: 6, moves: []))
        if done { row.completedAt = day(offset) }
        context.insert(row)
        return row
    }

    private func all(_ context: ModelContext) -> [PlannedSession] {
        (try? context.fetch(FetchDescriptor<PlannedSession>())) ?? []
    }

    // MARK: - The rule

    @Test("A session missed this week beats the next one early")
    func missedBeatsEarly() throws {
        let context = try store()
        session(context, -1)              // missed yesterday
        session(context, 1)               // tomorrow's, written
        let offer = DayOffer.next(from: all(context), weekStart: weekStart, today: today)
        #expect(offer?.kind == .missed)
        #expect(offer?.session.scheduledFor == day(-1))
    }

    @Test("The most recent missed session is the one offered")
    func mostRecentMissed() throws {
        let context = try store()
        session(context, -3)
        session(context, -1)
        session(context, -2)
        let offer = DayOffer.next(from: all(context), weekStart: weekStart, today: today)
        #expect(offer?.kind == .missed)
        #expect(offer?.session.scheduledFor == day(-1))
    }

    @Test("With nothing missed, the next one is offered early")
    func nextEarly() throws {
        let context = try store()
        session(context, -1, done: true)
        session(context, 2)
        session(context, 1)
        let offer = DayOffer.next(from: all(context), weekStart: weekStart, today: today)
        #expect(offer?.kind == .early)
        #expect(offer?.session.scheduledFor == day(1))
    }

    @Test("Nothing is offered when the week is done and nothing lies ahead")
    func nothingLeft() throws {
        let context = try store()
        session(context, -2, done: true)
        session(context, -1, done: true)
        let offer = DayOffer.next(from: all(context), weekStart: weekStart, today: today)
        #expect(offer == nil)
    }

    @Test("A session missed before this week's start is last week's, and stays there")
    func lastWeekIsNotOffered() throws {
        let context = try store()
        session(context, -5)              // before weekStart at -3
        let offer = DayOffer.next(from: all(context), weekStart: weekStart, today: today)
        #expect(offer == nil)
    }

    @Test("Today's own session is neither missed nor early — the caller shows it")
    func todayIsNotAnOffer() throws {
        let context = try store()
        session(context, 0)
        let offer = DayOffer.next(from: all(context), weekStart: weekStart, today: today)
        #expect(offer == nil)
    }

    // MARK: - What finished today

    @Test("The session today was written for wins a day that holds two")
    func finishedTodayPrefersToday() throws {
        let context = try store()
        let pulledForward = session(context, 1)
        pulledForward.completedAt = day(0).addingTimeInterval(8 * 3600)
        let todays = session(context, 0)
        todays.completedAt = day(0).addingTimeInterval(7 * 3600)

        let found = DayOffer.finishedToday(all(context), now: day(0).addingTimeInterval(20 * 3600))
        #expect(found?.scheduledFor == day(0))
    }

    @Test("A session pulled forward and finished today is still today's record")
    func finishedTodayFallsBackToLatest() throws {
        let context = try store()
        let pulledForward = session(context, 2)
        pulledForward.completedAt = day(0).addingTimeInterval(9 * 3600)

        let found = DayOffer.finishedToday(all(context), now: day(0).addingTimeInterval(20 * 3600))
        #expect(found?.scheduledFor == day(2))
    }

    // MARK: - The week's first day

    @Test("A block week starts seven days after the one before it, whatever weekday it began on")
    func weekStartCountsFromTheBlock() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let block = Block(startDate: start, goalWeightPounds: 150, startingWeightPounds: 170)
        let first = DayOffer.weekStart(1, of: block)
        #expect(first == Calendar.current.startOfDay(for: start))
        #expect(DayOffer.weekStart(3, of: block)
                == Calendar.current.date(byAdding: .day, value: 14, to: first))
    }

    // MARK: - The snapshot the complication reads

    @Test("The running fields are cleared when nothing is running")
    func snapshotClearsWhenIdle() {
        var snapshot = TodaySnapshot.sample
        snapshot.runningTitle = "Full · mixed"
        snapshot.runningPhase = "Work"
        snapshot.runningPhaseEnds = .now.addingTimeInterval(40)
        snapshot.runningEnds = .now.addingTimeInterval(600)

        snapshot.setRunning(nil)

        #expect(snapshot.runningTitle == nil)
        #expect(snapshot.runningPhase == nil)
        #expect(snapshot.runningPhaseEnds == nil)
        #expect(snapshot.runningEnds == nil)
        #expect(snapshot.isRunning() == false)
    }

    @Test("A running session fills the phase and both end dates")
    func snapshotFillsWhileRunning() {
        let routine = IntervalRoutine(name: "Full · mixed", work: 40, rest: 20, rounds: 4,
                                      moves: [Move(name: "Kettlebell row", equipment: .kettlebell,
                                                   cue: "Flat back, elbow past the ribs.")])
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let active = ActiveSession(routine: routine, startedAt: now, elapsed: 10,
                                   running: true, savedAt: now)
        var snapshot = TodaySnapshot()
        snapshot.setRunning(active, now: now)

        #expect(snapshot.runningTitle == "Full · mixed")
        #expect(snapshot.runningPhase == "Work")
        // Ten seconds into a forty-second work interval.
        #expect(snapshot.runningPhaseEnds == now.addingTimeInterval(30))
        #expect(snapshot.isRunning(at: now))
    }

    @Test("A snapshot the phone wrote — with none of the running keys — still decodes")
    func oldSnapshotsDecode() throws {
        // The phone writes these fields and no others. The synthesized decoder
        // throws on a missing non-Optional key, which is why every one of the
        // running fields is Optional.
        let json = """
        {"days":[],"practiceDone":false,"practiceMinutes":8,
         "writtenOn":0,"week":1,"weekCount":12,"marksThisWeek":2,"marksTarget":4}
        """
        let decoded = try JSONDecoder().decode(TodaySnapshot.self, from: Data(json.utf8))
        #expect(decoded.marksThisWeek == 2)
        #expect(decoded.runningTitle == nil)
        #expect(decoded.isRunning() == false)
    }
}
