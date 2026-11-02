import CoreData
import Foundation
import Testing
@testable import YafoKit

@Suite struct BirthdayTests {
    let persistence: PersistenceController
    let repository: Repository
    let calendar: EventCalendar
    let cal = Calendar.current

    init() throws {
        persistence = try PersistenceController.makeTemporary()
        repository = Repository(persistence: persistence)
        calendar = repository.ensurePersonalCalendar(name: "Ich")
    }

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func year(_ year: Int) -> DateInterval {
        DateInterval(start: date(year, 1, 1), end: date(year + 1, 1, 1))
    }

    @Test func ageCountsUpEveryYear() throws {
        let anna = repository.createBirthday(name: "Anna", day: date(2026, 3, 14), birthYear: 1991,
                                             in: calendar, createdBy: nil)
        try repository.save()
        #expect(anna.isBirthday && anna.isAllDay)
        #expect(anna.start == date(1991, 3, 14))

        let in2026 = anna.occurrences(overlapping: year(2026))
        #expect(in2026.map(\.start) == [date(2026, 3, 14)])
        #expect(in2026.first?.age == 35)
        #expect(anna.occurrences(overlapping: year(2027)).first?.age == 36)
        #expect(anna.occurrences(overlapping: year(1991)).first?.age == 0)
        #expect(anna.occurrences(overlapping: year(1990)).isEmpty)
        #expect(repository.occurrences(overlapping: year(2030)).map(\.title) == ["Anna"])
    }

    @Test func withoutBirthYearThereIsNoAge() throws {
        let ben = repository.createBirthday(name: "Ben", day: date(2026, 7, 1), birthYear: nil,
                                            in: calendar, createdBy: nil)
        #expect(ben.birthYear == 0)
        #expect(ben.occurrences(overlapping: year(2028)).first?.age == nil)
        #expect(ben.occurrences(overlapping: year(2028)).first?.start == date(2028, 7, 1))
    }

    @Test func leapDayBirthdayFallsOnLastDayOfFebruary() {
        let lea = repository.createBirthday(name: "Lea", day: date(2000, 2, 29), birthYear: 2000,
                                            in: calendar, createdBy: nil)
        #expect(lea.occurrences(overlapping: year(2027)).map(\.start) == [date(2027, 2, 28)])
        #expect(lea.occurrences(overlapping: year(2028)).map(\.start) == [date(2028, 2, 29)])
        #expect(lea.occurrences(overlapping: year(2027)).first?.age == 27)
    }

    @Test func leapDayWithoutBirthYearInCommonYear() {
        let start = Birthday.seriesStart(day: date(2028, 2, 29), birthYear: 2027)
        #expect(start == date(2027, 2, 28))
    }

    @Test func updateChangesDateAndYear() throws {
        let anna = repository.createBirthday(name: "Anna", day: date(2026, 3, 14), birthYear: 1991,
                                             in: calendar, createdBy: nil)
        repository.updateBirthday(anna, name: "Anna M.", day: date(2026, 4, 2), birthYear: 1990,
                                  calendar: calendar, notes: nil)
        let next = anna.occurrences(overlapping: year(2026))
        #expect(next.map(\.start) == [date(2026, 4, 2)])
        #expect(next.first?.title == "Anna M.")
        #expect(next.first?.age == 36)
    }

    @Test func normalEventsAreNoBirthdays() {
        let event = repository.createEvent(title: "Dentist", start: date(2026, 3, 1), end: date(2026, 3, 2),
                                           isAllDay: true, in: calendar, createdBy: nil)
        #expect(event.kind == .event)
        #expect(event.occurrences(overlapping: year(2026)).first?.age == nil)
    }
}
