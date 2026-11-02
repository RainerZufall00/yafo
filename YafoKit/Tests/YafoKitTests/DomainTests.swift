import Foundation
import Testing
@testable import YafoKit

@Suite struct DomainTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2 // Montag
        return calendar
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test(arguments: [("Anna Maria Schmidt", "AS"), ("Mama", "MA"), ("", "?"), ("jan-ole", "JO")])
    func initials(name: String, expected: String) {
        #expect(Initials.make(from: name) == expected)
    }

    @Test func monthGridStartsOnMondayAndCoversWholeWeeks() {
        // November 2026 beginnt an einem Sonntag.
        let grid = MonthGrid(containing: date(2026, 11, 15), calendar: calendar)
        #expect(grid.days.count % 7 == 0)
        #expect(grid.days.first?.date == date(2026, 10, 26))
        #expect(grid.days.first?.isInMonth == false)
        #expect(grid.days.filter(\.isInMonth).count == 30)
        #expect(grid.weeks.count == 6)
    }

    @Test func weekdaySymbolsFollowFirstWeekday() {
        var german = calendar
        german.locale = Locale(identifier: "de_DE")
        #expect(MonthGrid.weekdaySymbols(calendar: german).first == "M")
    }

    @Test func daysOfEvent() {
        // Ganztägig 1.–3. Dezember, Ende exklusiv am 4.
        #expect(calendar.days(from: date(2026, 12, 1), to: date(2026, 12, 4)).count == 3)
        // Abends bis nach Mitternacht.
        #expect(calendar.days(from: date(2026, 12, 1, 22), to: date(2026, 12, 2, 1)).count == 2)
        // Ohne Dauer.
        #expect(calendar.days(from: date(2026, 12, 1, 9), to: date(2026, 12, 1, 9)).count == 1)
    }

    @Test func defaultColors() {
        #expect(CalendarColors.defaultColor(for: .personal) == CalendarColors.personalDefault)
        #expect(CalendarColors.defaultColor(for: .shared) == CalendarColors.sharedDefault)
        #expect(CalendarColors.defaultColor(for: .shared, existingSharedCount: 6)
                == CalendarColors.additionalShared[0])
    }
}
