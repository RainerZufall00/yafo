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
