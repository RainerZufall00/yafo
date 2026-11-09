import Foundation

/// Die nächsten Termine als kleine Datei in der App Group. Die App schreibt sie nach jedem
/// Speichern und Sync, das Widget liest nur sie und greift nie selbst auf Core Data zu.
nonisolated public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public struct Item: Codable, Sendable, Hashable, Identifiable {
        public var id: String
        public var title: String
        public var start: Date
        public var end: Date
        public var isAllDay: Bool
        public var colorHex: String
        public var calendarName: String
        public var location: String?
        public var isBirthday: Bool
        public var age: Int?
        public var initials: [String]

        public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, colorHex: String,
                    calendarName: String, location: String?, isBirthday: Bool, age: Int?, initials: [String]) {
            self.id = id
            self.title = title
            self.start = start
            self.end = end
            self.isAllDay = isAllDay
            self.colorHex = colorHex
            self.calendarName = calendarName
            self.location = location
            self.isBirthday = isBirthday
            self.age = age
            self.initials = initials
        }
    }

    /// Offener Artikel der Einkaufsliste, schon in Laufreihenfolge.
    public struct ShoppingEntry: Codable, Sendable, Hashable, Identifiable {
        public var id: UUID
        public var name: String
        public var quantity: String?
        public var emoji: String
        public var icon: String
        public var colorHex: String

        public init(id: UUID, name: String, quantity: String?, emoji: String, icon: String, colorHex: String) {
            self.id = id
            self.name = name
            self.quantity = quantity
            self.emoji = emoji
            self.icon = icon
            self.colorHex = colorHex
        }
    }

    /// Offenes Todo, fällige zuerst.
    public struct TodoEntry: Codable, Sendable, Hashable, Identifiable {
        public var id: UUID
        public var title: String
        public var dueDate: Date?
        public var assigneeInitials: String?
        public var isRecurring: Bool

        public init(id: UUID, title: String, dueDate: Date?, assigneeInitials: String?, isRecurring: Bool) {
            self.id = id
            self.title = title
            self.dueDate = dueDate
            self.assigneeInitials = assigneeInitials
            self.isRecurring = isRecurring
        }
    }

    /// Einkauf und Todos einer Liste. `key` wie in der App: `id` der Familie oder „personal“.
    public struct ListEntry: Codable, Sendable, Hashable, Identifiable {
        public var key: String
        public var name: String
        public var isPersonal: Bool
        public var shoppingCount: Int
        public var shopping: [ShoppingEntry]
        public var todoCount: Int
        public var todos: [TodoEntry]
        public var id: String { key }

        public init(key: String, name: String, isPersonal: Bool, shoppingCount: Int, shopping: [ShoppingEntry],
                    todoCount: Int, todos: [TodoEntry]) {
            self.key = key
            self.name = name
            self.isPersonal = isPersonal
            self.shoppingCount = shoppingCount
            self.shopping = shopping
            self.todoCount = todoCount
            self.todos = todos
        }
    }

    /// Kalender, in die die Share Extension Termine aus Screenshots legen darf.
    public struct CalendarEntry: Codable, Sendable, Hashable, Identifiable {
        public var id: UUID
        public var name: String
        public var colorHex: String
        public var familyName: String?

        public init(id: UUID, name: String, colorHex: String, familyName: String?) {
            self.id = id
            self.name = name
            self.colorHex = colorHex
            self.familyName = familyName
        }
    }

    public var generatedAt: Date
    public var items: [Item]
    public var lists: [ListEntry]
    public var calendars: [CalendarEntry]
    /// Liste, die in der App zuletzt gewählt war; Vorgabe für nicht eingerichtete Widgets.
    public var defaultListKey: String?

    public init(generatedAt: Date, items: [Item], lists: [ListEntry] = [], calendars: [CalendarEntry] = [],
                defaultListKey: String? = nil) {
        self.generatedAt = generatedAt
        self.items = items
        self.lists = lists
        self.calendars = calendars
        self.defaultListKey = defaultListKey
    }

    /// Ältere Schnappschüsse ohne Listen und Kalender bleiben lesbar.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        items = try container.decode([Item].self, forKey: .items)
        lists = try container.decodeIfPresent([ListEntry].self, forKey: .lists) ?? []
        calendars = try container.decodeIfPresent([CalendarEntry].self, forKey: .calendars) ?? []
        defaultListKey = try container.decodeIfPresent(String.self, forKey: .defaultListKey)
    }

    public static let empty = WidgetSnapshot(generatedAt: .distantPast, items: [])

    /// Liste zum Schlüssel; ohne passenden die zuletzt in der App gewählte, sonst die erste.
    public func list(for key: String?) -> ListEntry? {
        lists.first { $0.key == key } ?? lists.first { $0.key == defaultListKey } ?? lists.first
    }

    /// Termine, die ab `date` noch laufen oder kommen, in Anzeigereihenfolge.
    public func upcoming(from date: Date) -> [Item] {
        items.filter { $0.end > date }
    }

    // MARK: Datei

    public static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: PersistenceController.appGroupIdentifier)?
            .appending(path: "widget-snapshot.json")
    }

    public static func load(from url: URL? = fileURL) -> WidgetSnapshot {
        guard let url, let data = try? Data(contentsOf: url) else { return .empty }
        return (try? JSONDecoder().decode(WidgetSnapshot.self, from: data)) ?? .empty
    }

    public func write(to url: URL? = Self.fileURL) throws {
        guard let url else { return }
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
