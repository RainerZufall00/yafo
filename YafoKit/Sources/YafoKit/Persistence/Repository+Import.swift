import CoreData
import Foundation

/// Vorschau vor dem Import: was übernommen wird und was verloren geht.
nonisolated public struct ICSImportPreview: Equatable, Sendable {
    public var eventCount: Int
    public var seriesCount: Int
    public var withAttendees: Int
    public var withAttachments: Int
    public var withConferenceLinks: Int

    public init(_ events: [ICSEvent]) {
        let masters = events.filter { $0.recurrenceID == nil && !$0.isCancelled }
        eventCount = masters.count
        seriesCount = masters.filter { $0.recurrenceRule != nil }.count
        withAttendees = events.filter(\.hasAttendees).count
        withAttachments = events.filter(\.hasAttachments).count
        withConferenceLinks = events.filter(\.hasConferenceLink).count
    }

    public var losesSomething: Bool { withAttendees + withAttachments + withConferenceLinks > 0 }
}

nonisolated public struct ICSImportResult: Equatable, Sendable {
    public var created = 0
    /// Schon vorhanden (gleiche UID im Zielkalender).
    public var skipped = 0
    public var exceptions = 0
}

extension Repository {
    /// Übernimmt Termine aus einer ICS-Datei oder -Adresse in `calendar`. Serien kommen samt
    /// Ausnahmen mit; was schon mit derselben UID im Kalender liegt, wird übersprungen.
    @discardableResult
    public func importICS(_ events: [ICSEvent], into calendar: EventCalendar, createdBy: String?) -> ICSImportResult {
        var result = ICSImportResult()
        var existing = Dictionary(
            (calendar.events ?? []).compactMap { event in event.importUID.map { ($0, event) } },
            uniquingKeysWith: { first, _ in first })
        var imported: [String: Event] = [:]

        for ics in events where ics.recurrenceID == nil && !ics.isCancelled {
            if existing[ics.uid] != nil {
                result.skipped += 1
                continue
            }
            let event = createEvent(title: ics.summary.isEmpty ? String(localized: "Untitled") : ics.summary,
                                    start: ics.start, end: ics.end, isAllDay: ics.isAllDay, in: calendar,
                                    recurrenceRule: ics.recurrenceRule.flatMap(Self.supportedRule), createdBy: createdBy)
            event.location = ics.location
            event.notes = ics.notes
            event.importUID = ics.uid
            if !ics.isAllDay { event.timeZone = ics.timeZone ?? TimeZone.current.identifier }
            existing[ics.uid] = event
            imported[ics.uid] = event
            result.created += 1

            if event.isRecurring {
                for date in ics.excludedDates {
                    delete(event, occurrence: date, scope: .thisOccurrence)
                    result.exceptions += 1
                }
            }
        }

        // Geänderte oder abgesagte Vorkommen nur an neu importierten Serien anbringen.
        for ics in events {
            guard let originalStart = ics.recurrenceID, let series = imported[ics.uid], series.isRecurring,
                  let seriesCalendar = series.calendar else { continue }
            if ics.isCancelled {
                delete(series, occurrence: originalStart, scope: .thisOccurrence)
            } else {
                update(series, occurrence: originalStart,
                       with: EventDraft(title: ics.summary, start: ics.start, end: ics.end, isAllDay: series.isAllDay,
                                        location: ics.location, notes: ics.notes, calendar: seriesCalendar,
                                        participants: series.participants ?? [], recurrenceRule: series.recurrenceRule),
                       scope: .thisOccurrence)
            }
            result.exceptions += 1
        }
        return result
    }

    /// Nur Regeln, die yafo auch berechnen kann; sonst wird der Termin einmalig übernommen.
    static func supportedRule(_ rule: String) -> String? {
        RecurrenceRule(rrule: rule) != nil ? rule : nil
    }
}
