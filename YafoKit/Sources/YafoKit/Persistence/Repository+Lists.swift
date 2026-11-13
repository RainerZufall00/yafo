import CoreData
import Foundation

/// Wem eine Liste gehört: einer Familie (liegt in deren Store) oder nur mir (privater Store).
public enum ListScope: Hashable {
    case personal
    case family(Family)

    public var family: Family? {
        if case .family(let family) = self { return family }
        return nil
    }

    public var predicate: NSPredicate {
        switch self {
        case .personal: NSPredicate(format: "family == nil")
        case .family(let family): NSPredicate(format: "family == %@", family)
        }
    }
}

// MARK: - Einkaufsliste

extension Repository {
    /// Offene Artikel in der Reihenfolge von `sortKey`.
    public func openShoppingItems(in scope: ListScope) -> [ShoppingItem] {
        shoppingItems(in: scope, checked: false, sortedBy: [NSSortDescriptor(key: "sortKey", ascending: true)])
    }

    /// „Zuletzt gekauft“: abgehakte Artikel, neueste zuerst.
    public func recentlyBought(in scope: ListScope, limit: Int = 50) -> [ShoppingItem] {
        Array(shoppingItems(in: scope, checked: true, sortedBy: [NSSortDescriptor(key: "checkedAt", ascending: false)])
            .prefix(limit))
    }

    /// Neuer Artikel am Ende der Liste. Gibt es den Namen schon unter „Zuletzt gekauft“,
    /// kommt dieser Artikel zurück auf die Liste statt eines Duplikats.
    @discardableResult
    public func addShoppingItem(_ name: String, quantity: String? = nil, to scope: ListScope) -> ShoppingItem {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let quantity = quantity.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        let nextKey = (openShoppingItems(in: scope).last?.sortKey ?? 0) + 1
        if let open = openShoppingItems(in: scope).first(where: { Self.sameName($0.name, name) }) {
            if quantity != nil { open.quantity = quantity }
            return open
        }
        let item = recentlyBought(in: scope, limit: .max).first { Self.sameName($0.name, name) }
            ?? newShoppingItem(in: scope)
        item.name = name
        item.quantity = quantity
        item.isChecked = false
        item.checkedAt = nil
        item.sortKey = nextKey
        return item
    }

    public func setChecked(_ item: ShoppingItem, _ isChecked: Bool) {
        guard item.isChecked != isChecked else { return }
        item.isChecked = isChecked
        item.checkedAt = isChecked ? .now : nil
        if !isChecked, let scope = item.listScope {
            item.sortKey = (openShoppingItems(in: scope).filter { $0 != item }.last?.sortKey ?? 0) + 1
        }
    }

