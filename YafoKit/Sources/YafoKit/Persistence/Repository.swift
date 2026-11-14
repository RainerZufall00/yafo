import CoreData
import Foundation

/// Lese- und Schreibzugriffe auf das Modell, immer über den `viewContext`.
/// Legt jedes neue Objekt im richtigen Store an: Familien beim Owner im privaten Store,
/// alles andere im Store des Objekts, an dem es hängt.
public final class Repository {
    public let persistence: PersistenceController
    public var context: NSManagedObjectContext { persistence.viewContext }

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    public func save() throws {
        try persistence.save()
    }

    // MARK: - Familien

    public func families() -> [Family] {
        fetch(Family.self, sortedBy: [NSSortDescriptor(keyPath: \Family.name, ascending: true)])
    }

    /// Legt eine Familie mit dem Anlegenden als erwachsenem Owner und einem geteilten Kalender an.
    @discardableResult
    public func createFamily(name: String, ownerName: String, ownerUserID: String?,
                             calendarName: String) -> Family {
        let family = insert(Family.self, into: persistence.privateStore)
        family.name = name
        addMember(name: ownerName, kind: .adult, userID: ownerUserID, to: family)
        addSharedCalendar(name: calendarName, to: family)
        return family
    }

    @discardableResult
    public func addMember(name: String, kind: MemberKind, userID: String?, to family: Family) -> Member {
        let member = insert(Member.self, near: family)
        member.displayName = name
        member.initials = Initials.make(from: name)
        member.kindRaw = kind.rawValue
        member.cloudKitUserID = userID
        member.family = family
        return member
    }

    /// Kinderprofil ohne eigenen Zugang.
    @discardableResult
    public func addChildProfile(name: String, to family: Family) -> Member {
        addMember(name: name, kind: .child, userID: nil, to: family)
    }

    /// Nach dem Annehmen einer Einladung: eigenes Profil anlegen oder ein bestehendes
    /// Kinderprofil mit dem Account verknüpfen (Teenager). Bisherige Teilnahmen bleiben.
    @discardableResult
    public func join(_ family: Family, userID: String, name: String, linking profile: Member? = nil) -> Member {
        if let profile {
            profile.cloudKitUserID = userID
            return profile
        }
        return addMember(name: name, kind: .adult, userID: userID, to: family)
    }

    /// Das eigene Profil in einer Familie, erkannt an der CloudKit-User-ID.
    public func me(in family: Family, userID: String?) -> Member? {
        guard let userID else { return nil }
        return family.members?.first { $0.cloudKitUserID == userID && $0.leftAt == nil }
    }

    /// Familien aus dem geteilten Store, in denen man noch kein Profil hat.
    public func familiesNeedingProfile(userID: String?) -> [Family] {
        guard let userID else { return [] }
        return families().filter { persistence.isInSharedStore($0) && me(in: $0, userID: userID) == nil }
    }

    /// Austritt: Profil bleibt mit „(ehemalig)“ erhalten, damit Termine und Kommentare lesbar bleiben.
    public func markLeft(_ member: Member) {
        member.leftAt = .now
    }

    public func activeMembers(of family: Family) -> [Member] {
        (family.members ?? [])
            .filter { $0.leftAt == nil }
            .sorted { ($0.kind == .adult ? 0 : 1, $0.createdAt ?? .distantPast)
                    < ($1.kind == .adult ? 0 : 1, $1.createdAt ?? .distantPast) }
    }

    // MARK: - Kalender

    /// Den eigenen Kalender gibt es genau einmal, im privaten Store.
    @discardableResult
    public func ensurePersonalCalendar(name: String) -> EventCalendar {
        let request = makeRequest(EventCalendar.self)
        request.predicate = NSPredicate(format: "kindRaw == %@ AND family == nil", CalendarKind.personal.rawValue)
        request.affectedStores = [persistence.privateStore]
        request.sortDescriptors = [NSSortDescriptor(keyPath: \EventCalendar.createdAt, ascending: true)]
        if let existing = (try? context.fetch(request))?.first {
            return existing
        }
        let calendar = insert(EventCalendar.self, into: persistence.privateStore)
        calendar.name = name
        calendar.kindRaw = CalendarKind.personal.rawValue
        calendar.defaultColor = CalendarColors.personalDefault
        return calendar
    }

    /// Legen zwei Geräte vor dem ersten Sync je einen eigenen Kalender an, bleibt der älteste;
    /// die Termine der anderen ziehen dorthin um.
    public func mergeDuplicatePersonalCalendars() {
        let request = makeRequest(EventCalendar.self)
        request.predicate = NSPredicate(format: "kindRaw == %@ AND family == nil", CalendarKind.personal.rawValue)
        request.affectedStores = [persistence.privateStore]
        request.sortDescriptors = [NSSortDescriptor(keyPath: \EventCalendar.createdAt, ascending: true)]
        guard let calendars = try? context.fetch(request), let keeper = calendars.first else { return }
        for duplicate in calendars.dropFirst() {
            for event in duplicate.events ?? [] {
                event.calendar = keeper
            }
            context.delete(duplicate)
        }
    }

    @discardableResult
    public func addSharedCalendar(name: String, to family: Family) -> EventCalendar {
        let existing = (family.calendars ?? []).filter { $0.kind == .shared }.count
        let calendar = insert(EventCalendar.self, near: family)
        calendar.name = name
        calendar.kindRaw = CalendarKind.shared.rawValue
        calendar.defaultColor = CalendarColors.defaultColor(for: .shared, existingSharedCount: existing)
        calendar.family = family
        return calendar
    }

