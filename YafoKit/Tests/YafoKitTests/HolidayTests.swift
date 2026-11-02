import CoreData
import Foundation
import Testing
@testable import YafoKit

@Suite struct HolidayTests {
    let cal = Calendar.current

    func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func names(_ region: HolidayRegion, _ year: Int) -> [String] {
        Holidays.holidays(in: region, year: year).map(\.germanName)
    }

    @Test func easterDates() {
        #expect(Holidays.easterSunday(year: 2024) == date(2024, 3, 31))
        #expect(Holidays.easterSunday(year: 2025) == date(2025, 4, 20))
        #expect(Holidays.easterSunday(year: 2026) == date(2026, 4, 5))
        #expect(Holidays.easterSunday(year: 2027) == date(2027, 3, 28))
        #expect(Holidays.easterSunday(year: 2038) == date(2038, 4, 25))
    }

    @Test func bavaria2026() {
        let holidays = Holidays.holidays(in: .by, year: 2026)
        #expect(holidays.count == 13)
        #expect(holidays.first { $0.germanName == "Fronleichnam" }?.date == date(2026, 6, 4))
        #expect(holidays.first { $0.germanName == "Christi Himmelfahrt" }?.date == date(2026, 5, 14))
        #expect(names(.by, 2026).contains("Allerheiligen"))
        #expect(!names(.by, 2026).contains("Reformationstag"))
    }

    @Test func stateDifferences() {
        #expect(names(.be, 2026).contains("Internationaler Frauentag"))
        #expect(!names(.be, 2018).contains("Internationaler Frauentag"))
        #expect(names(.hh, 2026).contains("Reformationstag"))
        #expect(!names(.hh, 2017).contains("Reformationstag"))
        #expect(names(.th, 2026).contains("Weltkindertag"))
        #expect(names(.bb, 2026).contains("Ostersonntag"))
        #expect(names(.nw, 2026).count == 11)
        #expect(names(.hb, 2026).count == 10)
    }

    @Test func repentanceDayInSaxony() {
        let day = Holidays.holidays(in: .sn, year: 2026).first { $0.germanName == "Buß- und Bettag" }?.date
        #expect(day == date(2026, 11, 18))
        #expect(Holidays.repentanceDay(year: 2022, calendar: cal) == date(2022, 11, 16))
    }

    @Test func austriaAndSwitzerland() {
        #expect(names(.at, 2026).count == 13)
        #expect(names(.at, 2026).contains("Nationalfeiertag"))
        #expect(names(.ch, 2026).contains("Bundesfeiertag"))
    }

    @Test func subscriptionsPerCalendarAreMergedBySource() throws {
        let persistence = try PersistenceController.makeTemporary()
        let repository = Repository(persistence: persistence)
        let personal = repository.ensurePersonalCalendar(name: "Me")
        let family = repository.createFamily(name: "Millers", ownerName: "Anna", ownerUserID: nil, calendarName: "Family")
        let shared = family.calendars!.first!

        repository.setHolidayRegion(.by, for: shared)
        repository.setHolidayRegion(.by, for: personal)
        #expect(repository.holidayRegion(of: shared) == .by)
        #expect(repository.activeHolidayRegions() == [.by])
        #expect(repository.calendarsSubscribed(to: .by, except: personal) == [shared])

        let may = DateInterval(start: date(2026, 5, 1), end: date(2026, 6, 1))
        let holidays = repository.holidays(overlapping: may)
        #expect(holidays[date(2026, 5, 1)]?.count == 1)
        #expect(holidays.keys.count == 3)

        repository.setHolidayRegion(.he, for: personal)
        #expect(repository.activeHolidayRegions() == [.by, .he])
        repository.setAppearance(of: shared, isVisible: false)
        #expect(repository.activeHolidayRegions() == [.he])
        repository.setHolidayRegion(nil, for: personal)
        #expect(repository.activeHolidayRegions().isEmpty)
        #expect((personal.subscriptions ?? []).isEmpty)
    }
}
