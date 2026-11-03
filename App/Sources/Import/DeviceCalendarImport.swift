import EventKit
import Foundation
import YafoKit

/// Liest Termine aus den Kalendern des Geräts (iCloud, Google, Exchange, CalDAV) und rechnet
/// sie in `ICSEvent` um, damit der Import denselben Weg nimmt wie ICS-Dateien.
@MainActor
final class DeviceCalendarImport {
    let store = EKEventStore()

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    var calendars: [EKCalendar] {
        store.calendars(for: .event).sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    /// Ein Jahr zurück bis zwei Jahre voraus. EventKit liefert Serien als einzelne Vorkommen;
    /// sie werden wieder zu einer Serie mit Regel, Ausnahmen und geänderten Vorkommen.
    func events(in calendars: [EKCalendar], now: Date = .now) -> [ICSEvent] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .year, value: -1, to: now)!
        let end = calendar.date(byAdding: .year, value: 2, to: now)!
        var occurrences: [EKEvent] = []
        // EventKit sucht höchstens vier Jahre am Stück; in Jahresschritten bleibt es schnell.
        var chunkStart = start
        while chunkStart < end {
            let chunkEnd = min(calendar.date(byAdding: .year, value: 1, to: chunkStart)!, end)
            let predicate = store.predicateForEvents(withStart: chunkStart, end: chunkEnd, calendars: calendars)
            occurrences += store.events(matching: predicate)
            chunkStart = chunkEnd
        }

        var seen = Set<String>()
        var result: [ICSEvent] = []
        let grouped = Dictionary(grouping: occurrences) { $0.calendarItemExternalIdentifier ?? $0.eventIdentifier ?? UUID().uuidString }
        for (uid, items) in grouped {
            let sorted = items.sorted { $0.startDate < $1.startDate }
            guard let first = sorted.first, seen.insert(uid).inserted else { continue }
            guard let rule = first.recurrenceRules?.first.flatMap(Self.rrule) else {
                result += sorted.map { Self.convert($0, uid: "\(uid)-\(Int($0.startDate.timeIntervalSince1970))") }
                continue
            }
            // Serie: Beginn ist das erste Vorkommen im Zeitraum (ursprüngliches Datum bei geänderten).
            let regular = sorted.filter { !$0.isDetached }
            guard let anchor = regular.first ?? sorted.first else { continue }
            var master = Self.convert(anchor, uid: uid)
            master.recurrenceRule = rule
            let seriesStart = anchor.occurrenceDate ?? anchor.startDate!
            let duration = anchor.endDate.timeIntervalSince(anchor.startDate)
            master.start = seriesStart
            master.end = seriesStart.addingTimeInterval(duration)

            // Fehlende Vorkommen werden zu Ausnahmen (EXDATE), geänderte zu Overrides.
            let present = Set(sorted.compactMap { $0.occurrenceDate ?? $0.startDate })
            if let parsed = RecurrenceRule(rrule: rule) {
                let expected = parsed.startDates(seriesStart: seriesStart, from: seriesStart, to: end, calendar: calendar)
                master.excludedDates = expected.filter { !present.contains($0) }
            }
            result.append(master)
            for detached in sorted where detached.isDetached {
                var override = Self.convert(detached, uid: uid)
                override.recurrenceID = detached.occurrenceDate
                result.append(override)
            }
        }
        return result
    }

    private static func convert(_ event: EKEvent, uid: String) -> ICSEvent {
        var end: Date = event.endDate
        if event.isAllDay {
            // EventKit endet ganztägig um 23:59:59 des letzten Tages; yafo am Folgetag um 0 Uhr.
            end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: event.endDate))!
        }
        return ICSEvent(uid: uid, summary: event.title ?? "", location: event.location, notes: event.notes,
                        start: event.isAllDay ? Calendar.current.startOfDay(for: event.startDate) : event.startDate,
                        end: end, isAllDay: event.isAllDay, timeZone: event.timeZone?.identifier,
                        recurrenceRule: nil, excludedDates: [], recurrenceID: nil,
                        isCancelled: event.status == .canceled,
                        hasAttendees: event.hasAttendees, hasAttachments: false,
                        hasConferenceLink: event.url != nil)
    }

    /// EKRecurrenceRule als RRULE-Text.
    static func rrule(_ rule: EKRecurrenceRule) -> String? {
        let frequency: String
        switch rule.frequency {
        case .daily: frequency = "DAILY"
        case .weekly: frequency = "WEEKLY"
        case .monthly: frequency = "MONTHLY"
        case .yearly: frequency = "YEARLY"
        @unknown default: return nil
        }
        var parts = ["FREQ=\(frequency)"]
        if rule.interval > 1 { parts.append("INTERVAL=\(rule.interval)") }
        let codes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
        if let days = rule.daysOfTheWeek, !days.isEmpty {
            parts.append("BYDAY=" + days.map { day in
                (day.weekNumber != 0 ? "\(day.weekNumber)" : "") + codes[day.dayOfTheWeek.rawValue - 1]
            }.joined(separator: ","))
        }
        if let monthDays = rule.daysOfTheMonth, !monthDays.isEmpty {
            parts.append("BYMONTHDAY=" + monthDays.map { "\($0)" }.joined(separator: ","))
        }
        if let months = rule.monthsOfTheYear, !months.isEmpty {
            parts.append("BYMONTH=" + months.map { "\($0)" }.joined(separator: ","))
        }
        if let end = rule.recurrenceEnd {
            if end.occurrenceCount > 0 {
                parts.append("COUNT=\(end.occurrenceCount)")
            } else if let date = end.endDate {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(identifier: "UTC")
                formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
                parts.append("UNTIL=\(formatter.string(from: date))")
            }
        }
        return parts.joined(separator: ";")
    }
}