    /// Namen aus „Zuletzt gekauft“, die mit `prefix` beginnen und nicht schon auf der Liste stehen.
    public func shoppingSuggestions(for prefix: String, in scope: ListScope, limit: Int = 5) -> [String] {
        let prefix = prefix.trimmingCharacters(in: .whitespaces)
        guard !prefix.isEmpty else { return [] }
        let open = Set(openShoppingItems(in: scope).compactMap { $0.name?.lowercased() })
        var seen = Set<String>()
        return recentlyBought(in: scope, limit: .max).compactMap(\.name).filter { name in
            let key = name.lowercased()
            guard name.range(of: prefix, options: [.caseInsensitive, .anchored, .diacriticInsensitive]) != nil,
                  !open.contains(key), !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
        .prefix(limit).map { $0 }
    }

    /// Neue Reihenfolge der offenen Artikel. Nur geänderte Schlüssel werden geschrieben,
    /// damit der Sync wenig zu tun hat.
    public func reorder(_ items: [ShoppingItem]) {
        for (index, item) in items.enumerated() where item.sortKey != Double(index + 1) {
            item.sortKey = Double(index + 1)
        }
    }

    /// Offene Artikel nach Abteilungen in Laufreihenfolge; innerhalb einer Abteilung nach `sortKey`.
    public func openShoppingItemsByAisle(in scope: ListScope) -> [(category: ShoppingCategory, items: [ShoppingItem])] {
        let grouped = Dictionary(grouping: openShoppingItems(in: scope), by: \.category)
        return ShoppingCategory.allCases.compactMap { category in
            grouped[category].map { (category, $0) }
        }
    }

    /// Abteilung von Hand festlegen; `nil` überlässt sie wieder dem Katalog.
    public func setCategory(_ category: ShoppingCategory?, of item: ShoppingItem) {
        item.categoryRaw = category?.rawValue
    }

    /// Vorschläge beim Tippen: erst „Zuletzt gekauft“, dann der Katalog.
    public func shoppingCompletions(for prefix: String, in scope: ListScope, limit: Int = 8) -> [String] {
        let open = Set(openShoppingItems(in: scope).compactMap { $0.name.map(ShoppingCatalog.normalize) })
        var seen = Set<String>()
        return (shoppingSuggestions(for: prefix, in: scope, limit: limit) + ShoppingCatalog.suggestions(for: prefix))
            .filter { name in
                let key = ShoppingCatalog.normalize(name)
                return !open.contains(key) && seen.insert(key).inserted
            }
            .prefix(limit).map { $0 }
    }

    /// Leert „Zuletzt gekauft“.
    public func clearRecentlyBought(in scope: ListScope) {
        recentlyBought(in: scope, limit: .max).forEach(delete)
    }

    private func newShoppingItem(in scope: ListScope) -> ShoppingItem {
        switch scope {
        case .personal:
            return insert(ShoppingItem.self, into: persistence.privateStore)
        case .family(let family):
            let item = insert(ShoppingItem.self, near: family)
            item.family = family
            return item
        }
    }

    private func shoppingItems(in scope: ListScope, checked: Bool, sortedBy sort: [NSSortDescriptor]) -> [ShoppingItem] {
        let request = NSFetchRequest<ShoppingItem>(entityName: "ShoppingItem")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            scope.predicate, NSPredicate(format: "isChecked == %@", NSNumber(value: checked))
        ])
        request.sortDescriptors = sort + [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    private static func sameName(_ lhs: String?, _ rhs: String) -> Bool {
        lhs?.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

extension ShoppingItem {
    public var category: ShoppingCategory {
        categoryRaw.flatMap(ShoppingCategory.init(rawValue:)) ?? ShoppingCatalog.category(for: name ?? "")
    }

    /// Piktogramm des Katalogartikels; passt die Abteilung nicht (von Hand geändert), das der Abteilung.
    public var emoji: String {
        if let article = ShoppingCatalog.article(for: name ?? ""), article.category == category { return article.emoji }
        return category.emoji
    }

    /// Gezeichnete Grafik, nach derselben Regel wie `emoji`.
    public var icon: String {
        if let article = ShoppingCatalog.article(for: name ?? ""), article.category == category { return article.icon }
        return category.icon
    }

    public var listScope: ListScope? {
        guard managedObjectContext != nil else { return nil }
        return family.map(ListScope.family) ?? .personal
    }
}

// MARK: - Todos

extension Repository {
    /// Offene Todos: fällige zuerst, ohne Datum am Ende.
    public func openTodos(in scope: ListScope) -> [TodoItem] {
        todos(in: scope, done: false).sorted {
            switch ($0.dueDate, $1.dueDate) {
            case let (lhs?, rhs?) where lhs != rhs: lhs < rhs
            case (.some, nil): true
            case (nil, .some): false
            default: ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
            }
        }
    }

    /// Erledigte Todos, zuletzt erledigte zuerst.
    public func doneTodos(in scope: ListScope) -> [TodoItem] {
        todos(in: scope, done: true).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }

    @discardableResult
    public func addTodo(_ title: String, dueDate: Date? = nil, assignee: Member? = nil,
                        recurrenceRule: String? = nil, to scope: ListScope, createdBy: String?) -> TodoItem {
        let todo: TodoItem
        switch scope {
        case .personal:
            todo = insert(TodoItem.self, into: persistence.privateStore)
        case .family(let family):
            todo = insert(TodoItem.self, near: family)
            todo.family = family
        }
        todo.createdBy = createdBy
        update(todo, title: title, dueDate: dueDate, assignee: assignee, recurrenceRule: recurrenceRule)
        return todo
    }

    public func update(_ todo: TodoItem, title: String, dueDate: Date?, assignee: Member?, recurrenceRule: String?) {
        todo.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        todo.dueDate = dueDate.map { Calendar.current.startOfDay(for: $0) }
        // Zuständig nur aus derselben Familie: keine Beziehungen zwischen Stores.
        todo.assignee = assignee.flatMap { $0.family != nil && $0.family == todo.family ? $0 : nil }
        // Ohne Fälligkeit gibt es nichts, worauf eine Serie weiterrollen könnte.
        todo.recurrenceRule = todo.dueDate == nil ? nil : recurrenceRule
    }

    /// Abhaken. Eine Serie rollt auf das nächste Fälligkeitsdatum weiter (mindestens heute)
    /// und bleibt offen; gibt dann das neue Datum zurück.
    @discardableResult
    public func complete(_ todo: TodoItem, today: Date = .now) -> Date? {
        if let next = nextDueDate(of: todo, today: today) {
            todo.dueDate = next
            return next
        }
        todo.isDone = true
        todo.doneAt = .now
        return nil
    }

    public func reopen(_ todo: TodoItem) {
        todo.isDone = false
        todo.doneAt = nil
    }

    public func nextDueDate(of todo: TodoItem, today: Date = .now) -> Date? {
        guard let due = todo.dueDate, let rule = todo.recurrenceRule.flatMap(RecurrenceRule.init(rrule:)) else { return nil }
        let calendar = Calendar.current
        let earliest = max(calendar.date(byAdding: .day, value: 1, to: due)!, calendar.startOfDay(for: today))
        // Bis zu zehn Jahre voraus genügen auch für jährliche Serien mit großem Abstand.
        let horizon = calendar.date(byAdding: .year, value: 10, to: earliest)!
        return rule.startDates(seriesStart: due, from: earliest, to: horizon, calendar: calendar)
            .first { $0 >= earliest }
    }

    /// Löscht alle erledigten Todos der Liste.
    public func clearDoneTodos(in scope: ListScope) {
        doneTodos(in: scope).forEach(delete)
    }

    private func todos(in scope: ListScope, done: Bool) -> [TodoItem] {
        let request = NSFetchRequest<TodoItem>(entityName: "TodoItem")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            scope.predicate, NSPredicate(format: "isDone == %@", NSNumber(value: done))
        ])
        return (try? context.fetch(request)) ?? []
    }
}

extension Repository {
    /// Für `@FetchRequest`: offene Todos, die im Intervall fällig sind.
    public static func duePredicate(_ interval: DateInterval) -> NSPredicate {
        NSPredicate(format: "isDone == NO AND dueDate >= %@ AND dueDate < %@",
                    interval.start as NSDate, interval.end as NSDate)
    }

    /// Verschiebt die Fälligkeit (Drag & Drop im Kalender).
    public func move(_ todo: TodoItem, toDay day: Date) {
        update(todo, title: todo.title ?? "", dueDate: day, assignee: todo.assignee,
               recurrenceRule: todo.recurrenceRule)
    }
}
