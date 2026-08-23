import Foundation
import Testing
@testable import WrkTime

/// One walk, once — however many devices wrote it down.
///
/// She started wearing the Apple Watch alongside the Whoop, and every walk
/// arrived on Signals twice at the same time: once from each recorder,
/// both rows counted into the week's minutes and into what the planner is
/// told about her volume.
@Suite("Recorded walks are deduplicated")
struct RecordedWalkTests {

    private func walk(_ source: String, start: TimeInterval, minutes: Double) -> RecordedWalk {
        RecordedWalk(date: Date(timeIntervalSinceReferenceDate: start),
                     minutes: minutes, source: source)
    }

    @Test("Two recordings of the same walk merge into one")
    func sameWalkTwice() {
        let merged = RecordedWalk.deduplicated([
            walk("Whoop", start: 0, minutes: 30),
            walk("Apple Watch", start: 30, minutes: 30),
        ])
        #expect(merged.count == 1)
        #expect(merged[0].source == "Whoop · Apple Watch")
    }

    @Test("The merged walk counts the union of time, never the sum")
    func unionNotSum() {
        // The watch started half a minute late and ran five minutes longer.
        let merged = RecordedWalk.deduplicated([
            walk("Whoop", start: 0, minutes: 30),
            walk("Apple Watch", start: 30, minutes: 35),
        ])
        #expect(merged.count == 1)
        #expect(abs(merged[0].minutes - 35.5) < 0.01)
        #expect(merged[0].date == Date(timeIntervalSinceReferenceDate: 0))
    }

    @Test("Walks apart in time stay two walks, same source or not")
    func separateWalksSurvive() {
        let morning = walk("Whoop", start: 0, minutes: 20)
        let evening = walk("Whoop", start: 8 * 3600, minutes: 20)
        let merged = RecordedWalk.deduplicated([morning, evening])
        #expect(merged.count == 2)
        // Newest first, the order the callers expect.
        #expect(merged[0].date > merged[1].date)
        #expect(merged.allSatisfy { $0.source == "Whoop" })
    }

    @Test("A minute of clock disagreement still reads as one walk")
    func toleranceCoversClockSkew() {
        // Whoop stopped at :30, the watch noticed the walk 40 s later.
        let merged = RecordedWalk.deduplicated([
            walk("Whoop", start: 0, minutes: 30),
            walk("Apple Watch", start: 30 * 60 + 40, minutes: 10),
        ])
        #expect(merged.count == 1)
    }

    @Test("Three recorders collapse to one row naming each once")
    func threeSourcesOnce() {
        let merged = RecordedWalk.deduplicated([
            walk("Whoop", start: 0, minutes: 30),
            walk("Apple Watch", start: 60, minutes: 29),
            walk("iPhone", start: 120, minutes: 20),
        ])
        #expect(merged.count == 1)
        #expect(merged[0].source == "Whoop · Apple Watch · iPhone")
    }

    @Test("An empty list stays empty")
    func emptyList() {
        #expect(RecordedWalk.deduplicated([]).isEmpty)
    }
}
