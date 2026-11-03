import CoreData
import Foundation

extension CalendarSubscription {
    public var kind: SubscriptionKind? { kindRaw.flatMap(SubscriptionKind.init(rawValue:)) }
}

extension Repository {
    // MARK: Feiertage

    /// Feiertagsregion, die dieser Kalender abonniert hat.
    public func holidayRegion(of calendar: EventCalendar) -> HolidayRegion? {
        (calendar.subscriptions ?? []).first { $0.kind == .publicHolidays }
            .flatMap { $0.region.flatMap(HolidayRegion.init(rawValue:)) }
    }

    /// Abo setzen oder mit `nil` beenden. Liegt im Store des Kalenders und synchronisiert so
    /// an alle Mitglieder; bei geteilten Kalendern ändert das nur der Owner (Regel in der App).
    public func setHolidayRegion(_ region: HolidayRegion?, for calendar: EventCalendar) {
        let existing = (calendar.subscriptions ?? []).filter { $0.kind == .publicHolidays }
        if let region, let current = existing.first, current.region == region.rawValue, existing.count == 1 { return }
        existing.forEach(delete)
        guard let region else { return }
        let subscription = insert(CalendarSubscription.self, near: calendar)
        subscription.kindRaw = SubscriptionKind.publicHolidays.rawValue
        subscription.region = region.rawValue
        subscription.sourceKey = region.sourceKey
        subscription.calendar = calendar
    }

    /// Regionen aller sichtbaren Kalender; jede Quelle zählt einmal, egal wie viele Kalender sie abonnieren.
    public func activeHolidayRegions() -> Set<HolidayRegion> {
        Set(calendars().filter(isVisible).compactMap(holidayRegion(of:)))
    }

    /// Andere Kalender, die dieselbe Region schon abonniert haben (für den Hinweis
    /// „Bereits über den Familienkalender abonniert“).
    public func calendarsSubscribed(to region: HolidayRegion, except calendar: EventCalendar) -> [EventCalendar] {
        calendars().filter { $0 != calendar && holidayRegion(of: $0) == region }
    }

    /// Feiertage der sichtbaren Abos im Intervall, je Tag.
    public func holidays(overlapping interval: DateInterval) -> [Date: [Holiday]] {
        Holidays.holidays(in: activeHolidayRegions(), overlapping: interval)
    }
}

/// Eine abonnierte Quelle, egal wie viele Kalender sie abonnieren.
nonisolated public struct SubscriptionSource: Hashable, Sendable {
    public let sourceKey: String
    public let kind: SubscriptionKind
    /// ICS-Adresse bzw. Region der Schulferien.
    public let url: URL?
    public let region: String?
}

extension Repository {
    // MARK: Schulferien

    public func schoolHolidayRegion(of calendar: EventCalendar) -> SchoolHolidayRegion? {
        (calendar.subscriptions ?? []).first { $0.kind == .schoolHolidays }
            .flatMap { SchoolHolidayRegion.region(code: $0.region) }
    }

    public func setSchoolHolidayRegion(_ region: SchoolHolidayRegion?, for calendar: EventCalendar) {
        let existing = (calendar.subscriptions ?? []).filter { $0.kind == .schoolHolidays }
        if let region, let current = existing.first, current.region == region.code, existing.count == 1 { return }
        existing.forEach(delete)
        guard let region else { return }
        let subscription = insert(CalendarSubscription.self, near: calendar)
        subscription.kindRaw = SubscriptionKind.schoolHolidays.rawValue
        subscription.region = region.code
        subscription.sourceKey = region.sourceKey
        subscription.calendar = calendar
    }

    // MARK: Eigene ICS-Abos

