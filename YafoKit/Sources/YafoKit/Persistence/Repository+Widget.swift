import CoreData
import Foundation

extension Repository {
    /// Sichtbare Termine von heute bis `days` Tage voraus, Ganztägiges je Tag zuerst.
    /// `listKey` ist die in der App gewählte Liste (Vorgabe für die Listen-Widgets).
    public func widgetSnapshot(now: Date = .now, days: Int = 14, limit: Int = 40,
                               listKey: String? = nil) -> WidgetSnapshot {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let interval = DateInterval(start: start, end: calendar.date(byAdding: .day, value: days, to: start)!)
        let items = occurrences(overlapping: interval)
            .filter { occurrence in
                occurrence.end > now && occurrence.event.calendar.map(isVisible) ?? false
            }
            .sorted {
                let lhsDay = calendar.startOfDay(for: max($0.start, start))
                let rhsDay = calendar.startOfDay(for: max($1.start, start))
                return (lhsDay, $0.isAllDay ? 0 : 1, $0.start) < (rhsDay, $1.isAllDay ? 0 : 1, $1.start)
            }
            .prefix(limit)
            .map { occurrence in
                let event = occurrence.event
                return WidgetSnapshot.Item(
                    id: "\(event.id?.uuidString ?? "")-\(Int(occurrence.originalStart.timeIntervalSince1970))",
                    title: occurrence.title, start: occurrence.start, end: occurrence.end,
                    isAllDay: occurrence.isAllDay,
                    colorHex: event.calendar.map(color(of:)) ?? CalendarColors.personalDefault,
                    calendarName: event.calendar?.name ?? "", location: occurrence.location,
                    isBirthday: event.isBirthday, age: occurrence.age,
                    initials: (event.participants ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
                        .compactMap(\.initials))
            }
        return WidgetSnapshot(generatedAt: now, items: Array(items), lists: widgetLists(),
                              calendars: widgetCalendars(), defaultListKey: listKey)
    }

    /// Je Familie und „Nur ich“ die offenen Artikel und Todos, gekürzt auf das, was ein großes
    /// Widget zeigen kann; die Gesamtzahl steht daneben.
    func widgetLists(limit: Int = 24) -> [WidgetSnapshot.ListEntry] {
        let scopes: [ListScope] = families().map(ListScope.family) + [.personal]
        return scopes.map { scope in
            let shopping = openShoppingItemsByAisle(in: scope).flatMap { $0.items }
            let todos = openTodos(in: scope)
            return WidgetSnapshot.ListEntry(
                key: scope.family?.id?.uuidString ?? "personal",
                name: scope.family?.name ?? String(localized: "Just me"),
                isPersonal: scope.family == nil,
                shoppingCount: shopping.count,
                shopping: shopping.prefix(limit).compactMap { item in
                    item.id.map {
                        WidgetSnapshot.ShoppingEntry(id: $0, name: item.name ?? "", quantity: item.quantity,
                                                     emoji: item.emoji, icon: item.icon,
                                                     colorHex: item.category.colorHex)
                    }
                },
                todoCount: todos.count,
                todos: todos.prefix(limit).compactMap { todo in
                    todo.id.map {
                        WidgetSnapshot.TodoEntry(id: $0, title: todo.title ?? "", dueDate: todo.dueDate,
                                                 assigneeInitials: todo.assignee?.initials,
                                                 isRecurring: todo.recurrenceRule != nil)
                    }
                })
        }
    }

    func widgetCalendars() -> [WidgetSnapshot.CalendarEntry] {
        calendars().compactMap { calendar in
            calendar.id.map {
                WidgetSnapshot.CalendarEntry(id: $0, name: calendar.name ?? "", colorHex: color(of: calendar),
                                             familyName: calendar.family?.name)
            }
        }
    }
}
