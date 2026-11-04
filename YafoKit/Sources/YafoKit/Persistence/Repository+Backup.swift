import CoreData
import Foundation

/// Vollständiges Backup als JSON: Familien, Mitglieder, Kalender, Termine samt Ausnahmen,
/// Teilnehmer, Kommentare, Listen, Abos und eigene Farben. Verweise laufen über die `id`,
/// damit eine Wiederherstellung nichts doppelt anlegt.
nonisolated public struct Backup: Codable, Equatable, Sendable {
    public static let format = "yafo-backup"
    public static let currentVersion = 1

    public var format = Backup.format
    public var version = Backup.currentVersion
    public var createdAt: Date
    public var families: [FamilyData] = []
    public var members: [MemberData] = []
    public var calendars: [CalendarData] = []
    public var events: [EventData] = []
    public var comments: [CommentData] = []
    public var shoppingItems: [ShoppingData] = []
    public var todos: [TodoData] = []
    public var subscriptions: [SubscriptionData] = []
    public var appearances: [AppearanceData] = []
    public var alertPreferences: [AlertData] = []

    public struct FamilyData: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String?
        public var createdAt: Date?
    }

    public struct MemberData: Codable, Equatable, Sendable {
        public var id: UUID
        public var familyID: UUID
        public var displayName: String?
        public var initials: String?
        public var kind: String?
        public var cloudKitUserID: String?
        public var leftAt: Date?
        public var createdAt: Date?
    }

    public struct CalendarData: Codable, Equatable, Sendable {
        public var id: UUID
        public var familyID: UUID?
        public var name: String?
        public var kind: String?
        public var defaultColor: String?
        public var createdAt: Date?
    }

    public struct ExceptionData: Codable, Equatable, Sendable {
        public var id: UUID
        public var originalDate: Date?
        public var isCancelled: Bool
        public var title: String?
        public var start: Date?
        public var end: Date?
        public var location: String?
        public var notes: String?
    }

    public struct EventData: Codable, Equatable, Sendable {
        public var id: UUID
        public var calendarID: UUID
        public var title: String?
        public var start: Date?
        public var end: Date?
        public var isAllDay: Bool
        public var timeZone: String?
        public var location: String?
        public var notes: String?
        public var recurrenceRule: String?
        public var createdBy: String?
        public var importUID: String?
        public var defaultAlertOffset: Double
        public var kind: String?
        public var birthYear: Int64
        public var createdAt: Date?
        public var updatedAt: Date?
        public var participantIDs: [UUID]
        public var exceptions: [ExceptionData]
        /// Fehlt in älteren Backups.
        public var geo: String? = nil
    }

    public struct CommentData: Codable, Equatable, Sendable {
        public var id: UUID
        public var eventID: UUID
        public var authorID: UUID?
        public var text: String?
        public var createdAt: Date?
        public var editedAt: Date?
    }

    public struct ShoppingData: Codable, Equatable, Sendable {
        public var id: UUID
        public var familyID: UUID?
        public var name: String?
        public var quantity: String?
        public var isChecked: Bool
        public var checkedAt: Date?
        public var sortKey: Double
        public var category: String?
        public var createdAt: Date?
    }

    public struct TodoData: Codable, Equatable, Sendable {
        public var id: UUID
        public var familyID: UUID?
        public var title: String?
        public var dueDate: Date?
        public var isDone: Bool
        public var doneAt: Date?
        public var createdBy: String?
        public var recurrenceRule: String?
        public var defaultAlertOffset: Double
        public var assigneeID: UUID?
        public var createdAt: Date?
    }

    public struct SubscriptionData: Codable, Equatable, Sendable {
        public var id: UUID
        public var calendarID: UUID
        public var kind: String?
        public var sourceKey: String?
        public var url: String?
        public var region: String?
        public var name: String?
        public var createdAt: Date?
    }

    public struct AppearanceData: Codable, Equatable, Sendable {
        public var id: UUID
        public var calendarID: String?
        public var color: String?
        public var isVisible: Bool
    }

    public struct AlertData: Codable, Equatable, Sendable {
        public var id: UUID
        public var itemID: String?
        public var alertOffset: Double
        public var isMuted: Bool
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Backup.timestamp(date))
        }
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> Backup {
        let decoder = JSONDecoder()
        // ISO 8601 mit oder ohne Sekundenbruchteile.
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)
                .timeZone(separator: .omitted)) ?? Date(text, strategy: .iso8601) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date \(text)"))
        }
        let backup = try decoder.decode(Backup.self, from: data)
        guard backup.format == format else { throw BackupError.notABackup }
        guard backup.version <= currentVersion else { throw BackupError.newerVersion }
        return backup
    }

    /// UTC mit Millisekunden, gerundet statt abgeschnitten, damit Lesen und erneutes
    /// Schreiben denselben Text ergibt.
    static func timestamp(_ date: Date) -> String {
        let milliseconds = Int((date.timeIntervalSince1970 * 1000).rounded())
        let seconds = Int((Double(milliseconds) / 1000).rounded(.down))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let base = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
        return base + String(format: ".%03dZ", milliseconds - seconds * 1000)
    }

    /// Dateiname wie `yafo-Backup 2026-11-03 0815.json`.
    public static func fileName(at date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return "yafo-Backup \(formatter.string(from: date)).json"
    }
}