    public func icsSubscriptions(of calendar: EventCalendar) -> [CalendarSubscription] {
        (calendar.subscriptions ?? []).filter { $0.kind == .ics }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// Fügt eine ICS- oder webcal-Adresse hinzu; `nil`, wenn die Adresse ungültig ist oder
    /// der Kalender sie schon abonniert hat.
    @discardableResult
    public func addICSSubscription(address: String, name: String?, to calendar: EventCalendar) -> CalendarSubscription? {
        guard let url = SubscriptionFeed.normalizedURL(address),
              let key = SubscriptionFeed.sourceKey(forICS: address),
              !icsSubscriptions(of: calendar).contains(where: { $0.sourceKey == key }) else { return nil }
        let subscription = insert(CalendarSubscription.self, near: calendar)
        subscription.kindRaw = SubscriptionKind.ics.rawValue
        subscription.url = url.absoluteString
        subscription.sourceKey = key
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        subscription.name = trimmed.isEmpty ? url.host() : trimmed
        subscription.calendar = calendar
        return subscription
    }

    // MARK: Quellen und lokaler Cache

    /// Alle Quellen, die geladen werden müssen (Feiertage rechnet die App selbst).
    public func subscriptionSources() -> [SubscriptionSource] {
        let request = NSFetchRequest<CalendarSubscription>(entityName: "CalendarSubscription")
        let subscriptions = (try? context.fetch(request)) ?? []
        var seen = Set<String>()
        return subscriptions.compactMap { subscription in
            guard let key = subscription.sourceKey, let kind = subscription.kind, kind != .publicHolidays,
                  subscription.calendar != nil, seen.insert(key).inserted else { return nil }
            return SubscriptionSource(sourceKey: key, kind: kind,
                                      url: subscription.url.flatMap(URL.init(string:)), region: subscription.region)
        }
    }

    /// Zeitpunkt des letzten erfolgreichen Abrufs einer Quelle.
    public func lastFetch(of sourceKey: String) -> Date? {
        let request = NSFetchRequest<SubscribedEvent>(entityName: "SubscribedEvent")
        request.predicate = NSPredicate(format: "sourceKey == %@", sourceKey)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \SubscribedEvent.fetchedAt, ascending: false)]
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first?.fetchedAt
    }

    /// Baut den Cache einer Quelle neu auf. Eine leere Quelle bekommt einen Platzhalter
    /// ohne Datum, damit der Abrufzeitpunkt erhalten bleibt.
    public func replaceCache(of sourceKey: String, with entries: [SubscriptionEntry], fetchedAt: Date = .now) {
        cachedEvents(of: sourceKey).forEach(delete)
        guard let store = persistence.localStore else { return }
        for entry in entries {
            let cached = insert(SubscribedEvent.self, into: store)
            cached.sourceKey = sourceKey
            cached.uid = entry.uid
            cached.title = entry.title
            cached.start = entry.start
            cached.end = entry.end
            cached.isAllDay = entry.isAllDay
            cached.location = entry.location
            cached.fetchedAt = fetchedAt
        }
        if entries.isEmpty {
            let marker = insert(SubscribedEvent.self, into: store)
            marker.sourceKey = sourceKey
            marker.fetchedAt = fetchedAt
        }
    }

    /// Entfernt den Cache von Quellen, die kein Kalender mehr abonniert.
    public func pruneCache(keeping sourceKeys: Set<String>) {
        let request = NSFetchRequest<SubscribedEvent>(entityName: "SubscribedEvent")
        request.predicate = NSPredicate(format: "NOT (sourceKey IN %@)", sourceKeys)
        ((try? context.fetch(request)) ?? []).forEach(delete)
    }

    /// Zwischengespeicherte Termine der Quellen im Intervall.
    public func cachedEvents(of sourceKeys: Set<String>, overlapping interval: DateInterval) -> [SubscribedEvent] {
        let request = NSFetchRequest<SubscribedEvent>(entityName: "SubscribedEvent")
        request.predicate = Self.cachePredicate(sourceKeys: sourceKeys, interval: interval)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \SubscribedEvent.start, ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    public static func cachePredicate(sourceKeys: Set<String>, interval: DateInterval) -> NSPredicate {
        NSPredicate(format: "sourceKey IN %@ AND start < %@ AND end > %@",
                    sourceKeys, interval.end as NSDate, interval.start as NSDate)
    }

    private func cachedEvents(of sourceKey: String) -> [SubscribedEvent] {
        let request = NSFetchRequest<SubscribedEvent>(entityName: "SubscribedEvent")
        request.predicate = NSPredicate(format: "sourceKey == %@", sourceKey)
        return (try? context.fetch(request)) ?? []
    }
}
