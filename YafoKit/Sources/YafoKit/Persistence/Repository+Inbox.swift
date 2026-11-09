import CoreData
import Foundation

/// Was beim Abarbeiten des Postfachs passiert ist.
nonisolated public struct InboxResult: Equatable, Sendable {
    public var checkedItems = 0
    public var completedTodos = 0
    public var createdEvents = 0
    /// Aufträge, deren Objekt es nicht mehr gibt (z. B. auf einem anderen Gerät gelöscht).
    public var skipped = 0

    public init() {}

    public var changedSomething: Bool { checkedItems + completedTodos + createdEvents > 0 }
}

extension Repository {
    /// Führt Aufträge aus Widgets und Share Extension aus. `createdBy` liefert für neue Termine
    /// den Anlegenden im Zielkalender (wie im Termin-Editor).
    @discardableResult
    public func apply(_ entries: [AppGroupInbox.Entry],
                      createdBy: (EventCalendar) -> String? = { _ in nil }) -> InboxResult {
        var result = InboxResult()
        for entry in entries {
            switch entry.action {
            case .checkShoppingItem(let id):
                if let item = object(ShoppingItem.self, id: id) {
                    if !item.isChecked { setChecked(item, true) }
                    result.checkedItems += 1
                } else {
                    result.skipped += 1
                }
            case .completeTodo(let id):
                if let todo = object(TodoItem.self, id: id), !todo.isDone {
                    complete(todo, today: entry.createdAt)
                    result.completedTodos += 1
                } else {
                    result.skipped += 1
                }
            case .addEvents(let suggestions, let calendarID):
                guard let calendar = object(EventCalendar.self, id: calendarID) else {
                    result.skipped += 1
                    continue
                }
                result.createdEvents += addEvents(suggestions, to: calendar, createdBy: createdBy(calendar)).count
            }
        }
        return result
    }

    /// Übernimmt Vorschläge aus einem Screenshot als neue Termine.
    @discardableResult
    public func addEvents(_ suggestions: [EventSuggestion], to calendar: EventCalendar,
                          createdBy: String?) -> [Event] {
        suggestions.map { suggestion in
            let suggestion = suggestion.normalized()
            let event = createEvent(title: suggestion.title.isEmpty ? String(localized: "New Event") : suggestion.title,
                                    start: suggestion.start, end: suggestion.end, isAllDay: suggestion.isAllDay,
                                    in: calendar, createdBy: createdBy)
            event.location = suggestion.location
            return event
        }
    }
}
