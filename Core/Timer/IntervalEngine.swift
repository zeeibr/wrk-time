import Foundation
import Observation

/// Drives a routine against wall-clock time.
///
/// The engine never accumulates decrements. It records when the routine started
/// and how long it has been paused, then derives everything from
/// `elapsed = now - start - pausedTotal` against the precomputed schedule. A
/// dropped tick, a backgrounded app, or a slow frame therefore cannot make the
/// count wrong — the next tick simply reports the truth.
@Observable
@MainActor
final class IntervalEngine {
    enum Status: Equatable { case idle, running, paused, finished }

    private(set) var routine: IntervalRoutine
    private(set) var schedule: RoutineSchedule
    private(set) var status: Status = .idle

    /// Why the session stopped, readable as state. The cue closures are
    /// single-assignment and already belong to `Haptics`, so a view that needs
    /// to act on the ending reads this rather than competing for `onFinish`.
    private(set) var endReason: EndReason?

    /// Re-read on every tick so the view updates; derived, never stored state.
    private(set) var elapsed: TimeInterval = 0

    /// Injectable so tests can drive time without waiting for it.
    private let now: () -> Date
    /// Tests drive `refresh()` by hand; a live ticker would race the fake clock.
    private let autoTick: Bool

    /// When the session began. Exposed so a finished session can be written
    /// back to Health with its real bounds rather than a guess.
    private(set) var startDate: Date?
    private var pausedTotal: TimeInterval = 0
    private var pauseBegan: Date?
    /// Seconds skipped forward past the natural schedule.
    private var skipOffset: TimeInterval = 0

    private var ticker: Task<Void, Never>?

    /// Why a session stopped. A session run to the end earns a mark; one you
    /// walked away from earns nothing and is not congratulated for it.
    enum EndReason { case completed, abandoned }

    /// Fires once per phase boundary, for haptics and audio cues.
    var onPhaseChange: ((Phase?) -> Void)?
    /// Fires once when the session stops, saying why. Belongs to the cue layer.
    var onFinish: ((EndReason) -> Void)?

    /// Fires once when the session stops, for whatever must be **recorded**.
    ///
    /// A second callback rather than sharing `onFinish`, and it is worth being
    /// exact about why, because the alternative cost a fortnight of vanished
    /// sessions.
    ///
    /// The view used to learn about the ending from
    /// `.onChange(of: engine.status)`. That modifier hung on the *field* — the
    /// running screen — and finishing swaps the field out for the completion
    /// screen in the very same update. SwiftUI does not run a change handler
    /// on a view it is removing, so the one ending that mattered was the one
    /// nothing heard: a session run to the end wrote no mark, while one
    /// abandoned early reported fine, because abandoning leaves the field on
    /// screen.
    ///
    /// So recording an ending must not depend on a view still being mounted.
    /// This fires from inside the engine, synchronously, at the moment the
    /// session stops — before any view hierarchy has had a chance to change.
    var onEnded: ((EndReason) -> Void)?
    /// Fires on each of the last three seconds of a work phase, so the coming
    /// change can be felt with the phone face-down on the floor.
    var onCountdownTick: (() -> Void)?

    private var lastNotifiedIndex: Int??
    private var lastTickSecond: Int?

    init(routine: IntervalRoutine,
         now: @escaping () -> Date = Date.init,
         autoTick: Bool = true) {
        self.routine = routine
        self.schedule = routine.schedule
        self.now = now
        self.autoTick = autoTick
    }

    // MARK: - Derived state

    var currentIndex: Int? { schedule.index(atElapsed: elapsed) }

    var currentPhase: Phase? {
        currentIndex.map { schedule.phases[$0] }
    }

    /// Seconds left in the current phase, rounded up so the display shows
    /// "0:01" for the whole final second rather than flicking to zero early.
    var remainingInPhase: TimeInterval {
        guard let phase = currentPhase else { return 0 }
        return max(0, phase.end - elapsed)
    }

    var remainingInRoutine: TimeInterval {
        max(0, schedule.total - elapsed)
    }

