import Foundation
import Testing
@testable import YafoKit

@Suite struct DayLayoutTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    /// Samstag, 14. November 2026
    var day: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 14))! }

    func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 14 + dayOffset, hour: hour, minute: minute))!
    }

    func item(_ layout: DayLayout<String>, _ id: String) -> DayLayout<String>.Item {
        layout.items.first { $0.id == id }!
    }

    @Test func separateEventsUseTheFullWidth() {
        let layout = DayLayout<String>(day: day, entries: [
            .init(id: "a", start: at(9), end: at(10)),
            .init(id: "b", start: at(10), end: at(11, 30))
        ], calendar: calendar)

        let a = item(layout, "a"), b = item(layout, "b")
        #expect(a.startMinute == 540 && a.endMinute == 600)
        #expect(b.startMinute == 600 && b.endMinute == 690)
        #expect(a.columnCount == 1 && b.columnCount == 1)
        #expect(a.column == 0 && b.column == 0)
    }

    @Test func overlappingEventsStandSideBySide() {
        let layout = DayLayout<String>(day: day, entries: [
            .init(id: "long", start: at(9), end: at(12)),
            .init(id: "first", start: at(9, 30), end: at(10)),
            .init(id: "second", start: at(10, 30), end: at(11)),
            .init(id: "later", start: at(14), end: at(15))
        ], calendar: calendar)

        #expect(item(layout, "long").column == 0)
        #expect(item(layout, "first").column == 1)
        // Spalte 1 ist um 10 Uhr wieder frei.
        #expect(item(layout, "second").column == 1)
        #expect(item(layout, "long").columnCount == 2)
        #expect(item(layout, "second").columnCount == 2)
        #expect(item(layout, "later").columnCount == 1)
    }

    @Test func shortEventsGetTheirMinimumHeightForOverlap() {
        let layout = DayLayout<String>(day: day, entries: [
            .init(id: "quick", start: at(9), end: at(9, 5)),
            .init(id: "next", start: at(9, 15), end: at(10))
        ], minimumMinutes: 30, calendar: calendar)

        #expect(item(layout, "quick").endMinute == 545)
        #expect(item(layout, "next").column == 1)
        #expect(item(layout, "quick").columnCount == 2)
    }

    @Test func eventsAcrossMidnightAreClipped() {
        let layout = DayLayout<String>(day: day, entries: [
            .init(id: "night", start: at(22, dayOffset: -1), end: at(2)),
            .init(id: "party", start: at(21), end: at(1, dayOffset: 1)),
            .init(id: "yesterday", start: at(20, dayOffset: -1), end: at(0))
        ], calendar: calendar)

        let night = item(layout, "night")
        #expect(night.startMinute == 0 && night.endMinute == 120)
        #expect(night.continuesBefore && !night.continuesAfter)
        let party = item(layout, "party")
        #expect(party.startMinute == 1260 && party.endMinute == 1440)
        #expect(party.continuesAfter)
        #expect(layout.items.contains { $0.id == "yesterday" } == false)
    }

    @Test func wallClockMinutesOnDaylightSavingDay() {
        let switchDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29))!
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 9))!
        let layout = DayLayout<String>(day: switchDay, entries: [
            .init(id: "brunch", start: start, end: start.addingTimeInterval(3600))
        ], calendar: calendar)

        #expect(item(layout, "brunch").startMinute == 540)
        #expect(item(layout, "brunch").endMinute == 600)
    }
}
