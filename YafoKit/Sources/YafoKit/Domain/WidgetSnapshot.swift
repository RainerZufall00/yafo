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

    public var generatedAt: Date
    public var items: [Item]

    public init(generatedAt: Date, items: [Item]) {
        self.generatedAt = generatedAt
        self.items = items
    }

    public static let empty = WidgetSnapshot(generatedAt: .distantPast, items: [])

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