public enum BackupError: LocalizedError {
    case notABackup
    case newerVersion

    public var errorDescription: String? {
        switch self {
        case .notABackup: String(localized: "This file is not a yafo backup.")
        case .newerVersion: String(localized: "This backup is from a newer version of yafo. Please update the app.")
        }
    }
}

/// Was die Wiederherstellung angelegt bzw. als schon vorhanden übersprungen hat.
nonisolated public struct RestoreResult: Equatable, Sendable {
    public var created = 0
    public var skipped = 0
    /// Familien, die es nicht mehr gab und die jetzt neu beim Wiederherstellenden liegen.
    public var newFamilies: [String] = []
}

extension Repository {
    // MARK: Backup erstellen

    public func makeBackup(scope: ExportScope = .all, now: Date = .now) -> Backup {
        var backup = Backup(createdAt: now)
        let families = families().filter { scope.includes($0) }
        for family in families {
            guard let id = family.id else { continue }
            backup.families.append(.init(id: id, name: family.name, createdAt: family.createdAt))
            for member in family.members ?? [] {
                guard let memberID = member.id else { continue }
                backup.members.append(.init(id: memberID, familyID: id, displayName: member.displayName,
                                            initials: member.initials, kind: member.kindRaw,
                                            cloudKitUserID: member.cloudKitUserID, leftAt: member.leftAt,
                                            createdAt: member.createdAt))
            }
        }

        let calendars = calendars(in: scope)
        for calendar in calendars {
            guard let calendarID = calendar.id else { continue }
            backup.calendars.append(.init(id: calendarID, familyID: calendar.family?.id, name: calendar.name,
                                          kind: calendar.kindRaw, defaultColor: calendar.defaultColor,
                                          createdAt: calendar.createdAt))
            for subscription in calendar.subscriptions ?? [] {
                guard let subscriptionID = subscription.id else { continue }
                backup.subscriptions.append(.init(id: subscriptionID, calendarID: calendarID, kind: subscription.kindRaw,
                                                  sourceKey: subscription.sourceKey, url: subscription.url,
                                                  region: subscription.region, name: subscription.name,
                                                  createdAt: subscription.createdAt))
            }
            for event in (calendar.events ?? []).sorted(by: { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }) {
                guard let eventID = event.id else { continue }
                let exceptions = (event.exceptions ?? []).compactMap { exception -> Backup.ExceptionData? in
                    exception.id.map {
                        .init(id: $0, originalDate: exception.originalDate, isCancelled: exception.isCancelled,
                              title: exception.title, start: exception.start, end: exception.end,
                              location: exception.location, notes: exception.notes)
                    }
                }.sorted { ($0.originalDate ?? .distantPast) < ($1.originalDate ?? .distantPast) }
                backup.events.append(.init(id: eventID, calendarID: calendarID, title: event.title, start: event.start,
                                           end: event.end, isAllDay: event.isAllDay, timeZone: event.timeZone,
                                           location: event.location, notes: event.notes,
                                           recurrenceRule: event.recurrenceRule, createdBy: event.createdBy,
                                           importUID: event.importUID, defaultAlertOffset: event.defaultAlertOffset,
                                           kind: event.kindRaw, birthYear: event.birthYear, createdAt: event.createdAt,
                                           updatedAt: event.updatedAt,
                                           participantIDs: (event.participants ?? []).compactMap(\.id).sorted { $0.uuidString < $1.uuidString },
                                           exceptions: exceptions, geo: event.geo))
                for comment in event.comments ?? [] {
                    guard let commentID = comment.id else { continue }
                    backup.comments.append(.init(id: commentID, eventID: eventID, authorID: comment.author?.id,
                                                 text: comment.text, createdAt: comment.createdAt,
                                                 editedAt: comment.editedAt))
                }
            }
        }
        backup.comments.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }

