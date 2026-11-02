import CoreData
import Foundation

// NSManagedObject-Unterklassen zum Modell in `YafoModel`.
// Regeln für das CloudKit-Schema (siehe docs/): alle Beziehungen optional, keine geordneten
// Beziehungen, keine Unique Constraints, Attribute optional oder mit Standardwert.
// Nach dem ersten Produktiv-Deployment nur noch erweitern, nie umbenennen oder löschen.

nonisolated public final class Family: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var members: Set<Member>?
    @NSManaged public var calendars: Set<EventCalendar>?
    @NSManaged public var shoppingItems: Set<ShoppingItem>?
    @NSManaged public var todoItems: Set<TodoItem>?
    @NSManaged public var ownerTransfers: Set<OwnerTransfer>?
}

nonisolated public final class Member: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var displayName: String?
    @NSManaged public var initials: String?
    @NSManaged public var kindRaw: String?
    /// Record-Name des Apple Accounts; fehlt bei Kinderprofilen.
    @NSManaged public var cloudKitUserID: String?
    @NSManaged public var leftAt: Date?
    @NSManaged public var createdAt: Date?
    @NSManaged public var family: Family?
    @NSManaged public var events: Set<Event>?
    @NSManaged public var comments: Set<Comment>?
    @NSManaged public var assignedTodos: Set<TodoItem>?
}

nonisolated public final class EventCalendar: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var kindRaw: String?
    /// Standardfarbe als Hex (#RRGGBB); jeder Nutzer kann sie per `CalendarAppearance` überschreiben.
    @NSManaged public var defaultColor: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var family: Family?
    @NSManaged public var events: Set<Event>?
    @NSManaged public var subscriptions: Set<CalendarSubscription>?
}

nonisolated public final class Event: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var start: Date?
    @NSManaged public var end: Date?
    @NSManaged public var isAllDay: Bool
    @NSManaged public var timeZone: String?
    @NSManaged public var location: String?
    @NSManaged public var notes: String?
    /// RRULE nach RFC 5545, z. B. `FREQ=WEEKLY;BYDAY=MO`.
    @NSManaged public var recurrenceRule: String?
    /// `id` des anlegenden Members bzw. CloudKit-User-ID im privaten Store.
    @NSManaged public var createdBy: String?
    @NSManaged public var importUID: String?
    /// Sekunden vor Beginn; bei Ganztagsterminen vor 0 Uhr des Tages.
    @NSManaged public var defaultAlertOffset: Double
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    /// `EventKind`, z. B. Geburtstag.
    @NSManaged public var kindRaw: String?
    /// Geburtsjahr bei Geburtstagen, 0 = unbekannt.
    @NSManaged public var birthYear: Int64
    @NSManaged public var calendar: EventCalendar?
    /// Leer bedeutet: ganze Familie.
    @NSManaged public var participants: Set<Member>?
    @NSManaged public var exceptions: Set<EventException>?
    @NSManaged public var comments: Set<Comment>?
}

nonisolated public final class EventException: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var originalDate: Date?
    @NSManaged public var isCancelled: Bool
    @NSManaged public var title: String?
    @NSManaged public var start: Date?
    @NSManaged public var end: Date?
    @NSManaged public var location: String?
    @NSManaged public var notes: String?
    @NSManaged public var event: Event?
}

nonisolated public final class Comment: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var text: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var editedAt: Date?
    @NSManaged public var author: Member?
    @NSManaged public var event: Event?
}

nonisolated public final class ShoppingItem: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var quantity: String?
    @NSManaged public var isChecked: Bool
    @NSManaged public var checkedAt: Date?
    @NSManaged public var sortKey: Double
    /// Von Hand gewählte Abteilung (`ShoppingCategory`); `nil` = aus dem Katalog.
    @NSManaged public var categoryRaw: String?
    @NSManaged public var createdAt: Date?
    /// `nil` bedeutet private Liste („Nur ich“).
    @NSManaged public var family: Family?
}

nonisolated public final class TodoItem: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var dueDate: Date?
    @NSManaged public var isDone: Bool
    @NSManaged public var doneAt: Date?
    @NSManaged public var createdBy: String?
    @NSManaged public var recurrenceRule: String?
    @NSManaged public var defaultAlertOffset: Double
    @NSManaged public var createdAt: Date?
    @NSManaged public var assignee: Member?
    /// `nil` bedeutet private Liste („Nur ich“).
    @NSManaged public var family: Family?
}

nonisolated public final class CalendarSubscription: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    /// Eindeutiger Schlüssel der Quelle, z. B. `ferien:DE-BY` oder die normalisierte URL.
    @NSManaged public var sourceKey: String?
    @NSManaged public var url: String?
    @NSManaged public var kindRaw: String?
    @NSManaged public var region: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var calendar: EventCalendar?
}

/// Lokaler Cache abonnierter Termine, pro Quelle statt pro Kalender. Nicht in CloudKit.
nonisolated public final class SubscribedEvent: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var sourceKey: String?
    @NSManaged public var uid: String?
    @NSManaged public var title: String?
    @NSManaged public var start: Date?
    @NSManaged public var end: Date?
    @NSManaged public var isAllDay: Bool
    @NSManaged public var fetchedAt: Date?
}

nonisolated public final class CalendarAppearance: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    /// `id` des Kalenders als Text (Verweis über Stores hinweg).
    @NSManaged public var calendarID: String?
    @NSManaged public var color: String?
    @NSManaged public var isVisible: Bool
}

nonisolated public final class AlertPreference: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var itemID: String?
    @NSManaged public var alertOffset: Double
    @NSManaged public var isMuted: Bool
}

nonisolated public final class ReadState: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var familyID: String?
    @NSManaged public var lastSeenAt: Date?
}

nonisolated public final class OwnerTransfer: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var newOwnerID: String?
    @NSManaged public var statusRaw: String?
    @NSManaged public var newShareURL: String?
    @NSManaged public var startedAt: Date?
    @NSManaged public var family: Family?
}