    /// 0 at the start of the phase, 1 at its end. This is what the draining
    /// field is bound to.
    var phaseProgress: Double {
        guard let phase = currentPhase, phase.duration > 0 else { return 0 }
        return min(1, max(0, (elapsed - phase.start) / phase.duration))
    }

    /// The fraction of the phase still to come — the height of the field.
    var phaseRemainingFraction: Double { 1 - phaseProgress }

    var completedWorkRounds: Int {
        guard let phase = currentPhase else { return schedule.workPhaseCount }
        // A flow phase numbers its position in the practice, not a round.
        // Without this, being three movements into the warm-up would report two
        // rounds already done.
        guard !phase.isFlow else { return 0 }
        return max(0, phase.round - 1)
    }

    /// True while the session is still in its opening practice.
    var isWarmingUp: Bool { currentPhase?.isFlow ?? false }

    /// The phase after the current one, for the "up next" line.
    var nextPhase: Phase? {
        guard let index = currentIndex, schedule.phases.indices.contains(index + 1) else { return nil }
        return schedule.phases[index + 1]
    }

    // MARK: - Transport

    func start() {
        guard status == .idle || status == .finished else { return }
        startDate = now()
        pausedTotal = 0
        pauseBegan = nil
        skipOffset = 0
        elapsed = 0
        lastNotifiedIndex = nil
        lastTickSecond = nil
        endReason = nil
        skippedMoves = []
        status = .running
        notifyPhaseChangeIfNeeded()
        startTicking()
    }

    /// Pick a session back up partway through, after the process died under it.
    ///
    /// This is the dividend of the engine deriving everything from elapsed
    /// wall-clock time against a precomputed schedule: there is no accumulated
    /// per-tick state to reconstruct, so resuming is only a matter of placing
    /// `startDate` where it would have been. An engine that decremented a
    /// counter every tick could not do this at all.
    func restore(to offset: TimeInterval, running: Bool = true) {
        guard offset > 0, offset < schedule.total else {
            start()
            return
        }
        startDate = now().addingTimeInterval(-offset)
        pausedTotal = 0
        pauseBegan = running ? nil : now()
        skipOffset = 0
        elapsed = offset
        lastNotifiedIndex = nil
        lastTickSecond = nil
        endReason = nil
        status = running ? .running : .paused
        notifyPhaseChangeIfNeeded()
        if running { startTicking() }
    }

    func pause() {
        guard status == .running else { return }
        pauseBegan = now()
        status = .paused
        stopTicking()
    }

    func resume() {
        guard status == .paused, let began = pauseBegan else { return }
        pausedTotal += now().timeIntervalSince(began)
        pauseBegan = nil
        status = .running
        startTicking()
    }

    func toggle() {
        switch status {
        case .running: pause()
        case .paused: resume()
        case .idle: start()
        // A finished session is over. Restarting the whole routine from the
        // same control that paused it is not a transport action, it is a
        // thirteen-minute surprise.
        case .finished: break
        }
    }

    /// Moves skipped this session, in the order they were skipped.
    ///
    /// Recorded because "she skipped something" is the most informative thing a
    /// session produces and it was previously thrown away — the engine jumped
    /// the clock forward and kept no note of what it had jumped over.
    private(set) var skippedMoves: [String] = []

    /// Jump to the start of the next phase. Implemented as a shift in the
    /// elapsed origin rather than by mutating the schedule, so the schedule
    /// stays a pure function of the routine.
    func skip() {
        guard let index = currentIndex else { return }
        // Read the move before the clock moves, or we record the next one.
        // Flow counts: skipping the spinal wave every session is exactly the
        // kind of thing worth being asked about, and dropping it here would
        // make the practice the one part of a session with no feedback path.
        if let move = schedule.phases[index].move, !schedule.phases[index].isRest,
           !skippedMoves.contains(move.name) {
            skippedMoves.append(move.name)
        }
        let target = schedule.start(of: index + 1)
        skipOffset += target - elapsed
        refresh()
    }

    /// How long each open-ended set actually ran, by set ordinal
    /// (`RoutineSchedule.setOrdinal`). A rep set's scheduled length is only
    /// the net under it; the seconds the record keeps are the ones she lifted.
    private(set) var setDurations: [Int: TimeInterval] = [:]

