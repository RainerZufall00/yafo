import CoreData
import Foundation

/// Ein einzelnes Vorkommen eines Termins: bei Serien ein Tag der Serie, mit den Änderungen
/// aus einer `EventException`; bei normalen Terminen der Termin selbst.
nonisolated public struct Occurrence: Identifiable {
    public struct ID: Hashable {
        public let event: NSManagedObjectID
        /// Ursprünglicher Beginn laut Regel; bleibt gleich, auch wenn das Vorkommen verschoben wird.
        public let originalStart: Date
    }

    public let event: Event
    public let originalStart: Date
    public let start: Date
    public let end: Date
    public let title: String
    public let location: String?
    public let notes: String?
    public let isAllDay: Bool
    public let isRecurring: Bool

    public var id: ID { ID(event: event.objectID, originalStart: originalStart) }
}

nonisolated public extension Event {
    var rule: RecurrenceRule? { recurrenceRule.flatMap(RecurrenceRule.init(rrule:)) }

    var isRecurring: Bool { rule != nil }

    /// Rechnet in der Zeitzone des Termins, damit 9 Uhr auch nach der Zeitumstellung 9 Uhr bleibt.
    /// Ganztägige Termine haben keine Zeitzone und gelten in der des Geräts.
    var seriesCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }

    var duration: TimeInterval {
        guard let start, let end else { return 0 }
        return max(end.timeIntervalSince(start), 0)
    }

    func exception(for originalStart: Date) -> EventException? {
        exceptions?.first { $0.originalDate == originalStart }
    }

    /// Vorkommen, deren Zeitraum das Intervall berührt (Ende exklusiv; Termine ohne Dauer
    /// zählen, wenn sie im Intervall beginnen). Abgesagte Vorkommen fehlen.
    func occurrences(overlapping interval: DateInterval) -> [Occurrence] {
        guard let start else { return [] }
        guard let rule else {
            let occurrence = occurrence(originalStart: start)
            return occurrence.overlaps(interval) ? [occurrence] : []
        }
        let exceptionsByDate = Dictionary((exceptions ?? []).compactMap { e in e.originalDate.map { ($0, e) } },
                                          uniquingKeysWith: { first, _ in first })
        var result: [Occurrence] = []
        let starts = rule.startDates(seriesStart: start, from: interval.start.addingTimeInterval(-duration),
                                     to: interval.end, calendar: seriesCalendar)
        for originalStart in starts where exceptionsByDate[originalStart] == nil {
            let occurrence = occurrence(originalStart: originalStart)
            if occurrence.overlaps(interval) { result.append(occurrence) }
        }
        // Verschobene Vorkommen können außerhalb ihres ursprünglichen Tages liegen.
        for (originalStart, exception) in exceptionsByDate where !exception.isCancelled {
            let occurrence = occurrence(originalStart: originalStart)
            if occurrence.overlaps(interval) { result.append(occurrence) }
        }
        return result.sorted { $0.start < $1.start }
    }

    /// Das Vorkommen zum ursprünglichen Beginn, mit den Änderungen einer Ausnahme.
    func occurrence(originalStart: Date) -> Occurrence {
        let exception = isRecurring ? exception(for: originalStart) : nil
        let start = exception?.start ?? originalStart
        let end = exception?.end ?? originalStart.addingTimeInterval(duration)
        return Occurrence(event: self, originalStart: originalStart, start: start, end: max(end, start),
                          title: exception?.title ?? title ?? "", location: exception?.location ?? location,
                          notes: exception?.notes ?? notes, isAllDay: isAllDay, isRecurring: isRecurring)
    }
}

nonisolated extension Occurrence {
    func overlaps(_ interval: DateInterval) -> Bool {
        if start == end { return start >= interval.start && start < interval.end }
        return start < interval.end && end > interval.start
    }
}
