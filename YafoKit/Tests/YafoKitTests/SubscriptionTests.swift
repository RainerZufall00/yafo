import CoreData
import Foundation
import Testing
@testable import YafoKit

@Suite struct SubscriptionTests {
    let cal = Calendar.current

    func local(_ m: Int, _ d: Int, _ h: Int = 0, year: Int = 2026) -> Date {
        cal.date(from: DateComponents(year: year, month: m, day: d, hour: h))!
    }

    @Test func expandsSeriesWithExclusionsAndOverrides() {
        let text = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:bin
        DTSTART;VALUE=DATE:20261102
        RRULE:FREQ=WEEKLY;COUNT=4
        EXDATE;VALUE=DATE:20261109
        SUMMARY:Bio bin
        END:VEVENT
        BEGIN:VEVENT
        UID:bin
        RECURRENCE-ID;VALUE=DATE:20261116
        DTSTART;VALUE=DATE:20261117
        SUMMARY:Bio bin (moved)
        END:VEVENT
        BEGIN:VEVENT
        UID:fair
        DTSTART:20261120T100000
        DTEND:20261120T120000
        SUMMARY:School fair
        LOCATION:Gym
        END:VEVENT
        END:VCALENDAR
        """
        let window = DateInterval(start: local(10, 1), end: local(12, 31))
        let entries = SubscriptionFeed.entries(from: ICSParser.parse(text), in: window)
        #expect(entries.map(\.title) == ["Bio bin", "Bio bin (moved)", "School fair", "Bio bin"])
        #expect(entries.map(\.start) == [local(11, 2), local(11, 17), local(11, 20, 10), local(11, 23)])
        #expect(entries[0].end == local(11, 3))
        #expect(entries[2].location == "Gym")
        #expect(Set(entries.map(\.uid)).count == 4)
    }

    @Test func dropsEventsOutsideTheWindow() {
        let text = """
        BEGIN:VEVENT
        UID:old
        DTSTART;VALUE=DATE:20200101
        SUMMARY:Old
        END:VEVENT
        """
        let window = DateInterval(start: local(1, 1), end: local(12, 31))
        #expect(SubscriptionFeed.entries(from: ICSParser.parse(text), in: window).isEmpty)
    }

    @Test func normalizesAddresses() {
        #expect(SubscriptionFeed.sourceKey(forICS: " webcal://Example.COM/cal.ics ")
                == "ics:https://example.com/cal.ics")
        #expect(SubscriptionFeed.sourceKey(forICS: "https://example.com/cal.ics")
                == SubscriptionFeed.sourceKey(forICS: "webcal://example.com/cal.ics"))
        #expect(SubscriptionFeed.normalizedURL("ftp://example.com") == nil)
        #expect(SubscriptionFeed.normalizedURL("not a url") == nil)
    }

    @Test func parsesSchoolHolidays() throws {
        let json = """
        [{"id":"a","startDate":"2026-11-02","endDate":"2026-11-06","type":"School",
          "name":[{"language":"DE","text":"Herbstferien"},{"language":"EN","text":"Autumn holidays"}]},
         {"id":"b","startDate":"2026-12-23","endDate":"2027-01-05","type":"School",
          "name":[{"language":"DE","text":"Weihnachtsferien"}]}]
        """
        let german = try SchoolHolidays.parse(Data(json.utf8), languageCode: "de")
        #expect(german.map(\.title) == ["Herbstferien", "Weihnachtsferien"])
        #expect(german[0].start == local(11, 2))
        #expect(german[0].end == local(11, 7))
        #expect(german[0].isAllDay)
        let english = try SchoolHolidays.parse(Data(json.utf8), languageCode: "en")
        #expect(english.map(\.title) == ["Autumn holidays", "Weihnachtsferien"])
    }

    @Test func schoolHolidayURLCoversThreeYears() {
        let url = SchoolHolidays.url(for: SchoolHolidayRegion.region(code: "DE-BY")!, around: local(11, 3))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(query.contains(URLQueryItem(name: "subdivisionCode", value: "DE-BY")))
        #expect(query.contains(URLQueryItem(name: "validFrom", value: "2025-01-01")))
        #expect(query.contains(URLQueryItem(name: "validTo", value: "2027-12-31")))
        #expect(SchoolHolidayRegion.matching(.by)?.name == "Bayern")
        #expect(SchoolHolidayRegion.matching(.at) == nil)
        #expect(SchoolHolidayRegion.regions(in: .ch).count == 26)
    }

    @Test func sourcesAndCachePerSource() throws {
        let persistence = try PersistenceController.makeTemporary()
        let repository = Repository(persistence: persistence)
        let personal = repository.ensurePersonalCalendar(name: "Me")
        let family = repository.createFamily(name: "Millers", ownerName: "Anna", ownerUserID: nil, calendarName: "Family")
        let shared = family.calendars!.first!

        let bavaria = SchoolHolidayRegion.region(code: "DE-BY")!
        repository.setSchoolHolidayRegion(bavaria, for: shared)
        repository.setSchoolHolidayRegion(bavaria, for: personal)
        repository.setHolidayRegion(.by, for: personal)
        #expect(repository.addICSSubscription(address: "webcal://example.com/bins.ics", name: "Bins", to: personal) != nil)
        #expect(repository.addICSSubscription(address: "https://example.com/bins.ics", name: nil, to: personal) == nil)
        #expect(repository.addICSSubscription(address: "https://example.com/bins.ics", name: " ", to: shared)?.name
                == "example.com")
        #expect(repository.addICSSubscription(address: "nonsense", name: nil, to: personal) == nil)
        #expect(repository.schoolHolidayRegion(of: personal) == bavaria)

        let sources = repository.subscriptionSources()
        #expect(Set(sources.map(\.sourceKey)) == ["ferien:DE-BY", "ics:https://example.com/bins.ics"])
        #expect(sources.first { $0.kind == .ics }?.url == URL(string: "https://example.com/bins.ics"))

        let fetched = local(11, 3, 8)
        repository.replaceCache(of: "ferien:DE-BY", with: [
            SubscriptionEntry(uid: "a", title: "Herbstferien", start: local(11, 2), end: local(11, 7), isAllDay: true),
        ], fetchedAt: fetched)
        repository.replaceCache(of: "ics:https://example.com/bins.ics", with: [], fetchedAt: fetched)
        try persistence.viewContext.save()
        #expect(repository.lastFetch(of: "ferien:DE-BY") == fetched)
        #expect(repository.lastFetch(of: "ics:https://example.com/bins.ics") == fetched)

        let week = DateInterval(start: local(11, 2), end: local(11, 9))
        let cached = repository.cachedEvents(of: ["ferien:DE-BY", "ics:https://example.com/bins.ics"], overlapping: week)
        #expect(cached.map(\.title) == ["Herbstferien"])
        #expect(cached.first?.objectID.persistentStore == persistence.localStore)

        // Neu laden ersetzt; nicht mehr abonnierte Quellen fliegen raus.
        repository.replaceCache(of: "ferien:DE-BY", with: [
            SubscriptionEntry(uid: "b", title: "Weihnachtsferien", start: local(12, 23), end: local(1, 6, year: 2027),
                              isAllDay: true),
        ])
        repository.setSchoolHolidayRegion(nil, for: personal)
        repository.setSchoolHolidayRegion(nil, for: shared)
        repository.pruneCache(keeping: Set(repository.subscriptionSources().map(\.sourceKey)))
        try persistence.viewContext.save()
        #expect(repository.lastFetch(of: "ferien:DE-BY") == nil)
        #expect(repository.lastFetch(of: "ics:https://example.com/bins.ics") == fetched)
    }
}
