import EventKit
import Foundation
import YafoKit

/// Kopiert yafo-Termine in einen Kalender des Geräts (iCloud, Google, Exchange …), z. B. damit
/// sie im Arbeitskalender auftauchen. Jede Kopie trägt `yafo://event/<id>` als URL; ein
/// erneuter Export ersetzt die alte Kopie statt sie zu verdoppeln.
@MainActor
final class DeviceCalendarExport {
    struct Result {
        var copied = 0
        var replaced = 0
    }

    let store = EKEventStore()

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    var writableCalendars: [EKCalendar] {
        store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    func calendar(withIdentifier id: String) -> EKCalendar? {
        store.calendar(withIdentifier: id)
    }

    static func url(of event: Event) -> URL? {
        event.id.map { URL(string: "yafo://event/\($0.uuidString)")! }
    }

    func export(_ calendars: [EventCalendar], to target: EKCalendar, repository: Repository,
                now: Date = .now) throws -> Result {
        var result = Result()
        let window = Self.window(around: now)
        var existing = Dictionary(grouping: copies(in: target, window: window)) { $0.url }

        let events = calendars.flatMap { $0.events ?? [] }
        for event in events {
            guard let url = Self.url(of: event), let start = event.start, let end = event.end else { continue }
            // Ältere einmalige Termine würden außerhalb des Suchzeitraums bei jedem Export verdoppelt.
            if event.recurrenceRule == nil, end < window.start { continue }
            if let old = existing.removeValue(forKey: url), let first = old.first {
                try store.remove(first, span: .futureEvents, commit: false)
                result.replaced += 1
            } else {
                result.copied += 1
            }

            let copy = EKEvent(eventStore: store)
            copy.calendar = target
            copy.url = url
            fill(copy, title: event.title, start: start, end: end, isAllDay: event.isAllDay,
                 location: event.location, notes: repository.exportDescription(of: event))
            if let zone = event.timeZone.flatMap(TimeZone.init(identifier:)), !event.isAllDay { copy.timeZone = zone }
            if let rule = event.recurrenceRule.flatMap(RecurrenceRule.init(rrule:)) {
                copy.recurrenceRules = [Self.ekRule(rule)]
            }
            try store.save(copy, span: .futureEvents, commit: false)

            guard copy.hasRecurrenceRules, let exceptions = event.exceptions, !exceptions.isEmpty else { continue }
            try store.commit()
            try applyExceptions(exceptions, of: event, to: copy, window: window, repository: repository)
        }
        try store.commit()
        return result
    }

    // MARK: Serien

    /// Abgesagte Vorkommen werden gelöscht, geänderte einzeln angepasst.
    private func applyExceptions(_ exceptions: Set<EventException>, of event: Event, to copy: EKEvent,
                                 window: DateInterval, repository: Repository) throws {
        let occurrences = store.events(matching: store.predicateForEvents(withStart: window.start, end: window.end,
                                                                           calendars: [copy.calendar]))
            .filter { $0.calendarItemIdentifier == copy.calendarItemIdentifier }
        let byOriginal = Dictionary(occurrences.map { ($0.occurrenceDate ?? $0.startDate!, $0) }) { first, _ in first }
        for exception in exceptions {
            guard let original = exception.originalDate, let occurrence = byOriginal[original] else { continue }
            if exception.isCancelled {
                try store.remove(occurrence, span: .thisEvent, commit: false)
                continue
            }
            let duration = (event.end ?? original).timeIntervalSince(event.start ?? original)
            let start = exception.start ?? original
            fill(occurrence, title: exception.title ?? event.title, start: start,
                 end: exception.end ?? start.addingTimeInterval(duration), isAllDay: event.isAllDay,
                 location: exception.location ?? event.location,
                 notes: exception.notes ?? repository.exportDescription(of: event))
            try store.save(occurrence, span: .thisEvent, commit: false)
        }
    }

    private func fill(_ copy: EKEvent, title: String?, start: Date, end: Date, isAllDay: Bool,
                      location: String?, notes: String?) {
        copy.title = title ?? ""
        copy.isAllDay = isAllDay
        copy.startDate = start
        // EventKit zählt bei Ganztagsterminen den letzten Tag mit; yafo speichert das Ende exklusiv.
        copy.endDate = isAllDay ? max(start, end.addingTimeInterval(-1)) : end
        copy.location = location
        copy.notes = notes
    }

    static func ekRule(_ rule: RecurrenceRule) -> EKRecurrenceRule {
        let frequency: EKRecurrenceFrequency = switch rule.frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
        let days = rule.byDay.compactMap { day -> EKRecurrenceDayOfWeek? in
            guard let weekday = EKWeekday(rawValue: day.weekday) else { return nil }
            return day.ordinal.map { EKRecurrenceDayOfWeek(weekday, weekNumber: $0) } ?? EKRecurrenceDayOfWeek(weekday)
        }
        let end: EKRecurrenceEnd? = if let count = rule.count {
            EKRecurrenceEnd(occurrenceCount: count)
        } else if let until = rule.until {
            EKRecurrenceEnd(end: until)
        } else {
            nil
        }
        return EKRecurrenceRule(recurrenceWith: frequency, interval: max(rule.interval, 1),
                                daysOfTheWeek: days.isEmpty ? nil : days,
                                daysOfTheMonth: rule.byMonthDay.isEmpty ? nil : rule.byMonthDay.map { $0 as NSNumber },
                                monthsOfTheYear: rule.byMonth.isEmpty ? nil : rule.byMonth.map { $0 as NSNumber },
                                weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: end)
    }

    // MARK: Vorhandene Kopien

    /// Früher exportierte Termine im Zielkalender, erkannt an ihrer yafo-URL.
    private func copies(in calendar: EKCalendar, window: DateInterval) -> [EKEvent] {
        var found: [EKEvent] = []
        var chunkStart = window.start
        // EventKit sucht höchstens vier Jahre am Stück.
        while chunkStart < window.end {
            let chunkEnd = min(Calendar.current.date(byAdding: .year, value: 1, to: chunkStart)!, window.end)
            found += store.events(matching: store.predicateForEvents(withStart: chunkStart, end: chunkEnd,
                                                                     calendars: [calendar]))
            chunkStart = chunkEnd
        }
        return found.filter { $0.url?.scheme == "yafo" }
    }

    /// Wie beim Import: ein Jahr zurück bis zwei Jahre voraus.
    static func window(around now: Date) -> DateInterval {
        let calendar = Calendar.current
        return DateInterval(start: calendar.date(byAdding: .year, value: -1, to: now)!,
                            end: calendar.date(byAdding: .year, value: 2, to: now)!)
    }
}
