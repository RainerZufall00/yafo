import Foundation
import Testing
@testable import YafoKit

@Suite struct WeekLayoutTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Montag, 2. November 2026
    var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))! }

    func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(byAdding: .hour, value: day * 24 + hour, to: monday)!
    }

    func timed(_ id: String, day: Int, hour: Int) -> WeekLayout<String>.Entry {
        .init(id: id, start: at(day, hour), end: at(day, hour + 1), isAllDay: false)
    }

    @Test func spanningEventsComeFirstAndKeepOneLane() {
        let layout = WeekLayout(weekStart: monday, entries: [
            timed("dentist", day: 1, hour: 9),
            .init(id: "trip", start: at(0, 0), end: at(3, 0), isAllDay: true)
        ], maxLanes: 3, calendar: calendar)

        let trip = layout.items.first { $0.id == "trip" }!
        #expect(trip.lane == 0)
        #expect(trip.firstColumn == 0 && trip.lastColumn == 2)
        #expect(trip.isSpanning)
        let dentist = layout.items.first { $0.id == "dentist" }!
        #expect(dentist.lane == 1)
        #expect(dentist.isSpanning == false)
    }

    @Test func eventsReachingIntoOtherWeeksAreClipped() {
        let layout = WeekLayout(weekStart: monday, entries: [
            .init(id: "holiday", start: at(-2, 0), end: at(9, 0), isAllDay: true)
        ], maxLanes: 3, calendar: calendar)
        let item = layout.items[0]
        #expect(item.firstColumn == 0 && item.lastColumn == 6)
        #expect(item.continuesBefore && item.continuesAfter)
    }

    @Test func overflowLeavesTheLastLaneForMore() {
        let entries = (0..<5).map { timed("e\($0)", day: 2, hour: 8 + $0) } + [timed("other", day: 4, hour: 9)]
        let layout = WeekLayout(weekStart: monday, entries: entries, maxLanes: 3, calendar: calendar)

        #expect(layout.items.filter { $0.firstColumn == 2 }.map(\.id) == ["e0", "e1"])
        #expect(layout.hiddenCounts[2] == 3)
        // Ein Tag ohne Überlauf nutzt alle Spuren.
        #expect(layout.items.contains { $0.id == "other" })
        #expect(layout.hiddenCounts[4] == 0)
    }

    @Test func exactlyFittingDayShowsEverything() {
        let entries = (0..<3).map { timed("e\($0)", day: 0, hour: 8 + $0) }
        let layout = WeekLayout(weekStart: monday, entries: entries, maxLanes: 3, calendar: calendar)
        #expect(layout.items.count == 3)
        #expect(layout.hiddenCounts.allSatisfy { $0 == 0 })
    }

    @Test func eventsOutsideTheWeekAreIgnored() {
        let layout = WeekLayout(weekStart: monday, entries: [timed("later", day: 8, hour: 9)],
                                maxLanes: 3, calendar: calendar)
        #expect(layout.items.isEmpty)
    }

    @Test func monthRowUsesOneColumnPerDay() {
        // November 2026 hat 30 Tage; der Termin läuft in den Dezember hinein.
        let november = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let day = { (d: Int) in self.calendar.date(byAdding: .day, value: d - 1, to: november)! }
        let layout = WeekLayout(start: november, columns: 30, entries: [
            .init(id: "trip", start: day(20), end: day(35), isAllDay: true),
            .init(id: "fair", start: day(25), end: day(27), isAllDay: true)
        ], maxLanes: 3, calendar: calendar)

        let trip = layout.items.first { $0.id == "trip" }!
        #expect(trip.firstColumn == 19 && trip.lastColumn == 29)
        #expect(!trip.continuesBefore && trip.continuesAfter)
        #expect(layout.items.first { $0.id == "fair" }?.lane == 1)
        #expect(layout.hiddenCounts.count == 30)
        #expect(layout.laneCount == 2)
    }
}
