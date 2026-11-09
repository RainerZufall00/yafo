import CoreData
import Foundation
import Testing
@testable import YafoKit

@Suite struct InboxTests {
    let persistence: PersistenceController
    let repository: Repository
    let family: Family
    let inbox: AppGroupInbox

    init() throws {
        persistence = try PersistenceController.makeTemporary()
        repository = Repository(persistence: persistence)
        family = repository.createFamily(name: "Millers", ownerName: "Anna", ownerUserID: "anna", calendarName: "Family")
        inbox = AppGroupInbox(url: FileManager.default.temporaryDirectory
            .appending(path: "inbox-\(UUID().uuidString).json"))
    }

    @Test func appendAndDrain() throws {
        let id = UUID()
        try inbox.append(.checkShoppingItem(id))
        try inbox.append(.completeTodo(UUID()))
        #expect(inbox.pending().count == 2)
        #expect(inbox.pendingItemIDs().contains(id))

        let drained = try inbox.drain()
        #expect(drained.map(\.action).first == .checkShoppingItem(id))
        #expect(inbox.pending().isEmpty)
        #expect(try inbox.drain().isEmpty)
    }

    @Test func eventSuggestionsSurviveTheRoundTrip() throws {
        let calendarID = UUID()
        let suggestion = EventSuggestion(title: "Zoo", start: .now, end: .now.addingTimeInterval(3600), isAllDay: false,
                                         location: "Hellabrunn")
        try inbox.append(.addEvents([suggestion], calendarID: calendarID))
        let action = try #require(try inbox.drain().first?.action)
        #expect(action == .addEvents([suggestion], calendarID: calendarID))
    }

