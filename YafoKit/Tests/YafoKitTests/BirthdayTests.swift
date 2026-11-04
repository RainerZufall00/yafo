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

    // MARK: - Import aus Kontakten

    @Test func matchesSameDayAndYearButNotOtherYear() {
        repository.createBirthday(name: "Oma Gisela", day: date(2026, 5, 3), birthYear: 1950,
                                  in: calendar, createdBy: nil)
        let same = BirthdayCandidate(id: "c1", name: "Gisela Müller", month: 5, day: 3, year: 1950)
        let other = BirthdayCandidate(id: "c2", name: "Gisela Müller", month: 5, day: 3, year: 1951)
        let noYear = BirthdayCandidate(id: "c3", name: "Gisela", month: 5, day: 3, year: nil)
        let otherDay = BirthdayCandidate(id: "c4", name: "Oma Gisela", month: 5, day: 4, year: 1950)
        #expect(repository.matchingBirthdays(for: same).map(\.title) == ["Oma Gisela"])
        #expect(repository.matchingBirthdays(for: other).isEmpty)
        #expect(repository.matchingBirthdays(for: noYear).count == 1)
        #expect(repository.matchingBirthdays(for: otherDay).isEmpty)
    }

    @Test func reimportUpdatesInsteadOfDuplicating() throws {
        let ben = BirthdayCandidate(id: "c9", name: "Ben", month: 7, day: 1, year: 1988)
        let first = repository.importBirthday(ben, into: calendar, createdBy: nil)
        try repository.save()
        var renamed = ben
        renamed.name = "Ben Miller"
        let second = repository.importBirthday(renamed, into: calendar, createdBy: nil)
        try repository.save()
        #expect(first == second)
        #expect(calendar.events?.count == 1)
        #expect(second.title == "Ben Miller")
        #expect(second.occurrences(overlapping: year(2026)).first?.age == 38)
        #expect(repository.matchingBirthdays(for: ben).first == second)
    }

    @Test func leapDayWithoutYearKeepsTheDay() {
        let lea = BirthdayCandidate(id: "c5", name: "Lea", month: 2, day: 29, year: nil)
        let day = lea.day(calendar: cal, now: date(2027, 6, 1))
        #expect(day == date(2024, 2, 29))
        let event = repository.importBirthday(lea, into: calendar, createdBy: nil)
        #expect(event.occurrences(overlapping: year(2028)).map(\.start) == [date(2028, 2, 29)])
        #expect(repository.matchingBirthdays(for: lea).count == 1)
    }

    // MARK: - Alter

    @Test func ageCountsFromBirthdayOn() {
        let born = date(1988, 7, 1)
        #expect(Birthday.age(birthDate: born, now: date(2026, 6, 30), calendar: cal) == 37)
        #expect(Birthday.age(birthDate: born, now: date(2026, 7, 1), calendar: cal) == 38)
    }

    @Test func birthDateFromAgeKeepsDayAndMonth() {
        let now = date(2026, 11, 4)
        // Geburtstag schon gewesen: 38 Jahre → 1988.
        #expect(Birthday.birthDate(sameDayAs: date(2026, 7, 1), age: 38, now: now, calendar: cal) == date(1988, 7, 1))
        // Geburtstag kommt noch: wer jetzt 73 ist, wird am 22.11. 74 → 1952.
        #expect(Birthday.birthDate(sameDayAs: date(2026, 11, 22), age: 73, now: now, calendar: cal) == date(1952, 11, 22))
        // Heute Geburtstag zählt schon.
        #expect(Birthday.birthDate(sameDayAs: date(2000, 11, 4), age: 10, now: now, calendar: cal) == date(2016, 11, 4))
    }

    @Test func latestPastKeepsTheDayInsteadOfToday() {
        let now = date(2026, 11, 4)
        #expect(Birthday.latestPast(sameDayAs: date(2026, 11, 22), now: now, calendar: cal) == date(2025, 11, 22))
        #expect(Birthday.latestPast(sameDayAs: date(2026, 3, 14), now: now, calendar: cal) == date(2026, 3, 14))
        // 29. Februar in einem Nicht-Schaltjahr: der 28.
        #expect(Birthday.latestPast(sameDayAs: date(2028, 2, 29), now: now, calendar: cal) == date(2026, 2, 28))
    }
}
