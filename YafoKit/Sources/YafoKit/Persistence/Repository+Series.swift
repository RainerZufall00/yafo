import CoreData
import Foundation

/// Werte eines Termins beim Anlegen oder Bearbeiten.
public struct EventDraft {
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?
    /// Koordinaten zu `location`, siehe `Event.geo`.
    public var geo: String?
    public var notes: String?
    public var calendar: EventCalendar
    public var participants: Set<Member>
    public var recurrenceRule: String?

    public init(title: String, start: Date, end: Date, isAllDay: Bool, location: String? = nil,
                notes: String? = nil, calendar: EventCalendar, participants: Set<Member> = [],
                recurrenceRule: String? = nil, geo: String? = nil) {
        self.title = title
        self.geo = geo
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.calendar = calendar
        self.participants = participants
        self.recurrenceRule = recurrenceRule
    }
}

/// Welche Vorkommen einer Serie eine Änderung betrifft.
public enum SeriesScope: Sendable {
    case thisOccurrence
    case thisAndFollowing
    case allOccurrences
}

extension Repository {
    /// Ändert einen Termin. Bei Serien bestimmt `scope`, ob nur das Vorkommen (als Ausnahme),
    /// dieses und alle folgenden (die Serie wird geteilt) oder alle geändert werden.
    /// Gibt den Termin zurück, der die Änderung jetzt trägt.
    @discardableResult
    public func update(_ event: Event, occurrence originalStart: Date? = nil, with draft: EventDraft,
                       scope: SeriesScope = .allOccurrences) -> Event {
        guard event.isRecurring, let originalStart, let seriesStart = event.start else {
            return updateWholeEvent(event, with: draft, shiftingExceptionsBy: 0)
        }
        switch scope {
        case .thisOccurrence:
            let exception = findOrCreateException(of: event, at: originalStart)
            exception.isCancelled = false
            // Nur Abweichungen speichern, damit spätere Änderungen an der Serie durchgreifen.
            exception.title = draft.title == event.title ? nil : draft.title
            exception.location = draft.location == event.location ? nil : draft.location
            exception.notes = draft.notes == event.notes ? nil : draft.notes
            let movesTime = draft.start != originalStart
                || draft.end.timeIntervalSince(draft.start) != event.duration
            exception.start = movesTime ? Self.wholeSeconds(draft.start) : nil
            exception.end = movesTime ? Self.wholeSeconds(draft.end) : nil
            event.updatedAt = .now
            return event

        case .thisAndFollowing where originalStart > seriesStart:
            return splitSeries(event, at: originalStart, with: draft)

        case .thisAndFollowing, .allOccurrences:
            // Verschiebung des Vorkommens auf die ganze Serie übertragen.
            let current = event.occurrence(originalStart: originalStart)
            let delta = draft.start.timeIntervalSince(current.start)
            var series = draft
            series.start = seriesStart.addingTimeInterval(delta)
            series.end = series.start.addingTimeInterval(draft.end.timeIntervalSince(draft.start))
            return updateWholeEvent(event, with: series, shiftingExceptionsBy: delta)
        }
    }

