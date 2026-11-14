import SwiftUI
import YafoKit

/// Was die Ansichten zum Darstellen brauchen: Farben, Termin-Darstellung und Sichtbarkeit pro Kalender
/// (aus `CalendarAppearance`, nur für einen selbst) und der Personenfilter.
struct CalendarStyle {
    var colors: [UUID: Color] = [:]
    var eventStyles: [UUID: EventStyle] = [:]
    var hiddenCalendars: Set<UUID> = []
    var person: Member?
    /// Feiertagsregionen der sichtbaren Kalender; jede Quelle zählt einmal.
    var holidayRegions: Set<HolidayRegion> = []
    /// Eigene ICS-Abos sichtbarer Kalender (passend zum Personenfilter), mit der Farbe des
    /// ersten Kalenders, der sie abonniert.
    var icsColors: [String: Color] = [:]
    var icsStyles: [String: EventStyle] = [:]
    /// Schulferien-Quellen sichtbarer Kalender.
    var schoolHolidayKeys: Set<String> = []

    var subscriptionKeys: Set<String> { Set(icsColors.keys).union(schoolHolidayKeys) }

    init(calendars: some Sequence<EventCalendar>, appearances: some Sequence<CalendarAppearance>,
         person: Member?) {
        let byID = Dictionary(appearances.compactMap { a in a.calendarID.map { ($0, a) } },
                              uniquingKeysWith: { first, _ in first })
        for calendar in calendars {
            guard let id = calendar.id else { continue }
            let appearance = byID[id.uuidString]
            colors[id] = Color(hex: appearance?.color ?? calendar.defaultColor ?? CalendarColors.sharedDefault)
            eventStyles[id] = appearance?.eventStyle ?? .outlined
            if appearance?.isVisible == false {
                hiddenCalendars.insert(id)
                continue
            }
            let appliesToPerson = person == nil || (calendar.family != nil && calendar.family == person?.family)
            for subscription in calendar.subscriptions ?? [] {
                guard let key = subscription.sourceKey else { continue }
                switch subscription.kind {
                case .publicHolidays:
                    subscription.region.flatMap(HolidayRegion.init(rawValue:)).map { _ = holidayRegions.insert($0) }
                case .schoolHolidays:
                    schoolHolidayKeys.insert(key)
                case .ics where appliesToPerson && icsColors[key] == nil:
                    icsColors[key] = colors[id]
                    icsStyles[key] = eventStyles[id]
                default:
                    break
                }
            }
        }
        self.person = person
    }

    /// Eigene Termine, Abo-Termine und eingeblendete Gerätekalender in einer Liste.
    /// Gerätekalender gehören nur zu einem selbst und fallen beim Personenfilter weg.
    func entries(occurrences: [Occurrence], subscribed: some Sequence<SubscribedEvent>,
                 external: [ExternalCalendars.Item]) -> [CalendarEntry] {
        var result = occurrences.map { occurrence in
            CalendarEntry(id: "\(occurrence.event.objectID.uriRepresentation())#\(occurrence.originalStart.timeIntervalSince1970)",
                          title: occurrence.displayTitle, start: occurrence.start, end: occurrence.end,
                          isAllDay: occurrence.isAllDay, location: occurrence.location, color: color(for: occurrence.event),
                          source: .event(occurrence), eventStyle: eventStyle(for: occurrence.event))
        }
        for event in subscribed {
            guard let key = event.sourceKey, let color = icsColors[key], let start = event.start, let end = event.end
            else { continue }
            result.append(CalendarEntry(id: "\(key)#\(event.uid ?? "")", title: event.title ?? "", start: start, end: end,
                                        isAllDay: event.isAllDay, location: event.location, color: color,
                                        source: .subscription, eventStyle: icsStyles[key] ?? .outlined))
        }
        if person == nil {
            result += external.map { item in
                CalendarEntry(id: "device#\(item.id)", title: item.title, start: item.start, end: item.end,
                              isAllDay: item.isAllDay, location: item.location ?? item.calendarTitle,
                              color: Color(hex: CalendarColors.external), source: .device)
            }
        }
        return result
    }

    /// Schulferien je Tag (Namen), aus dem lokalen Cache.
    func schoolHolidays(in subscribed: some Sequence<SubscribedEvent>) -> [Date: [String]] {
        var result: [Date: [String]] = [:]
        for event in subscribed {
            guard let key = event.sourceKey, schoolHolidayKeys.contains(key), let start = event.start,
                  let end = event.end, let title = event.title else { continue }
            for day in Calendar.current.days(from: start, to: end) where !(result[day] ?? []).contains(title) {
                result[day, default: []].append(title)
            }
        }
        return result
    }

    func holidays(in interval: DateInterval) -> [Date: [Holiday]] {
        holidayRegions.isEmpty ? [:] : Holidays.holidays(in: holidayRegions, overlapping: interval)
    }

    func color(for event: Event) -> Color {
        event.calendar?.id.flatMap { colors[$0] } ?? .gray
    }

    func eventStyle(for event: Event) -> EventStyle {
        event.calendar?.id.flatMap { eventStyles[$0] } ?? .outlined
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

/// Ein Eintrag im Raster und in der Tagesliste: eigener Termin, Abo-Termin oder Gerätekalender.
struct CalendarEntry: Identifiable {
    enum Source {
        case event(Occurrence)
        case subscription
        case device
    }

    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let color: Color
    let source: Source
    /// Gerätekalender bleiben immer umrandet.
    var eventStyle: EventStyle = .outlined

    var occurrence: Occurrence? {
        if case .event(let occurrence) = source { return occurrence }
        return nil
    }

    var isDevice: Bool {
        if case .device = source { return true }
        return false
    }

    /// Ganztägige zuerst, dann nach Beginn.
    static func listOrder(_ a: CalendarEntry, _ b: CalendarEntry) -> Bool {
        (a.isAllDay ? 0 : 1, a.start, a.title) < (b.isAllDay ? 0 : 1, b.start, b.title)
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
