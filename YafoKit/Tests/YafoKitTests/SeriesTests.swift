import CoreData
import Foundation
import Testing
@testable import YafoKit

@Suite struct SeriesTests {
    let persistence: PersistenceController
    let repository: Repository
    let calendar: EventCalendar
    let cal = Calendar.current

    init() throws {
        persistence = try PersistenceController.makeTemporary()
        repository = Repository(persistence: persistence)
        calendar = repository.ensurePersonalCalendar(name: "Ich")
    }

    /// Montag in einer festen Woche, damit Wochentage stimmen.
    var monday: Date {
        cal.nextDate(after: cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!,
                     matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)!
    }

    func day(_ offset: Int, _ hour: Int = 16) -> Date {
        cal.date(bySettingHour: hour, minute: 0, second: 0, of: cal.date(byAdding: .day, value: offset, to: monday)!)!
    }

    var fourWeeks: DateInterval { DateInterval(start: monday, end: cal.date(byAdding: .day, value: 28, to: monday)!) }

    func weeklySwimming(_ rule: String = "FREQ=WEEKLY") throws -> Event {
        let event = repository.createEvent(title: "Swimming", start: day(0), end: day(0, 17), isAllDay: false,
                                           in: calendar, recurrenceRule: rule, createdBy: nil)
        try repository.save()
        return event
    }

    func draft(_ occurrence: Occurrence) -> EventDraft {
        EventDraft(title: occurrence.title, start: occurrence.start, end: occurrence.end,
                   isAllDay: occurrence.isAllDay, location: occurrence.location, notes: occurrence.notes,
                   calendar: occurrence.event.calendar!, recurrenceRule: occurrence.event.recurrenceRule)
    }

    func occurrences() -> [Occurrence] {
        repository.occurrences(overlapping: fourWeeks)
    }

    @Test func seriesExpandsInQueries() throws {
        _ = try weeklySwimming()
        #expect(occurrences().map(\.start) == [day(0), day(7), day(14), day(21)])
    }

    @Test func editingOneOccurrenceCreatesAnException() throws {
        let event = try weeklySwimming()
        var changed = draft(occurrences()[1])
        changed.title = "Swimming (pool B)"
        changed.start = day(8)
        changed.end = day(8, 17)
        repository.update(event, occurrence: day(7), with: changed, scope: .thisOccurrence)
        try repository.save()

        let result = occurrences()
        #expect(result.map(\.start) == [day(0), day(8), day(14), day(21)])
        #expect(result[1].title == "Swimming (pool B)")
        #expect(result[1].originalStart == day(7))
        #expect(result[2].title == "Swimming")
        #expect(event.exceptions?.count == 1)
    }

    @Test func exceptionStoresOnlyDifferences() throws {
        let event = try weeklySwimming()
        var changed = draft(occurrences()[1])
        changed.location = "Pool B"
        repository.update(event, occurrence: day(7), with: changed, scope: .thisOccurrence)
        // Danach den Titel der ganzen Serie ändern: greift auch beim Ausnahme-Vorkommen.
        var all = draft(occurrences()[0])
        all.title = "Swim training"
        repository.update(event, occurrence: day(0), with: all, scope: .allOccurrences)
        try repository.save()

        let second = occurrences()[1]
        #expect(second.title == "Swim training")
        #expect(second.location == "Pool B")
        #expect(second.start == day(7))
    }

    @Test func cancellingOneOccurrence() throws {
        let event = try weeklySwimming()
        repository.delete(event, occurrence: day(14), scope: .thisOccurrence)
        try repository.save()
        #expect(occurrences().map(\.start) == [day(0), day(7), day(21)])
    }

    @Test func editingThisAndFollowingSplitsTheSeries() throws {
        let event = try weeklySwimming()
        var changed = draft(occurrences()[2])
        changed.start = day(14, 18)
        changed.end = day(14, 19)
        let following = repository.update(event, occurrence: day(14), with: changed, scope: .thisAndFollowing)
        try repository.save()

        #expect(following != event)
        #expect(occurrences().map(\.start) == [day(0), day(7), day(14, 18), day(21, 18)])
        #expect(event.rule?.until != nil)
    }

    @Test func splittingKeepsTheTotalCount() throws {
        let event = try weeklySwimming("FREQ=WEEKLY;COUNT=3")
        var changed = draft(occurrences()[1])
        changed.title = "Later"
        let following = repository.update(event, occurrence: day(7), with: changed, scope: .thisAndFollowing)
        try repository.save()

        #expect(following.rule?.count == 2)
        #expect(occurrences().map(\.title) == ["Swimming", "Later", "Later"])
    }

    @Test func movingWholeSeriesShiftsExceptions() throws {
        let event = try weeklySwimming()
        repository.delete(event, occurrence: day(7), scope: .thisOccurrence)
        var changed = draft(occurrences()[0])
        changed.start = day(0, 18)
        changed.end = day(0, 19)
        repository.update(event, occurrence: day(0), with: changed, scope: .allOccurrences)
        try repository.save()

        // Das abgesagte Vorkommen bleibt abgesagt.
        #expect(occurrences().map(\.start) == [day(0, 18), day(14, 18), day(21, 18)])
    }

    @Test func deletingThisAndFollowingEndsTheSeries() throws {
        let event = try weeklySwimming()
        repository.delete(event, occurrence: day(14), scope: .thisAndFollowing)
        try repository.save()
        #expect(occurrences().map(\.start) == [day(0), day(7)])
    }

    @Test func deletingFromTheFirstOccurrenceRemovesEverything() throws {
        let event = try weeklySwimming()
        repository.delete(event, occurrence: day(0), scope: .thisAndFollowing)
        try repository.save()
        #expect(occurrences().isEmpty)
    }

    @Test func multiDayOccurrencesStartingBeforeTheWindowAreFound() throws {
        // Jeden Sonntag 22 Uhr bis Montag 2 Uhr.
        repository.createEvent(title: "Night shift", start: day(-1, 22), end: day(0, 2), isAllDay: false,
                               in: calendar, recurrenceRule: "FREQ=WEEKLY", createdBy: nil)
        try repository.save()
        let mondayOnly = DateInterval(start: monday, duration: 86_400)
        #expect(repository.occurrences(overlapping: mondayOnly).count == 1)
    }

    @Test func movingSeriesToAnotherStoreKeepsExceptions() throws {
        let event = try weeklySwimming()
        repository.delete(event, occurrence: day(7), scope: .thisOccurrence)
        let family = repository.createFamily(name: "F", ownerName: "A", ownerUserID: nil, calendarName: "F")
        // Simuliert eine Familie im geteilten Store.
        let shared = repository.insert(EventCalendar.self, into: persistence.sharedStore)
        shared.kindRaw = CalendarKind.shared.rawValue
        _ = family
        var changed = draft(occurrences()[0])
        changed.calendar = shared
        let moved = repository.update(event, occurrence: day(0), with: changed, scope: .allOccurrences)
        try repository.save()

        #expect(persistence.store(of: moved) == persistence.sharedStore)
        #expect(occurrences().map(\.start) == [day(0), day(14), day(21)])
    }
}