    /// Verschiebt ein Vorkommen auf einen anderen Tag (Drag & Drop im Kalender); Uhrzeit und Dauer bleiben.
    /// Geburtstage gelten immer als ganze Serie: Tag und Monat ändern sich, das Geburtsjahr bleibt.
    @discardableResult
    public func move(_ event: Event, occurrence originalStart: Date, toDay day: Date,
                     scope: SeriesScope = .allOccurrences, calendar cal: Calendar = .current) -> Event {
        let occurrence = event.occurrence(originalStart: originalStart)
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: occurrence.start),
                                      to: cal.startOfDay(for: day)).day ?? 0
        guard days != 0, let calendar = event.calendar else { return event }
        if event.isBirthday {
            return updateBirthday(event, name: event.title ?? "", day: day,
                                  birthYear: event.birthYear > 0 ? Int(event.birthYear) : nil,
                                  calendar: calendar, notes: event.notes)
        }
        let start = cal.date(byAdding: .day, value: days, to: occurrence.start) ?? occurrence.start
        let end = cal.date(byAdding: .day, value: days, to: occurrence.end) ?? occurrence.end
        // Nur dieses Vorkommen: seine Abweichungen behalten. Sonst gelten die Werte der Serie.
        let single = scope == .thisOccurrence && event.isRecurring
        let draft = EventDraft(title: single ? occurrence.title : event.title ?? "", start: start, end: end,
                               isAllDay: event.isAllDay,
                               location: single ? occurrence.location : event.location,
                               notes: single ? occurrence.notes : event.notes, calendar: calendar,
                               participants: event.participants ?? [], recurrenceRule: event.recurrenceRule,
                               geo: event.geo)
        return update(event, occurrence: originalStart, with: draft, scope: scope)
    }

    /// Löscht einen Termin bzw. Vorkommen einer Serie.
    public func delete(_ event: Event, occurrence originalStart: Date?, scope: SeriesScope) {
        guard event.isRecurring, let originalStart, let seriesStart = event.start, let rule = event.rule,
              scope != .allOccurrences else {
            context.delete(event)
            return
        }
        switch scope {
        case .thisOccurrence:
            findOrCreateException(of: event, at: originalStart).isCancelled = true
            event.updatedAt = .now
        case .thisAndFollowing where originalStart > seriesStart:
            end(event, rule: rule, before: originalStart)
            for exception in event.exceptions ?? [] where (exception.originalDate ?? .distantPast) >= originalStart {
                context.delete(exception)
            }
        default:
            context.delete(event)
        }
    }

    // MARK: - Intern

    func apply(_ draft: EventDraft, to event: Event) {
        event.title = draft.title
        event.start = Self.wholeSeconds(draft.start)
        event.end = Self.wholeSeconds(max(draft.end, draft.start))
        event.isAllDay = draft.isAllDay
        event.timeZone = draft.isAllDay ? nil : (event.timeZone ?? TimeZone.current.identifier)
        event.location = draft.location
        event.geo = draft.location == nil ? nil : draft.geo
        event.notes = draft.notes
        event.recurrenceRule = draft.recurrenceRule
        event.calendar = draft.calendar
        // Teilnehmer nur aus derselben Familie: keine Beziehungen zwischen Stores.
        event.participants = draft.participants.filter { $0.family != nil && $0.family == draft.calendar.family }
        event.updatedAt = .now
    }

    private func updateWholeEvent(_ event: Event, with draft: EventDraft, shiftingExceptionsBy delta: TimeInterval) -> Event {
        var target = event
        if persistence.store(of: draft.calendar) != persistence.store(of: event) {
            // Beziehungen über Stores hinweg sind nicht erlaubt: im Ziel-Store neu anlegen.
            target = createEvent(title: draft.title, start: draft.start, end: draft.end, isAllDay: draft.isAllDay,
                                 in: draft.calendar, createdBy: event.createdBy)
            target.kindRaw = event.kindRaw
            target.birthYear = event.birthYear
            target.defaultAlertOffset = event.defaultAlertOffset
            for exception in event.exceptions ?? [] {
                let copy = insert(EventException.self, near: target)
                copy.originalDate = exception.originalDate
                copy.isCancelled = exception.isCancelled
                copy.title = exception.title
                copy.start = exception.start
                copy.end = exception.end
                copy.location = exception.location
                copy.notes = exception.notes
                copy.event = target
            }
            context.delete(event)
        }
        apply(draft, to: target)
        if delta != 0 {
            for exception in target.exceptions ?? [] {
                exception.originalDate = exception.originalDate?.addingTimeInterval(delta)
            }
        }
        return target
    }

    private func splitSeries(_ event: Event, at originalStart: Date, with draft: EventDraft) -> Event {
        let originalRule = event.recurrenceRule
        let rule = event.rule!
        let current = event.occurrence(originalStart: originalStart)
        let delta = draft.start.timeIntervalSince(current.start)

        var followingRule = draft.recurrenceRule
        if draft.recurrenceRule == originalRule, let count = rule.count {
            // Bei COUNT zählen die bisherigen Vorkommen mit.
            let before = rule.startDates(seriesStart: event.start!, from: event.start!, to: originalStart,
                                         calendar: event.seriesCalendar).count
            var remaining = rule
            remaining.count = max(count - before, 1)
            followingRule = remaining.rruleString
        }
        end(event, rule: rule, before: originalStart)

        let following = createEvent(title: draft.title, start: draft.start, end: draft.end, isAllDay: draft.isAllDay,
                                    in: draft.calendar, createdBy: event.createdBy)
        var followingDraft = draft
        followingDraft.recurrenceRule = followingRule
        apply(followingDraft, to: following)

        let sameStore = persistence.store(of: following) == persistence.store(of: event)
        for exception in event.exceptions ?? [] where (exception.originalDate ?? .distantPast) >= originalStart {
            if sameStore {
                exception.event = following
                exception.originalDate = exception.originalDate?.addingTimeInterval(delta)
            } else {
                context.delete(exception)
            }
        }
        return following
    }

    /// Serie endet vor `date` (UNTIL statt COUNT).
    private func end(_ event: Event, rule: RecurrenceRule, before date: Date) {
        var ended = rule
        ended.count = nil
        ended.until = date.addingTimeInterval(-1)
        event.recurrenceRule = ended.rruleString
        event.updatedAt = .now
    }

    private func findOrCreateException(of event: Event, at originalStart: Date) -> EventException {
        if let existing = event.exception(for: originalStart) { return existing }
        let exception = insert(EventException.self, near: event)
        exception.originalDate = originalStart
        exception.event = event
        return exception
    }

    static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded(.down))
    }
}