    @Test func applyChecksItemsAndCompletesTodos() throws {
        let milk = repository.addShoppingItem("Milk", to: .family(family))
        let todo = repository.addTodo("Take out trash", to: .family(family), createdBy: nil)
        try repository.save()

        let result = repository.apply([
            .init(createdAt: .now, action: .checkShoppingItem(try #require(milk.id))),
            .init(createdAt: .now, action: .completeTodo(try #require(todo.id))),
            .init(createdAt: .now, action: .completeTodo(UUID())),
        ])
        #expect(result.checkedItems == 1 && result.completedTodos == 1 && result.skipped == 1)
        #expect(milk.isChecked)
        #expect(todo.isDone)
    }

    @Test func applyRollsRecurringTodosForward() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let todo = repository.addTodo("Water plants", dueDate: today, recurrenceRule: "FREQ=WEEKLY",
                                      to: .family(family), createdBy: nil)
        repository.apply([.init(createdAt: .now, action: .completeTodo(try #require(todo.id)))])
        #expect(!todo.isDone)
        #expect(todo.dueDate == calendar.date(byAdding: .day, value: 7, to: today))
    }

    @Test func applyCreatesEventsInTheChosenCalendar() throws {
        let target = try #require(family.calendars?.first)
        let start = Calendar.current.date(byAdding: .day, value: 3, to: .now)!
        let suggestions = [
            EventSuggestion(title: " Summer party ", start: start, end: start.addingTimeInterval(7200), isAllDay: false,
                            location: "Garden"),
            EventSuggestion(title: "Holidays", start: start, end: start, isAllDay: true),
        ]
        let result = repository.apply([.init(createdAt: .now,
                                             action: .addEvents(suggestions, calendarID: try #require(target.id)))],
                                      createdBy: { _ in "member-1" })
        #expect(result.createdEvents == 2)
        let events = (target.events ?? []).sorted { ($0.isAllDay ? 1 : 0) < ($1.isAllDay ? 1 : 0) }
        #expect(events.map(\.title) == ["Summer party", "Holidays"])
        #expect(events.first?.location == "Garden")
        #expect(events.first?.createdBy == "member-1")
        let allDay = try #require(events.last)
        #expect(allDay.end == Calendar.current.date(byAdding: .day, value: 1, to: allDay.start!))
    }

    @Test func snapshotCarriesListsAndCalendars() throws {
        repository.addShoppingItem("Milk", quantity: "2 l", to: .family(family))
        repository.addShoppingItem("Bread", to: .family(family))
        repository.addTodo("Call grandma", to: .personal, createdBy: nil)
        try repository.save()

        let snapshot = repository.widgetSnapshot(listKey: "personal")
        let familyList = try #require(snapshot.list(for: family.id?.uuidString))
        #expect(familyList.name == "Millers" && !familyList.isPersonal)
        #expect(familyList.shoppingCount == 2)
        // Laufreihenfolge: Backwaren vor Kühlregal.
        #expect(familyList.shopping.map(\.name) == ["Bread", "Milk"])
        #expect(familyList.shopping.last?.quantity == "2 l")
        #expect(snapshot.list(for: nil)?.key == "personal")
        #expect(snapshot.list(for: "personal")?.todos.map(\.title) == ["Call grandma"])
        #expect(snapshot.calendars.contains { $0.familyName == "Millers" })

        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
    }

    @Test func oldSnapshotsWithoutListsStillDecode() throws {
        let json = #"{"generatedAt": 0, "items": []}"#
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.lists.isEmpty && snapshot.calendars.isEmpty)
    }
}

@Suite struct EventSuggestionTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func modelOutputWithTimes() throws {
        let s = try #require(EventSuggestion.fromModel(title: "Elternabend", start: "2026-11-20T19:30",
                                                       end: "2026-11-20T21:00", isAllDay: false,
                                                       location: " Aula ", calendar: calendar))
        #expect(s.start == date(2026, 11, 20, 19, 30))
        #expect(s.end == date(2026, 11, 20, 21))
        #expect(!s.isAllDay && s.location == "Aula")
    }

    @Test func modelOutputWithoutEndLastsAnHour() throws {
        let s = try #require(EventSuggestion.fromModel(title: "Arzt", start: "2026-11-20T09:00", end: "",
                                                       isAllDay: false, location: "", calendar: calendar))
        #expect(s.end == date(2026, 11, 20, 10))
        #expect(s.location == nil)
    }

    @Test func modelOutputAllDayEndsTheNextMorning() throws {
        let s = try #require(EventSuggestion.fromModel(title: "Ferienlager", start: "2026-07-01", end: "2026-07-03",
                                                       isAllDay: false, location: "", calendar: calendar))
        #expect(s.isAllDay)
        #expect(s.start == date(2026, 7, 1))
        #expect(s.end == date(2026, 7, 4))
    }

    @Test func unreadableStartGivesNothing() {
        #expect(EventSuggestion.fromModel(title: "x", start: "next Friday", end: "", isAllDay: false, location: "",
                                          calendar: calendar) == nil)
    }

    @Test func detectsTimeInText() {
        #expect(EventSuggestionDetector.containsTime("Friday 15:30"))
        #expect(EventSuggestionDetector.containsTime("am 3. Mai um 15.30 Uhr"))
        #expect(EventSuggestionDetector.containsTime("3 pm"))
        #expect(EventSuggestionDetector.containsTime("um 15 Uhr"))
        #expect(!EventSuggestionDetector.containsTime("14.03.2026"))
        #expect(!EventSuggestionDetector.containsTime("March 14, 2026"))
    }

    @Test func dataDetectorFindsAnEnglishDate() throws {
        let now = date(2026, 3, 1, 12)
        let text = "Invitation\nBirthday party on March 14, 2026 at 3:00 PM\nRSVP to Anna"
        let suggestions = EventSuggestionDetector.suggestions(in: text, now: now, calendar: calendar)
        let first = try #require(suggestions.first)
        #expect(!first.isAllDay)
        #expect(first.title.localizedCaseInsensitiveContains("Birthday party"))
    }

    @Test func titlesLoseFillerWords() {
        #expect(EventSuggestionDetector.clean("Birthday party on ") == "Birthday party")
        #expect(EventSuggestionDetector.clean(" – Elternabend am") == "Elternabend")
        #expect(EventSuggestionDetector.clean("Sommerfest, ") == "Sommerfest")
    }

    @Test func dataDetectorSkipsPastDates() {
        let now = date(2026, 3, 1, 12)
        let text = "Sent on January 2, 2026"
        #expect(EventSuggestionDetector.suggestions(in: text, now: now, calendar: calendar).isEmpty)
    }
}
