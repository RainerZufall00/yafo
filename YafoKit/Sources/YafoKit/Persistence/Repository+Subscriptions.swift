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
