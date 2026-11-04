import CoreData
import Foundation

extension Repository {
    /// Neuer Geburtstag am Tag `day` (Monat und Tag zählen), optional mit Geburtsjahr.
    @discardableResult
    public func createBirthday(name: String, day: Date, birthYear: Int?, in calendar: EventCalendar,
                               notes: String? = nil, createdBy: String?) -> Event {
        let event = insert(Event.self, near: calendar)
        event.createdBy = createdBy
        applyBirthday(name: name, day: day, birthYear: birthYear, calendar: calendar, notes: notes, to: event)
        return event
    }

    /// Ändert einen Geburtstag; betrifft immer die ganze Serie.
    @discardableResult
    public func updateBirthday(_ event: Event, name: String, day: Date, birthYear: Int?,
                               calendar: EventCalendar, notes: String?) -> Event {
        let target: Event
        if persistence.store(of: calendar) != persistence.store(of: event) {
            target = createBirthday(name: name, day: day, birthYear: birthYear, in: calendar,
                                    notes: notes, createdBy: event.createdBy)
            delete(event)
        } else {
            target = event
            applyBirthday(name: name, day: day, birthYear: birthYear, calendar: calendar, notes: notes, to: event)
        }
        return target
    }

    private func applyBirthday(name: String, day: Date, birthYear: Int?, calendar: EventCalendar,
                               notes: String?, to event: Event) {
        let cal = Calendar.current
        let start = Birthday.seriesStart(day: day, birthYear: birthYear, calendar: cal)
        apply(EventDraft(title: name, start: start, end: cal.date(byAdding: .day, value: 1, to: start)!,
                         isAllDay: true, notes: notes, calendar: calendar,
                         recurrenceRule: Birthday.rule(for: day, calendar: cal)), to: event)
        event.kind = .birthday
        event.birthYear = Int64(birthYear ?? 0)
        event.defaultAlertOffset = AlertDefaults.birthdayOffset
        // Alte Ausnahmen passen nach einer Datumsänderung nicht mehr.
        for exception in event.exceptions ?? [] { delete(exception) }
    }
}

/// Geburtstag aus einer anderen Quelle (z. B. Kontakte), bevor er übernommen wird.
nonisolated public struct BirthdayCandidate: Identifiable, Hashable, Sendable {
    /// Stabile ID in der Quelle, z. B. die Kontakt-ID.
    public var id: String
    public var name: String
    public var month: Int
    public var day: Int
    /// `nil`, wenn das Geburtsjahr in der Quelle fehlt.
    public var year: Int?

    public init(id: String, name: String, month: Int, day: Int, year: Int?) {
        self.id = id
        self.name = name
        self.month = month
        self.day = day
        self.year = year
    }

    /// Tag für `createBirthday`: mit Jahr das Geburtsdatum, sonst dieses Jahr
    /// (am 29. Februar das letzte Schaltjahr, damit der Tag nicht verloren geht).
    public func day(calendar: Calendar = .current, now: Date = .now) -> Date {
        var year = year ?? calendar.component(.year, from: now)
        if self.year == nil, month == 2, day == 29 {
            while calendar.range(of: .day, in: .month,
                                 for: calendar.date(from: DateComponents(year: year, month: 2))!)?.count != 29 {
                year -= 1
            }
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

extension Repository {
    static let contactUIDPrefix = "contact:"

    /// Schon vorhandene Geburtstage, die wahrscheinlich dieselbe Person sind: gleicher Tag und Monat,
    /// und wenn beide das Geburtsjahr kennen, auch dasselbe Jahr. Namen zählen nicht, weil dieselbe
    /// Person in Kontakten und Kalender oft anders heißt („Mama“ und „Gisela Müller“).
    /// Früher aus genau diesem Kontakt übernommene Geburtstage stehen vorne.
    public func matchingBirthdays(for candidate: BirthdayCandidate, calendar cal: Calendar = .current) -> [Event] {
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.predicate = NSPredicate(format: "kindRaw == %@", EventKind.birthday.rawValue)
        let birthdays = (try? context.fetch(request)) ?? []
        let uid = Self.contactUIDPrefix + candidate.id
        return birthdays.filter { event in
            if event.importUID == uid { return true }
            guard let start = event.start else { return false }
            let parts = cal.dateComponents([.month, .day], from: start)
            let sameDay = parts.month == candidate.month && parts.day == candidate.day
                // Ohne Jahr am 29. Februar angelegt, aber in einem Nicht-Schaltjahr auf den 28. gerutscht.
                || (candidate.month == 2 && candidate.day == 29 && parts.month == 2 && parts.day == 28
                    && event.recurrenceRule?.contains("BYMONTHDAY=-1") == true)
            guard sameDay else { return false }
            guard let year = candidate.year, event.birthYear > 0 else { return true }
            return Int(event.birthYear) == year
        }
        .sorted { ($0.importUID == uid ? 0 : 1) < ($1.importUID == uid ? 0 : 1) }
    }

    /// Übernimmt einen Geburtstag in `calendar`. Wurde derselbe Kontakt dort schon einmal übernommen,
    /// wird dieser Eintrag aktualisiert statt doppelt angelegt.
    @discardableResult
    public func importBirthday(_ candidate: BirthdayCandidate, into calendar: EventCalendar,
                               createdBy: String?) -> Event {
        let uid = Self.contactUIDPrefix + candidate.id
        let day = candidate.day()
        if let existing = calendar.events?.first(where: { $0.importUID == uid }) {
            return updateBirthday(existing, name: candidate.name, day: day, birthYear: candidate.year,
                                  calendar: calendar, notes: existing.notes)
        }
        let event = createBirthday(name: candidate.name, day: day, birthYear: candidate.year, in: calendar,
                                   createdBy: createdBy)
        event.importUID = uid
        return event
    }
}