        backup.shoppingItems = shoppingItems(in: scope).compactMap { item in
            item.id.map {
                .init(id: $0, familyID: item.family?.id, name: item.name, quantity: item.quantity,
                      isChecked: item.isChecked, checkedAt: item.checkedAt, sortKey: item.sortKey,
                      category: item.categoryRaw, createdAt: item.createdAt)
            }
        }
        backup.todos = todoItems(in: scope).compactMap { item in
            item.id.map {
                .init(id: $0, familyID: item.family?.id, title: item.title, dueDate: item.dueDate, isDone: item.isDone,
                      doneAt: item.doneAt, createdBy: item.createdBy, recurrenceRule: item.recurrenceRule,
                      defaultAlertOffset: item.defaultAlertOffset, assigneeID: item.assignee?.id,
                      createdAt: item.createdAt)
            }
        }

        let calendarIDs = Set(calendars.compactMap { $0.id?.uuidString })
        backup.appearances = all(CalendarAppearance.self).compactMap { appearance in
            guard let id = appearance.id, let calendarID = appearance.calendarID, calendarIDs.contains(calendarID)
            else { return nil }
            return .init(id: id, calendarID: calendarID, color: appearance.color, isVisible: appearance.isVisible)
        }
        let itemIDs = Set(backup.events.map(\.id.uuidString) + backup.todos.map(\.id.uuidString))
        backup.alertPreferences = all(AlertPreference.self).compactMap { preference in
            guard let id = preference.id, let itemID = preference.itemID, itemIDs.contains(itemID) else { return nil }
            return .init(id: id, itemID: itemID, alertOffset: preference.alertOffset, isMuted: preference.isMuted)
        }
        return backup
    }

    // MARK: Wiederherstellen

    /// Legt an, was es noch nicht gibt (erkannt an der `id`), und lässt Vorhandenes unverändert.
    /// Familien, die nicht mehr erreichbar sind, entstehen neu im privaten Store; man wird
    /// ihr Owner und lädt die anderen neu ein. Der eigene Kalender wird mit dem vorhandenen
    /// zusammengeführt.
    @discardableResult
    public func restore(_ backup: Backup, personalCalendarName: String) -> RestoreResult {
        var result = RestoreResult()
        var families: [UUID: Family] = [:]
        var members: [UUID: Member] = [:]
        var calendars: [UUID: EventCalendar] = [:]
        var events: [UUID: Event] = [:]

        for data in backup.families {
            if let existing = object(Family.self, id: data.id) {
                families[data.id] = existing
                result.skipped += 1
                continue
            }
            let family = insert(Family.self, into: persistence.privateStore)
            family.id = data.id
            family.name = data.name
            family.createdAt = data.createdAt ?? family.createdAt
            families[data.id] = family
            result.newFamilies.append(data.name ?? "")
            result.created += 1
        }

        for data in backup.members {
            if let existing = object(Member.self, id: data.id) {
                members[data.id] = existing
                result.skipped += 1
                continue
            }
            guard let family = families[data.familyID] else { continue }
            let member = insert(Member.self, near: family)
            member.id = data.id
            member.displayName = data.displayName
            member.initials = data.initials
            member.kindRaw = data.kind
            member.cloudKitUserID = data.cloudKitUserID
            member.leftAt = data.leftAt
            member.createdAt = data.createdAt ?? member.createdAt
            member.family = family
            members[data.id] = member
            result.created += 1
        }

        for data in backup.calendars {
            if let existing = object(EventCalendar.self, id: data.id) {
                calendars[data.id] = existing
                result.skipped += 1
                continue
            }
            if data.familyID == nil && data.kind == CalendarKind.personal.rawValue {
                // Den eigenen Kalender gibt es genau einmal; Termine kommen in den vorhandenen.
                calendars[data.id] = ensurePersonalCalendar(name: data.name ?? personalCalendarName)
                continue
            }
            let family = data.familyID.flatMap { families[$0] }
            if data.familyID != nil && family == nil { continue }
            let calendar = family.map { insert(EventCalendar.self, near: $0) }
                ?? insert(EventCalendar.self, into: persistence.privateStore)
            calendar.id = data.id
            calendar.name = data.name
            calendar.kindRaw = data.kind
            calendar.defaultColor = data.defaultColor
            calendar.createdAt = data.createdAt ?? calendar.createdAt
            calendar.family = family
            calendars[data.id] = calendar
            result.created += 1
        }

        for data in backup.subscriptions {
            guard object(CalendarSubscription.self, id: data.id) == nil, let calendar = calendars[data.calendarID],
                  !(calendar.subscriptions ?? []).contains(where: { $0.sourceKey == data.sourceKey && $0.kindRaw == data.kind })
            else { result.skipped += 1; continue }
            let subscription = insert(CalendarSubscription.self, near: calendar)
            subscription.id = data.id
            subscription.kindRaw = data.kind
            subscription.sourceKey = data.sourceKey
            subscription.url = data.url
            subscription.region = data.region
            subscription.name = data.name
            subscription.createdAt = data.createdAt ?? subscription.createdAt
            subscription.calendar = calendar
            result.created += 1
        }

        for data in backup.events {
            if let existing = object(Event.self, id: data.id) {
                events[data.id] = existing
                result.skipped += 1
                continue
            }
            guard let calendar = calendars[data.calendarID] else { continue }
            let event = insert(Event.self, near: calendar)
            event.id = data.id
            event.title = data.title
            event.start = data.start
            event.end = data.end
            event.isAllDay = data.isAllDay
            event.timeZone = data.timeZone
            event.location = data.location
            event.geo = data.geo
            event.notes = data.notes
            event.recurrenceRule = data.recurrenceRule
            event.createdBy = data.createdBy
            event.importUID = data.importUID
            event.defaultAlertOffset = data.defaultAlertOffset
            event.kindRaw = data.kind
            event.birthYear = data.birthYear
            event.createdAt = data.createdAt ?? event.createdAt
            event.updatedAt = data.updatedAt
            event.calendar = calendar
            // Teilnehmer nur aus derselben Familie (Beziehungen gehen nicht über Stores).
            event.participants = Set(data.participantIDs.compactMap { members[$0] }
                .filter { $0.family != nil && $0.family == calendar.family })
            for exceptionData in data.exceptions {
                let exception = insert(EventException.self, near: event)
                exception.id = exceptionData.id
                exception.originalDate = exceptionData.originalDate
                exception.isCancelled = exceptionData.isCancelled
                exception.title = exceptionData.title
                exception.start = exceptionData.start
                exception.end = exceptionData.end
                exception.location = exceptionData.location
                exception.notes = exceptionData.notes
                exception.event = event
            }
            events[data.id] = event
            result.created += 1
        }

        for data in backup.comments {
            guard object(Comment.self, id: data.id) == nil, let event = events[data.eventID] else {
                result.skipped += 1
                continue
            }
            let comment = insert(Comment.self, near: event)
            comment.id = data.id
            comment.text = data.text
            comment.createdAt = data.createdAt ?? comment.createdAt
            comment.editedAt = data.editedAt
            comment.author = data.authorID.flatMap { members[$0] }.flatMap {
                $0.family == event.calendar?.family ? $0 : nil
            }
            comment.event = event
            result.created += 1
        }

        for data in backup.shoppingItems {
            guard object(ShoppingItem.self, id: data.id) == nil else { result.skipped += 1; continue }
            let family = data.familyID.flatMap { families[$0] }
            if data.familyID != nil && family == nil { continue }
            let item = family.map { insert(ShoppingItem.self, near: $0) }
                ?? insert(ShoppingItem.self, into: persistence.privateStore)
            item.id = data.id
            item.name = data.name
            item.quantity = data.quantity
            item.isChecked = data.isChecked
            item.checkedAt = data.checkedAt
            item.sortKey = data.sortKey
            item.categoryRaw = data.category
            item.createdAt = data.createdAt ?? item.createdAt
            item.family = family
            result.created += 1
        }

        for data in backup.todos {
            guard object(TodoItem.self, id: data.id) == nil else { result.skipped += 1; continue }
            let family = data.familyID.flatMap { families[$0] }
            if data.familyID != nil && family == nil { continue }
            let item = family.map { insert(TodoItem.self, near: $0) }
                ?? insert(TodoItem.self, into: persistence.privateStore)
            item.id = data.id
            item.title = data.title
            item.dueDate = data.dueDate
            item.isDone = data.isDone
            item.doneAt = data.doneAt
            item.createdBy = data.createdBy
            item.recurrenceRule = data.recurrenceRule
            item.defaultAlertOffset = data.defaultAlertOffset
            item.createdAt = data.createdAt ?? item.createdAt
            item.family = family
            item.assignee = data.assigneeID.flatMap { members[$0] }.flatMap { $0.family == family && family != nil ? $0 : nil }
            result.created += 1
        }

        // Eigene Farben und Erinnerungen: nur, wenn es für den Kalender bzw. Eintrag noch keine gibt.
        let knownAppearances = Set(all(CalendarAppearance.self).compactMap(\.calendarID))
        for data in backup.appearances where object(CalendarAppearance.self, id: data.id) == nil {
            guard let calendarID = data.calendarID, !knownAppearances.contains(calendarID) else { continue }
            let appearance = insert(CalendarAppearance.self, into: persistence.privateStore)
            appearance.id = data.id
            appearance.calendarID = calendarID
            appearance.color = data.color
            appearance.isVisible = data.isVisible
        }
        let knownAlerts = Set(all(AlertPreference.self).compactMap(\.itemID))
        for data in backup.alertPreferences where object(AlertPreference.self, id: data.id) == nil {
            guard let itemID = data.itemID, !knownAlerts.contains(itemID) else { continue }
            let preference = insert(AlertPreference.self, into: persistence.privateStore)
            preference.id = data.id
            preference.itemID = itemID
            preference.alertOffset = data.alertOffset
            preference.isMuted = data.isMuted
        }
        return result
    }

    // MARK: Hilfen

    func object<T: NSManagedObject>(_ type: T.Type, id: UUID) -> T? {
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    func all<T: NSManagedObject>(_ type: T.Type) -> [T] {
        (try? context.fetch(NSFetchRequest<T>(entityName: String(describing: type)))) ?? []
    }
}

extension ExportScope {
    func includes(_ family: Family) -> Bool {
        switch self {
        case .all: true
        case .personal: false
        case .family(let chosen): family == chosen
        }
    }
}
