import Foundation

/// What a stated goal *implies*, as distinct from what is actually happening.
///
/// `WeightTrend` answers "what is happening" — a seven-day mean and a rate
/// measured from real readings, and it correctly refuses to project a date when
/// the trend is flat or going the other way. That is the right answer once
/// there is history. It is no answer at all on the day the block is set up,
/// when there are no readings yet and the reader is being asked to choose a
/// goal and a pace with nothing to go on.
///
/// This fills that gap, and only that gap. Two decisions are deliberate:
///
/// **It caps the rate rather than honouring any date.** You can name a target
/// date; if it needs more than one percent of body weight a week, the
/// projection says what the date would cost instead of quietly drawing a
/// steeper line. Faster than that is mostly water and lean tissue, and lean
/// tissue is the thing the whole block exists to keep.
///
/// **It is drawn from a mean, never a single reading**, for the same reason
/// `WeightTrend` is: scale weight swings two to four pounds across a cycle on
/// fluid alone, which is larger than a week of real change.
struct Projection: Equatable {
    let current: Double
    let goal: Double
    /// Signed pounds per week, positive when the number is coming down.
    let weeklyRate: Double
    let weeksRemaining: Double
    let arrival: Date
    /// True when the requested date needed a rate this refuses to draw.
    let cappedFromRequestedDate: Bool

    /// The rate above which change is mostly fluid and lean mass.
    static let safeFraction = 0.01
    /// Where the app aims when it is choosing for you: gentler than the ceiling.
    static let defaultFraction = 0.0065

    var poundsRemaining: Double { current - goal }
    var isComplete: Bool { poundsRemaining <= 0 }

    /// "14 October · about 9 weeks" — a date and a distance, no percentages.
    var summary: String {
        guard !isComplete else { return "At goal" }
        let weeks = Int(weeksRemaining.rounded())
        let date = arrival.formatted(.dateTime.month(.wide).day())
        return "\(date) · about \(weeks) \(weeks == 1 ? "week" : "weeks")"
    }

    /// Said once, where the date is chosen — never as a recurring banner.
    var cappedNote: String? {
        guard cappedFromRequestedDate else { return nil }
        return "That date needs more than a pound a week off your current weight. The plan is drawn at a rate that keeps the muscle you are building, so the date moved rather than the rate."
    }
}

enum Projections {
    /// Draws the projection. `requestedArrival` is the reader's date if she set
    /// one; the rate it implies is honoured only up to the safe ceiling.
    static func project(current: Double,
                        goal: Double,
                        requestedArrival: Date? = nil,
                        from now: Date = .now) -> Projection? {
        guard current > 0, goal > 0 else { return nil }

        let remaining = current - goal
        guard remaining > 0 else {
            return Projection(current: current, goal: goal, weeklyRate: 0,
                              weeksRemaining: 0, arrival: now,
                              cappedFromRequestedDate: false)
        }

        let ceiling = current * Projection.safeFraction
        var rate = current * Projection.defaultFraction
        var capped = false

        if let requestedArrival {
            let weeks = now.distance(to: requestedArrival) / (7 * 86_400)
            if weeks > 0 {
                let implied = remaining / weeks
                rate = min(implied, ceiling)
                capped = implied > ceiling
            }
        }

        // A floor as well as a ceiling: a rate near zero projects a date
        // decades out, which is noise rather than information.
        rate = max(rate, 0.15)

        let weeks = remaining / rate
        let arrival = now.addingTimeInterval(weeks * 7 * 86_400)
        return Projection(current: current, goal: goal, weeklyRate: rate,
                          weeksRemaining: weeks, arrival: arrival,
                          cappedFromRequestedDate: capped)
    }
}
