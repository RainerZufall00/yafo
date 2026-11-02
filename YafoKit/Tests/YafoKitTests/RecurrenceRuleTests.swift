import Foundation
import Testing
@testable import YafoKit

@Suite struct RecurrenceRuleTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func days(_ rule: String, from start: Date, until end: Date) -> [String] {
        RecurrenceRule(rrule: rule)!
            .startDates(seriesStart: start, from: start, to: end, calendar: calendar)
            .map { d in
                let c = calendar.dateComponents([.year, .month, .day], from: d)
                return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
            }
    }

    @Test func parsesAndWritesRules() throws {
        let rule = try #require(RecurrenceRule(rrule: "RRULE:FREQ=MONTHLY;INTERVAL=2;BYDAY=-1FR,2MO;COUNT=5"))
        #expect(rule.frequency == .monthly)
        #expect(rule.interval == 2)
        #expect(rule.byDay == [.init(6, ordinal: -1), .init(2, ordinal: 2)])
        #expect(rule.count == 5)
        #expect(rule.rruleString == "FREQ=MONTHLY;INTERVAL=2;BYDAY=-1FR,2MO;COUNT=5")
    }

    @Test func keepsUnknownParts() throws {
        let rule = try #require(RecurrenceRule(rrule: "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1"))
        #expect(rule.rruleString.hasSuffix(";BYSETPOS=-1"))
    }

    @Test(arguments: ["", "FREQ=HOURLY", "FREQ=DAILY;INTERVAL=0", "FREQ=WEEKLY;BYDAY=XX", "FREQ=DAILY;COUNT=abc"])
    func rejectsInvalidRules(rule: String) {
        #expect(RecurrenceRule(rrule: rule) == nil)
    }

    @Test func untilFormats() throws {
        let utc = try #require(RecurrenceRule(rrule: "FREQ=DAILY;UNTIL=20261231T230000Z"))
        #expect(utc.until == date(2027, 1, 1, 0))
        // Nur Datum: der ganze Tag zählt mit.
        let dateOnly = try #require(RecurrenceRule(rrule: "FREQ=DAILY;UNTIL=20261231"))
        let roundTrip = try #require(RecurrenceRule(rrule: dateOnly.rruleString))
        #expect(roundTrip.until == dateOnly.until)
    }

    @Test func weeklyOnSeveralDays() {
        // Mo, 2. November 2026
        let result = days("FREQ=WEEKLY;BYDAY=MO,WE", from: date(2026, 11, 2, 16), until: date(2026, 11, 17))
        #expect(result == ["2026-11-02", "2026-11-04", "2026-11-09", "2026-11-11", "2026-11-16"])
    }

    @Test func everyTwoWeeks() {
        let result = days("FREQ=WEEKLY;INTERVAL=2", from: date(2026, 11, 4, 9), until: date(2026, 12, 31))
        #expect(result == ["2026-11-04", "2026-11-18", "2026-12-02", "2026-12-16", "2026-12-30"])
    }

    @Test func weeklyStartingMidWeekSkipsEarlierDays() {
        // Serie beginnt Mi; der Montag derselben Woche liegt davor und zählt nicht.
        let result = days("FREQ=WEEKLY;BYDAY=MO,WE;COUNT=3", from: date(2026, 11, 4, 9), until: date(2027, 1, 1))
        #expect(result == ["2026-11-04", "2026-11-09", "2026-11-11"])
    }

    @Test func monthlyOn31stSkipsShortMonths() {
        let result = days("FREQ=MONTHLY", from: date(2027, 1, 31), until: date(2027, 6, 1))
        #expect(result == ["2027-01-31", "2027-03-31", "2027-05-31"])
    }

    @Test func lastFridayAndSecondMonday() {
        #expect(days("FREQ=MONTHLY;BYDAY=-1FR", from: date(2026, 11, 1), until: date(2027, 2, 1))
                == ["2026-11-27", "2026-12-25", "2027-01-29"])
        #expect(days("FREQ=MONTHLY;BYDAY=2MO;COUNT=2", from: date(2026, 11, 1), until: date(2027, 6, 1))
                == ["2026-11-09", "2026-12-14"])
    }

    @Test func lastDayOfMonth() {
        #expect(days("FREQ=MONTHLY;BYMONTHDAY=-1", from: date(2027, 1, 1), until: date(2027, 4, 1))
                == ["2027-01-31", "2027-02-28", "2027-03-31"])
    }

    @Test func yearlyOnLeapDayOnlyInLeapYears() {
        #expect(days("FREQ=YEARLY", from: date(2028, 2, 29), until: date(2037, 1, 1))
                == ["2028-02-29", "2032-02-29", "2036-02-29"])
    }

    @Test func yearlyNthWeekdayOfMonth() {
        // Muttertag: zweiter Sonntag im Mai.
        #expect(days("FREQ=YEARLY;BYMONTH=5;BYDAY=2SU", from: date(2027, 1, 1), until: date(2029, 1, 1))
                == ["2027-05-09", "2028-05-14"])
    }

    @Test func countIncludesOccurrencesBeforeTheWindow() {
        let rule = RecurrenceRule(rrule: "FREQ=DAILY;COUNT=10")!
        let start = date(2026, 11, 1, 8)
        let window = rule.startDates(seriesStart: start, from: date(2026, 11, 8), to: date(2026, 12, 1),
                                     calendar: calendar)
        #expect(window.count == 3) // 8., 9., 10. November
    }

    @Test func untilIsInclusive() {
        let rule = RecurrenceRule(frequency: .daily, until: date(2026, 11, 3, 8))
        let result = rule.startDates(seriesStart: date(2026, 11, 1, 8), from: .distantPast, to: .distantFuture,
                                     calendar: calendar)
        #expect(result.count == 3)
    }

    @Test func wallClockTimeSurvivesDaylightSavingChange() {
        // Zeitumstellung am 28. März 2027: 9 Uhr bleibt 9 Uhr.
        let rule = RecurrenceRule(frequency: .weekly)
        let result = rule.startDates(seriesStart: date(2027, 3, 21, 9), from: date(2027, 3, 1),
                                     to: date(2027, 4, 5), calendar: calendar)
        #expect(result.map { calendar.component(.hour, from: $0) } == [9, 9, 9])
    }

    @Test func dailyFilteredByWeekdays() {
        #expect(days("FREQ=DAILY;BYDAY=SA,SU", from: date(2026, 11, 2), until: date(2026, 11, 16))
                == ["2026-11-07", "2026-11-08", "2026-11-14", "2026-11-15"])
    }
}
