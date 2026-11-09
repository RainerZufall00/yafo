import Foundation

/// Aufträge aus den Widgets an die App. Widgets schreiben nie selbst in Core Data (nur die App
/// synchronisiert mit CloudKit), sondern legen hier ab, was zu tun ist.
/// Die App arbeitet das Postfach beim Start und bei jeder Rückkehr in den Vordergrund ab.
nonisolated public enum InboxAction: Codable, Sendable, Hashable {
    /// Artikel der Einkaufsliste abhaken (`ShoppingItem.id`).
    case checkShoppingItem(UUID)
    /// Todo abhaken; Serien rollen wie in der App weiter (`TodoItem.id`).
    case completeTodo(UUID)

    /// Objekt, das der Auftrag betrifft; Widgets blenden es aus, bis die App ihn erledigt hat.
    public var itemID: UUID? {
        switch self {
        case .checkShoppingItem(let id), .completeTodo(let id): id
        }
    }
}

nonisolated public struct AppGroupInbox: Sendable {
    public struct Entry: Codable, Sendable, Hashable {
        public var createdAt: Date
        public var action: InboxAction
    }

    public let url: URL?

    public init(url: URL? = AppGroupInbox.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: PersistenceController.appGroupIdentifier)?
            .appending(path: "inbox.json")
    }

    /// Hängt einen Auftrag an. Mehrere Prozesse greifen zu, daher koordiniert.
    public func append(_ action: InboxAction, at date: Date = .now) throws {
        try modify { $0.append(Entry(createdAt: date, action: action)) }
    }

    /// Alle offenen Aufträge, ohne sie zu entfernen.
    public func pending() -> [Entry] {
        guard let url else { return [] }
        var entries: [Entry] = []
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { url in
            entries = Self.decode(url)
        }
        return entries
    }

    /// IDs, die gerade auf ihre Erledigung warten.
    public func pendingItemIDs() -> Set<UUID> {
        Set(pending().compactMap(\.action.itemID))
    }

    /// Nimmt alle Aufträge heraus und leert das Postfach.
    public func drain() throws -> [Entry] {
        var taken: [Entry] = []
        try modify { entries in
            taken = entries
            entries.removeAll()
        }
        return taken
    }

    private func modify(_ change: (inout [Entry]) -> Void) throws {
        guard let url else { return }
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { url in
            var entries = Self.decode(url)
            change(&entries)
            do {
                if entries.isEmpty {
                    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                } else {
                    try JSONEncoder().encode(entries).write(to: url, options: .atomic)
                }
            } catch {
                writeError = error
            }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    private static func decode(_ url: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }
}
