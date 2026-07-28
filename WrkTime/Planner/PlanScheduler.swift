import BackgroundTasks
import Foundation
import SwiftData

/// Writes the week before she is awake to read it.
///
/// Planning is a network call that can take the better part of a minute, and it
/// used to happen at the worst possible moment: the first time she opened the
/// app on the first day of a new week, with her standing there waiting. Her
/// ask was to have it fire around six in the morning instead — so the week is
/// simply there.
///
/// **This is best effort and the code must not pretend otherwise.** iOS decides
/// when a background task actually runs; `earliestBeginDate` is a floor, not an
/// appointment, and the system weighs battery, charge state and how much she
/// uses the app. It typically runs overnight on a charger and it may not run at
/// all. So the launch path stays exactly as it was: opening the app into an
/// unplanned week still writes it. This only means that most mornings, nothing
/// will need to.
///
/// It costs nothing extra. The same decision runs — `PlanTrigger` still says
/// whether the model is worth asking — so a clean week is stepped on in the
/// background just as it would be in the foreground.
@MainActor
enum PlanScheduler {
    /// Also listed in `BGTaskSchedulerPermittedIdentifiers`; the two must match
    /// or registration traps at launch.
    static let taskIdentifier = "com.zee.wrktime.plan"

    /// Six in the morning, her time.
    ///
    /// Local rather than a fixed zone: she asked for Los Angeles because that
    /// is where she is, and six on a Tuesday should stay six on a Tuesday if
    /// she travels.
    static let hour = 6

    private static var container: ModelContainer?

    /// Registered before the app finishes launching, which is the only moment
    /// `BGTaskScheduler` accepts a handler.
    static func register(container: ModelContainer) {
        Self.container = container
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            Task { @MainActor in await run(task) }
        }
    }

    /// Asks for the next six a.m. Safe to call often — a second request for the
    /// same identifier replaces the first rather than queueing another.
    static func schedule(after date: Date = .now) {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = nextMorning(after: date)
        // A plan needs the network; it does not need her plugged in, and
        // requiring that would mean the week never gets written on a phone that
        // charges during the day.
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    static func nextMorning(after date: Date, calendar: Calendar = .current) -> Date {
        let next = calendar.nextDate(after: date,
                                     matching: DateComponents(hour: hour, minute: 0),
                                     matchingPolicy: .nextTime)
        return next ?? date.addingTimeInterval(86_400)
    }

    /// When iOS last actually ran the task — not when it was last asked for.
    ///
    /// Recorded whether or not a week got written, because the question it
    /// answers is "is this happening at all", and a morning where the week was
    /// already planned is a success rather than a silence. Without it the
    /// feature is unfalsifiable from the outside: nothing on screen would ever
    /// differ between iOS running it and iOS deciding not to.
    static var lastRan: Date? {
        UserDefaults.standard.object(forKey: "lastMorningPlanAt") as? Date
    }

    private static func run(_ task: BGTask) async {
        UserDefaults.standard.set(Date.now, forKey: "lastMorningPlanAt")

        // Always ask for the next one first. If this is skipped and the work
        // below throws or is cut short, nothing ever schedules again and the
        // feature silently stops existing.
        schedule()

        guard let container else { return task.setTaskCompleted(success: false) }
        let context = ModelContext(container)

        let planning = Task { () -> Bool in
            let blocks = (try? context.fetch(FetchDescriptor<Block>())) ?? []
            guard let block = blocks.first, !block.hasEnded else { return false }
            let outcome = await PlannerService.planCurrentWeekIfNeeded(for: block, in: context)
            return outcome != nil
        }

        // The system can pull the rug at any point; leaving a half-written week
        // behind would be worse than not having tried.
        task.expirationHandler = { planning.cancel() }
        let wrote = await planning.value
        task.setTaskCompleted(success: wrote)
    }
}
