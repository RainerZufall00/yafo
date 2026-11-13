import CoreData
import Foundation
import Testing
@testable import YafoKit

@Suite struct BirthdayDetectorTests {
    let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 13))!

    func guess(_ title: String) -> BirthdayDetector.Guess? {
        BirthdayDetector.guess(title: title, now: now)
    }

    @Test func recognizesCommonTitles() {
        #expect(guess("Geburtstag Oma") == .init(name: "Oma"))
        #expect(guess("Geburtstag von Max Mustermann") == .init(name: "Max Mustermann"))
        #expect(guess("Anna hat Geburtstag") == .init(name: "Anna"))
        #expect(guess("Max Mustermann's birthday") == .init(name: "Max Mustermann"))
        #expect(guess("Birthday: Lisa") == .init(name: "Lisa"))
        #expect(guess("Paul 40. Geburtstag") == .init(name: "Paul"))
        #expect(guess("Onkel Jens wird 50 - Geburtstag") == .init(name: "Onkel Jens"))
        #expect(guess("Tante Inges Geburtstag") == .init(name: "Tante Inges"))
    }

    @Test func readsTheBirthYear() {
        #expect(guess("🎂 Lena (1990)") == .init(name: "Lena", birthYear: 1990))
        #expect(guess("Geb. Tante Inge *1956") == .init(name: "Tante Inge", birthYear: 1956))
        // Ein Jahr in der Zukunft ist kein Geburtsjahr.
        #expect(guess("Geburtstag Mia 2030")?.birthYear == nil)
    }

    @Test func ignoresPartiesAndOtherEvents() {
        #expect(guess("Kindergeburtstag Paul") == nil)
        #expect(guess("Geburtstagsfeier Opa") == nil)
        #expect(guess("Geburtstagsparty bei Lisa") == nil)
        #expect(guess("Geschenk für Mama besorgen – Geburtstag") == nil)
        #expect(guess("Arbeit") == nil)
        #expect(guess("Gebäudereinigung") == nil)
        #expect(guess("Geburtstag") == nil)
    }
}

@Suite struct BirthdaySuggestionTests {
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

    @discardableResult
    func allDay(_ title: String, _ day: Date, rule: String? = nil) -> Event {
        repository.createEvent(title: title, start: day, end: cal.date(byAdding: .day, value: 1, to: day)!,
                               isAllDay: true, in: calendar, recurrenceRule: rule, createdBy: nil)
    }

    @Test func groupsOneEventPerYearIntoOneSuggestion() throws {
        allDay("Geburtstag Oma", date(2024, 5, 3))
        allDay("Geburtstag Oma", date(2025, 5, 3))
        allDay("Geburtstag Oma", date(2026, 5, 3))
        allDay("Geburtstag Opa", date(2026, 8, 1))
        allDay("Urlaub", date(2026, 7, 1))
        repository.createEvent(title: "Geburtstag Max", start: date(2026, 9, 1).addingTimeInterval(15 * 3600),
                               end: date(2026, 9, 1).addingTimeInterval(17 * 3600), isAllDay: false,
                               in: calendar, createdBy: nil)
        try repository.save()

        let suggestions = repository.birthdaySuggestions()
        #expect(suggestions.map(\.name) == ["Oma", "Opa"])
        #expect(suggestions[0].events.count == 3)
        #expect(suggestions[0].event.start == date(2024, 5, 3))
    }