    /// She has finished the set. The rest begins now.
    ///
    /// Distinct from `skip`: a set she ended is a set she did, so it is not
    /// written down as skipped, and its real length is kept for the record.
    /// On a phase that is not open-ended this is a plain skip — the one
    /// control can sit in the same place in every mode.
    func endSet() {
        guard let index = currentIndex else { return }
        let phase = schedule.phases[index]
        guard phase.openEnded else { skip(); return }
        if let ordinal = schedule.setOrdinal(of: index) {
            setDurations[ordinal] = max(1, (elapsed - phase.start).rounded())
        }
        let target = schedule.start(of: index + 1)
        skipOffset += target - elapsed
        refresh()
    }

    /// Stop the session. The reason travels with it, because ending early and
    /// running to the end are not the same event and must not be cued alike.
    func end(reason: EndReason = .abandoned) {
        guard status != .finished else { return }
        stopTicking()
        status = .finished
        elapsed = schedule.total
        endReason = reason
        onFinish?(reason)
        onEnded?(reason)
    }

    // MARK: - Ticking

    private func startTicking() {
        stopTicking()
        guard autoTick else { return }
        // The engine is main-actor isolated, so this task inherits that
        // isolation and touches the engine directly — no hop, no sending.
        //
        // `self` is held weakly, and the strong reference the tick borrows is
        // released before the sleep — holding it across the suspension would
        // keep the engine alive for as long as the loop ran. The loop ends
        // itself when the engine goes away or stops running, so there is
        // nothing left for a deinit to cancel.
        ticker = Task { [weak self] in
            while !Task.isCancelled, self?.tickOnce() == true {
                // 20 Hz is smooth for a draining field and cheap enough to run
                // for half an hour without meaningfully touching the battery.
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// One pass of the live ticker. Returns whether the loop should continue.
    private func tickOnce() -> Bool {
        refresh()
        return status == .running
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    /// Recompute elapsed from the clock. Called by the ticker, and safe to call
    /// on returning to the foreground — that is the whole point of the design.
    func refresh() {
        guard let startDate else { return }
        var paused = pausedTotal
        if let pauseBegan { paused += now().timeIntervalSince(pauseBegan) }
        // Clamped at zero as well as at the top. `Date.now` is not monotonic:
        // move the clock back five minutes mid-session and `elapsed` went
        // negative, `index(atElapsed:)` returned nil, and the session sat in a
        // no-phase state — count at 0:00, caption reading "Finished", field
        // full, never finishing — until real time caught up.
        elapsed = max(0, now().timeIntervalSince(startDate) - paused + skipOffset)

        if elapsed >= schedule.total {
            elapsed = schedule.total
            if status != .finished {
                stopTicking()
                status = .finished
                endReason = .completed
                onFinish?(.completed)
                onEnded?(.completed)
            }
            return
        }
        notifyPhaseChangeIfNeeded()
        notifyCountdownIfNeeded()
    }

    private func notifyPhaseChangeIfNeeded() {
        let index = currentIndex
        if lastNotifiedIndex != .some(index) {
            lastNotifiedIndex = .some(index)
            lastTickSecond = nil
            onPhaseChange?(currentPhase)
        }
    }

    /// Cue the last three seconds of work. Driven by crossing a second
    /// boundary rather than by its own timer, so a slow frame can make a tick
    /// late but cannot drop one or fire it twice.
    private func notifyCountdownIfNeeded() {
        guard status == .running, let phase = currentPhase, phase.isWork else { return }
        let secondsLeft = Int(remainingInPhase.rounded(.up))
        guard (1...3).contains(secondsLeft), secondsLeft != lastTickSecond else { return }
        lastTickSecond = secondsLeft
        onCountdownTick?()
    }
}

// MARK: - Formatting

extension TimeInterval {
    /// `0:41`. Rounds up so a phase reads "0:01" for its whole final second.
    var clockString: String {
        let total = Int(rounded(.up))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    /// `14:00` for durations stated in minutes and seconds.
    var durationString: String {
        let total = Int(rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
