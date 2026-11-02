import SwiftUI
import YafoKit

/// Was die Ansichten zum Darstellen brauchen: Farben und Sichtbarkeit pro Kalender
/// (aus `CalendarAppearance`, nur für einen selbst) und der Personenfilter.
struct CalendarStyle {
    var colors: [UUID: Color] = [:]
    var hiddenCalendars: Set<UUID> = []
    var person: Member?

    init(calendars: some Sequence<EventCalendar>, appearances: some Sequence<CalendarAppearance>,
         person: Member?) {
        let byID = Dictionary(appearances.compactMap { a in a.calendarID.map { ($0, a) } },
                              uniquingKeysWith: { first, _ in first })
        for calendar in calendars {
            guard let id = calendar.id else { continue }
            let appearance = byID[id.uuidString]
            colors[id] = Color(hex: appearance?.color ?? calendar.defaultColor ?? CalendarColors.sharedDefault)
            if appearance?.isVisible == false {
                hiddenCalendars.insert(id)
            }
        }
        self.person = person
    }

    func color(for event: Event) -> Color {
        event.calendar?.id.flatMap { colors[$0] } ?? .gray
    }

    /// Sichtbarer Kalender und, falls gefiltert, die Person ist dabei. Ein Termin ohne
    /// Teilnehmer gilt für die ganze Familie seines Kalenders.
    func includes(_ event: Event) -> Bool {
        guard let calendar = event.calendar, let id = calendar.id, !hiddenCalendars.contains(id) else {
            return false
        }
        guard let person else { return true }
        let participants = event.participants ?? []
        if participants.isEmpty {
            return calendar.family != nil && calendar.family == person.family
        }
        return participants.contains(person)
    }
}

extension Event {
    var sortedParticipants: [Member] {
        (participants ?? []).sorted {
            ($0.kind == .adult ? 0 : 1, $0.displayName ?? "") < ($1.kind == .adult ? 0 : 1, $1.displayName ?? "")
        }
    }
}

extension Occurrence {
    /// Titel für Chips und Listen; Geburtstage mit Torte und Alter.
    var displayTitle: String {
        guard event.isBirthday else { return title }
        if let age { return "🎂 \(title) (\(age))" }
        return "🎂 \(title)"
    }

    var timeText: String {
        if event.isBirthday {
            if let age { return String(localized: "Turns \(age)") }
            return String(localized: "Birthday")
        }
        if isAllDay {
            return String(localized: "All day")
        }
        return "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
    }
}
