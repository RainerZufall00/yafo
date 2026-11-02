import Foundation
import Testing
@testable import YafoKit

@Suite struct ICSParserTests {
    var berlin: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        berlin.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func parsesTimedAllDayAndUTCEvents() {
        let ics = """
        BEGIN:VCALENDAR\r
        VERSION:2.0\r
        BEGIN:VEVENT\r
        UID:a1@example.com\r
        DTSTART;TZID=Europe/Berlin:20261103T100000\r
        DTEND;TZID=Europe/Berlin:20261103T113000\r
        SUMMARY:Zahnarzt\\, Kontrolle\r
        LOCATION:Praxis Dr. Müller\r
        DESCRIPTION:Erste Zeile\\nZweite Zeile\r
        BEGIN:VALARM\r
        TRIGGER:-PT15M\r
        DESCRIPTION:Alarm\r
        END:VALARM\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:b2\r
        DTSTART;VALUE=DATE:20261224\r
        DTEND;VALUE=DATE:20261227\r
        SUMMARY:Weihnachten\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:c3\r
        DTSTART:20261105T170000Z\r
        DURATION:PT1H30M\r
        SUMMARY:Call\r
        END:VEVENT\r
        END:VCALENDAR\r
        """
        let events = ICSParser.parse(ics, calendar: berlin)
        #expect(events.count == 3)

        let dentist = events[0]
        #expect(dentist.uid == "a1@example.com")
        #expect(dentist.summary == "Zahnarzt, Kontrolle")
        #expect(dentist.notes == "Erste Zeile\nZweite Zeile")
        #expect(dentist.start == local(2026, 11, 3, 10))
        #expect(dentist.end == local(2026, 11, 3, 11, 30))
        #expect(dentist.timeZone == "Europe/Berlin")
        #expect(!dentist.isAllDay)

        let christmas = events[1]
        #expect(christmas.isAllDay)
        #expect(christmas.start == local(2026, 12, 24))
        #expect(christmas.end == local(2026, 12, 27))

        let call = events[2]
        #expect(call.start == local(2026, 11, 5, 18))
        #expect(call.end == local(2026, 11, 5, 19, 30))
    }

    @Test func foldedLinesAndMissingEnd() {
        let ics = """
        BEGIN:VEVENT
        UID:long
        SUMMARY:Ein sehr langer
          Titel
        DTSTART;VALUE=DATE:20260101
        END:VEVENT
        """
        let event = ICSParser.parse(ics, calendar: berlin).first
        #expect(event?.summary == "Ein sehr langer Titel")
        #expect(event?.end == local(2026, 1, 2))
    }

    @Test func seriesWithExceptionsAndOverrides() {
        let ics = """
        BEGIN:VEVENT
        UID:swim
        DTSTART;TZID=Europe/Berlin:20261102T160000
        DTEND;TZID=Europe/Berlin:20261102T170000
        RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20261231T230000Z
        EXDATE;TZID=Europe/Berlin:20261109T160000,20261116T160000
        SUMMARY:Schwimmen
        ATTENDEE;CN=Anna:mailto:anna@example.com
        END:VEVENT
        BEGIN:VEVENT
        UID:swim
        RECURRENCE-ID;TZID=Europe/Berlin:20261123T160000
        DTSTART;TZID=Europe/Berlin:20261123T170000
        DTEND;TZID=Europe/Berlin:20261123T180000
        SUMMARY:Schwimmen (später)
        END:VEVENT
        """
        let events = ICSParser.parse(ics, calendar: berlin)
        #expect(events.count == 2)
        #expect(events[0].recurrenceRule == "FREQ=WEEKLY;BYDAY=MO;UNTIL=20261231T230000Z")
        #expect(events[0].excludedDates == [local(2026, 11, 9, 16), local(2026, 11, 16, 16)])
        #expect(events[0].hasAttendees)
        #expect(events[1].recurrenceID == local(2026, 11, 23, 16))
        #expect(events[1].start == local(2026, 11, 23, 17))
    }

    @Test func windowsTimeZonesAndDurations() {
        #expect(ICSParser.timeZone(for: "W. Europe Standard Time")?.identifier == "Europe/Berlin")
        #expect(ICSParser.timeZone(for: "/mozilla.org/20050126_1/Europe/Vienna")?.identifier == "Europe/Vienna")
        #expect(ICSParser.parseDuration("P1W") == DateComponents(day: 7))
        #expect(ICSParser.parseDuration("P1DT2H") == DateComponents(day: 1, hour: 2))
    }
}

@Suite struct ICSImportTests {
    let persistence: PersistenceController
    let repository: Repository
    let calendar: EventCalendar
    let cal = Calendar.current

    init() throws {
        persistence = try PersistenceController.makeTemporary()
        repository = Repository(persistence: persistence)
        calendar = repository.ensurePersonalCalendar(name: "Me")
    }

    func local(_ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
    }

    func ics(_ m: Int, _ d: Int, _ h: Int) -> String {
        String(format: "2026%02d%02dT%02d0000", m, d, h)
    }

    var seriesICS: String {
        """
        BEGIN:VEVENT
        UID:swim
        DTSTART:\(ics(11, 2, 16))
        DTEND:\(ics(11, 2, 17))
        RRULE:FREQ=WEEKLY;COUNT=4
        EXDATE:\(ics(11, 9, 16))
        SUMMARY:Swimming
        END:VEVENT
        BEGIN:VEVENT
        UID:swim
        RECURRENCE-ID:\(ics(11, 16, 16))
        DTSTART:\(ics(11, 16, 18))
        DTEND:\(ics(11, 16, 19))
        SUMMARY:Swimming late
        END:VEVENT
        BEGIN:VEVENT
        UID:trip
        DTSTART;VALUE=DATE:20261120
        DTEND;VALUE=DATE:20261122
        SUMMARY:Trip
        ATTENDEE:mailto:x@example.com
        END:VEVENT
        """
    }

    @Test func importsSeriesWithExceptionsAndSkipsDuplicates() throws {
        let events = ICSParser.parse(seriesICS)
        let preview = ICSImportPreview(events)
        #expect(preview.eventCount == 2 && preview.seriesCount == 1 && preview.withAttendees == 1)

        let result = repository.importICS(events, into: calendar, createdBy: nil)
        #expect(result.created == 2 && result.exceptions == 2)
        try repository.save()

        let month = DateInterval(start: local(11, 1), end: local(12, 1))
        let occurrences = repository.occurrences(overlapping: month)
        #expect(occurrences.map(\.title) == ["Swimming", "Swimming late", "Trip", "Swimming"])
        #expect(occurrences[1].start == local(11, 16, 18))
        #expect(occurrences[2].isAllDay && occurrences[2].end == local(11, 22))

        let again = repository.importICS(events, into: calendar, createdBy: nil)
        #expect(again.created == 0 && again.skipped == 2)
    }
}