    @Test func convertingMakesAYearlyBirthdayAndRemovesDuplicates() throws {
        allDay("Geburtstag Oma (1950)", date(2025, 5, 3))
        allDay("Geburtstag Oma", date(2026, 5, 3))
        try repository.save()

        let suggestion = try #require(repository.birthdaySuggestions().first)
        #expect(suggestion.birthYear == 1950)
        let birthday = try #require(repository.convertToBirthday(suggestion))
        try repository.save()

        #expect(birthday.isBirthday && birthday.title == "Oma" && birthday.birthYear == 1950)
        #expect(birthday.start == date(1950, 5, 3))
        let in2027 = birthday.occurrences(overlapping: DateInterval(start: date(2027, 1, 1), end: date(2028, 1, 1)))
        #expect(in2027.first?.age == 77)
        #expect(repository.occurrences(overlapping: DateInterval(start: date(2026, 1, 1), end: date(2027, 1, 1)))
            .map(\.title) == ["Oma"])
        #expect(repository.birthdaySuggestions().isEmpty)
    }

    @Test func dismissedSuggestionsStayHidden() throws {
        let event = allDay("Lisa's birthday", date(2026, 2, 2), rule: "FREQ=YEARLY")
        try repository.save()
        #expect(repository.birthdaySuggestion(for: event)?.name == "Lisa")
        #expect(repository.birthdaySuggestions(dismissed: [event.id!.uuidString]).isEmpty)
    }

    @Test func birthdayColorDefaultsToOwnColorAndCanFollowTheCalendar() throws {
        let birthday = repository.createBirthday(name: "Anna", day: date(2026, 3, 14), birthYear: nil,
                                                 in: calendar, createdBy: nil)
        #expect(repository.color(of: birthday) == CalendarColors.birthdayDefault)
        repository.setBirthdayColor(nil)
        #expect(repository.color(of: birthday) == repository.color(of: calendar))
        repository.setBirthdayColor("#123456")
        #expect(repository.birthdayColor() == "#123456")
        #expect(repository.color(of: birthday) == "#123456")
    }
}

@Suite struct MoveTests {
    let persistence: PersistenceController
    let repository: Repository
    let calendar: EventCalendar
    let cal = Calendar.current

    init() throws {
        persistence = try PersistenceController.makeTemporary()
        repository = Repository(persistence: persistence)
        calendar = repository.ensurePersonalCalendar(name: "Ich")
    }

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func movingKeepsTimeAndDuration() throws {
        let event = repository.createEvent(title: "Arzt", start: date(2026, 11, 12, 8), end: date(2026, 11, 12, 9),
                                           isAllDay: false, in: calendar, createdBy: nil)
        repository.move(event, occurrence: event.start!, toDay: date(2026, 11, 14))
        #expect(event.start == date(2026, 11, 14, 8))
        #expect(event.end == date(2026, 11, 14, 9))
    }

    @Test func movingOneOccurrenceCreatesAnException() throws {
        let event = repository.createEvent(title: "Sport", start: date(2026, 11, 2, 17), end: date(2026, 11, 2, 18),
                                           isAllDay: false, in: calendar, recurrenceRule: "FREQ=WEEKLY", createdBy: nil)
        let second = date(2026, 11, 9, 17)
        repository.move(event, occurrence: second, toDay: date(2026, 11, 11), scope: .thisOccurrence)
        #expect(event.start == date(2026, 11, 2, 17))
        let week = DateInterval(start: date(2026, 11, 9), end: date(2026, 11, 16))
        #expect(event.occurrences(overlapping: week).map(\.start) == [date(2026, 11, 11, 17)])
        #expect(event.exception(for: second)?.title == nil)
    }

    @Test func movingAllOccurrencesShiftsTheSeries() throws {
        let event = repository.createEvent(title: "Sport", start: date(2026, 11, 2, 17), end: date(2026, 11, 2, 18),
                                           isAllDay: false, in: calendar, recurrenceRule: "FREQ=WEEKLY", createdBy: nil)
        repository.move(event, occurrence: date(2026, 11, 9, 17), toDay: date(2026, 11, 10), scope: .allOccurrences)
        #expect(event.start == date(2026, 11, 3, 17))
    }

    @Test func movingABirthdayKeepsTheYearOfBirth() throws {
        let anna = repository.createBirthday(name: "Anna", day: date(1991, 3, 14), birthYear: 1991,
                                             in: calendar, createdBy: nil)
        repository.move(anna, occurrence: date(2026, 3, 14), toDay: date(2026, 3, 16))
        #expect(anna.start == date(1991, 3, 16))
        #expect(anna.birthYear == 1991)
    }
}
