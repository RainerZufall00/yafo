import CoreData
import Foundation

extension Repository {
    /// Sichtbare Termine von heute bis `days` Tage voraus, je Tag erst Ganztägiges, dann nach Uhrzeit,
    /// dann (mit `includeTodos`) die an dem Tag fälligen Todos; überfällige stehen bei heute.
    /// `listKey` ist die in der App gewählte Liste (Vorgabe für die Listen-Widgets).
    public func widgetSnapshot(now: Date = .now, days: Int = 14, limit: Int = 40,
                               listKey: String? = nil, includeTodos: Bool = true) -> WidgetSnapshot {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let interval = DateInterval(start: start, end: calendar.date(byAdding: .day, value: days, to: start)!)
        let events = occurrences(overlapping: interval)
            .filter { occurrence in
                occurrence.end > now && occurrence.event.calendar.map(isVisible) ?? false
            }
            .map { occurrence in
                let event = occurrence.event
                return WidgetSnapshot.Item(
                    id: "\(event.id?.uuidString ?? "")-\(Int(occurrence.originalStart.timeIntervalSince1970))",
                    title: occurrence.title, start: occurrence.start, end: occurrence.end,
                    isAllDay: occurrence.isAllDay,
                    colorHex: color(of: event),
                    calendarName: event.calendar?.name ?? "", location: occurrence.location,
                    isBirthday: event.isBirthday, age: occurrence.age,
                    initials: (event.participants ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
                        .compactMap(\.initials))
            }
        let todos = includeTodos ? widgetTodos(dueBefore: interval.end) : []
        // Rang je Tag: 0 ganztägig, 1 mit Uhrzeit, 2 Todo.
        func rank(_ item: WidgetSnapshot.Item) -> Int { item.isTodo ? 2 : item.isAllDay ? 0 : 1 }
        let items = (events + todos)
            .sorted {
                let lhsDay = calendar.startOfDay(for: max($0.start, start))
                let rhsDay = calendar.startOfDay(for: max($1.start, start))
                return (lhsDay, rank($0), $0.start, $0.title) < (rhsDay, rank($1), $1.start, $1.title)
            }
            .prefix(limit)
        return WidgetSnapshot(generatedAt: now, items: Array(items), lists: widgetLists(),
                              calendars: widgetCalendars(), defaultListKey: listKey)
    }

    /// Offene Todos mit Fälligkeit vor `end` (auch überfällige) als ganztägige Einträge in der Farbe
    /// des Familienkalenders bzw. des eigenen Kalenders.
    func widgetTodos(dueBefore end: Date) -> [WidgetSnapshot.Item] {
        let request = NSFetchRequest<TodoItem>(entityName: "TodoItem")
        request.predicate = NSPredicate(format: "isDone == NO AND dueDate != nil AND dueDate < %@", end as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "dueDate", ascending: true)]
        let todos = (try? context.fetch(request)) ?? []
        guard !todos.isEmpty else { return [] }
        let calendars = calendars()
        let personalColor = calendars.first { $0.kind == .personal }.map(color(of:)) ?? CalendarColors.personalDefault
        var familyColors: [NSManagedObjectID: String] = [:]
        for calendar in calendars {
            if let family = calendar.family, familyColors[family.objectID] == nil {
                familyColors[family.objectID] = color(of: calendar)
            }
        }
        let calendar = Calendar.current
        return todos.compactMap { todo in
            guard let id = todo.id, let due = todo.dueDate else { return nil }
            let day = calendar.startOfDay(for: due)
            return WidgetSnapshot.Item(
                id: "todo-\(id.uuidString)", title: todo.title ?? "", start: day,
                end: calendar.date(byAdding: .day, value: 1, to: day)!, isAllDay: true,
                colorHex: todo.family.flatMap { familyColors[$0.objectID] } ?? personalColor,
                calendarName: todo.family?.name ?? String(localized: "Just me"), location: nil,
                isBirthday: false, age: nil, initials: todo.assignee?.initials.map { [$0] } ?? [],
                todoID: id, isRecurring: todo.recurrenceRule != nil)
        }
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