    public func calendars() -> [EventCalendar] {
        fetch(EventCalendar.self, sortedBy: [NSSortDescriptor(keyPath: \EventCalendar.createdAt, ascending: true)])
            .sorted { ($0.kind == .personal ? 0 : 1) < ($1.kind == .personal ? 0 : 1) }
    }

    /// Eigene Farbe und Sichtbarkeit pro Kalender, nur für einen selbst.
    public func appearance(for calendar: EventCalendar) -> CalendarAppearance? {
        guard let id = calendar.id?.uuidString else { return nil }
        let request = makeRequest(CalendarAppearance.self)
        request.predicate = NSPredicate(format: "calendarID == %@", id)
        request.affectedStores = [persistence.privateStore]
        return (try? context.fetch(request))?.first
    }

    public func color(of calendar: EventCalendar) -> String {
        appearance(for: calendar)?.color ?? calendar.defaultColor ?? CalendarColors.sharedDefault
    }

    public func isVisible(_ calendar: EventCalendar) -> Bool {
        appearance(for: calendar)?.isVisible ?? true
    }

    public func eventStyle(of calendar: EventCalendar) -> EventStyle {
        appearance(for: calendar)?.eventStyle ?? .outlined
    }

    public func setAppearance(of calendar: EventCalendar, color: String? = nil, isVisible: Bool? = nil,
                              eventStyle: EventStyle? = nil) {
        let appearance = appearance(for: calendar) ?? {
            let new = insert(CalendarAppearance.self, into: persistence.privateStore)
            new.calendarID = calendar.id?.uuidString
            return new
        }()
        if let color { appearance.color = color }
        if let isVisible { appearance.isVisible = isVisible }
        if let eventStyle { appearance.eventStyle = eventStyle }
    }

    // MARK: - Termine

    @discardableResult
    public func createEvent(title: String, start: Date, end: Date, isAllDay: Bool,
                            in calendar: EventCalendar, participants: Set<Member> = [],
                            recurrenceRule: String? = nil, createdBy: String?) -> Event {
        let event = insert(Event.self, near: calendar)
        event.createdBy = createdBy
        apply(EventDraft(title: title, start: start, end: end, isAllDay: isAllDay, calendar: calendar,
                         participants: participants, recurrenceRule: recurrenceRule), to: event)
        event.defaultAlertOffset = isAllDay ? AlertDefaults.allDayEventOffset : AlertDefaults.timedEventOffset
        return event
    }

    /// Alle Vorkommen (Serien expandiert, Ausnahmen angewendet), die das Intervall berühren.
    public func occurrences(overlapping interval: DateInterval) -> [Occurrence] {
        let request = makeRequest(Event.self)
        request.predicate = Self.overlapPredicate(interval)
        return ((try? context.fetch(request)) ?? [])
            .flatMap { $0.occurrences(overlapping: interval) }
            .sorted { $0.start < $1.start }
    }

    /// Normale Termine, die das Intervall berühren, und alle Serien, die vor seinem Ende beginnen.
    public static func overlapPredicate(_ interval: DateInterval) -> NSPredicate {
        NSPredicate(format: "(start < %@ AND (end > %@ OR start >= %@)) OR (recurrenceRule != nil AND start < %@)",
                    interval.end as NSDate, interval.start as NSDate, interval.start as NSDate,
                    interval.end as NSDate)
    }

    public func delete(_ object: NSManagedObject) {
        context.delete(object)
    }

    // MARK: - Hilfen

    /// Neues Objekt im angegebenen Store, mit eigener UUID und Anlagezeit.
    public func insert<T: NSManagedObject>(_ type: T.Type, into store: NSPersistentStore) -> T {
        let object = T(context: context)
        context.assign(object, to: store)
        // Permanente ID, damit `objectID.persistentStore` schon vor dem Speichern stimmt.
        try? context.obtainPermanentIDs(for: [object])
        object.setValue(UUID(), forKey: "id")
        if object.entity.attributesByName["createdAt"] != nil {
            object.setValue(Date.now, forKey: "createdAt")
        }
        return object
    }

    /// Neues Objekt im selben Store wie `anchor`.
    public func insert<T: NSManagedObject>(_ type: T.Type, near anchor: NSManagedObject) -> T {
        insert(type, into: persistence.store(of: anchor))
    }

    private func makeRequest<T: NSManagedObject>(_ type: T.Type) -> NSFetchRequest<T> {
        NSFetchRequest<T>(entityName: String(describing: type))
    }

    private func fetch<T: NSManagedObject>(_ type: T.Type, sortedBy sort: [NSSortDescriptor]) -> [T] {
        let request = makeRequest(type)
        request.sortDescriptors = sort
        return (try? context.fetch(request)) ?? []
    }
}

nonisolated public extension Member {
    var kind: MemberKind { MemberKind(rawValue: kindRaw ?? "") ?? .adult }
    var hasAccount: Bool { cloudKitUserID != nil }
}

nonisolated public extension EventCalendar {
    var kind: CalendarKind { CalendarKind(rawValue: kindRaw ?? "") ?? .personal }
}

nonisolated public extension CalendarAppearance {
    var eventStyle: EventStyle {
        get { eventStyleRaw.flatMap(EventStyle.init(rawValue:)) ?? .outlined }
        set { eventStyleRaw = newValue.rawValue }
    }
}
