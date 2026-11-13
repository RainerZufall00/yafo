import CoreData
import SwiftUI
import YafoKit

/// Was die Ansichten zum Darstellen brauchen: Farben und Sichtbarkeit pro Kalender
/// (aus `CalendarAppearance`, nur für einen selbst) und der Personenfilter.
struct CalendarStyle {
    var colors: [UUID: Color] = [:]
    var hiddenCalendars: Set<UUID> = []
    var person: Member?
    /// Feiertagsregionen der sichtbaren Kalender; jede Quelle zählt einmal.
    var holidayRegions: Set<HolidayRegion> = []
    /// Eigene ICS-Abos sichtbarer Kalender (passend zum Personenfilter), mit der Farbe des
    /// ersten Kalenders, der sie abonniert.
    var icsColors: [String: Color] = [:]
    /// Schulferien-Quellen sichtbarer Kalender.
    var schoolHolidayKeys: Set<String> = []
    /// Eigene Farbe für Geburtstage; `nil` = Farbe ihres Kalenders.
    var birthdayColor: Color?
    /// Todos mit Fälligkeit im Kalender zeigen (Einstellung, nur auf dem Gerät).
    var showsTodos = false
    /// Besondere Tage (Advent, Sankt Martin, Halloween …) der Feiertagsregionen zeigen (Einstellung, nur auf dem Gerät).
    var showsObservances = false
    /// Farbe für Todos je Familie (die ihres ersten Kalenders) und für „Nur ich“.
    private var familyColors: [NSManagedObjectID: Color] = [:]
    private var personalColor = Color(hex: CalendarColors.personalDefault)

    var subscriptionKeys: Set<String> { Set(icsColors.keys).union(schoolHolidayKeys) }

    init(calendars: some Sequence<EventCalendar>, appearances: some Sequence<CalendarAppearance>,
         person: Member?, showsTodos: Bool = false, showsObservances: Bool = false) {
        let byID = Dictionary(appearances.compactMap { a in a.calendarID.map { ($0, a) } },
                              uniquingKeysWith: { first, _ in first })
        birthdayColor = Repository.birthdayColor(appearanceColor: byID[Repository.birthdayAppearanceID]?.color)
            .map { Color(hex: $0) }
        self.showsTodos = showsTodos
        self.showsObservances = showsObservances
        for calendar in calendars {
            guard let id = calendar.id else { continue }
            let appearance = byID[id.uuidString]
            colors[id] = Color(hex: appearance?.color ?? calendar.defaultColor ?? CalendarColors.sharedDefault)
            if let family = calendar.family {
                if familyColors[family.objectID] == nil { familyColors[family.objectID] = colors[id] }
            } else if calendar.kind == .personal, let color = colors[id] {
                personalColor = color
            }
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
                default:
                    break
                }
            }
        }
        self.person = person
    }

    /// Eigene Termine, Abo-Termine und eingeblendete Gerätekalender in einer Liste.
    /// Gerätekalender gehören nur zu einem selbst und fallen beim Personenfilter weg. Mit `observancesIn` kommen
    /// die besonderen Tage dieses Zeitraums als ganztägige, gedämpfte Einträge dazu.
    func entries(occurrences: [Occurrence], subscribed: some Sequence<SubscribedEvent>,
                 external: [ExternalCalendars.Item], todos: some Sequence<TodoItem> = [TodoItem](),
                 observancesIn interval: DateInterval? = nil) -> [CalendarEntry] {
        var result = occurrences.map { occurrence in
            CalendarEntry(id: "\(occurrence.event.objectID.uriRepresentation())#\(occurrence.originalStart.timeIntervalSince1970)",
                          title: occurrence.displayTitle, start: occurrence.start, end: occurrence.end,
                          isAllDay: occurrence.isAllDay, location: occurrence.location, color: color(for: occurrence.event),
                          source: .event(occurrence))
        }
        for event in subscribed {
            guard let key = event.sourceKey, let color = icsColors[key], let start = event.start, let end = event.end
            else { continue }
            result.append(CalendarEntry(id: "\(key)#\(event.uid ?? "")", title: event.title ?? "", start: start, end: end,
                                        isAllDay: event.isAllDay, location: event.location, color: color,
                                        source: .subscription))
        }
        if person == nil {
            result += external.map { item in
                CalendarEntry(id: "device#\(item.id)", title: item.title, start: item.start, end: item.end,
                              isAllDay: item.isAllDay, location: item.location ?? item.calendarTitle,
                              color: Color(hex: CalendarColors.external), source: .device)
            }
        }
        if showsTodos {
            result += todos.filter(includes).compactMap { todo in
                guard let due = todo.dueDate, !todo.isDone,
                      let end = Calendar.current.date(byAdding: .day, value: 1, to: due) else { return nil }
                return CalendarEntry(id: "todo#\(todo.objectID.uriRepresentation())", title: todo.title ?? "",
                                     start: due, end: end, isAllDay: true, location: nil,
                                     color: todo.family.flatMap { familyColors[$0.objectID] } ?? personalColor,
                                     source: .todo(todo))
            }
        }
        if let interval {
            let calendar = Calendar.current
            for (day, list) in observances(in: interval) {
                guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
                result += list.map { observance in
                    CalendarEntry(id: "observance#\(day.timeIntervalSince1970)#\(observance.germanName)",
                                  title: observance.name(), start: day, end: end, isAllDay: true, location: nil,
                                  color: Color(hex: CalendarColors.external), source: .observance)
                }
            }
        }
        return result
    }

    /// Beim Personenfilter: der Person zugewiesen oder niemandem in ihrer Familie. Private Todos
    /// gehören nur einem selbst.
    func includes(_ todo: TodoItem) -> Bool {
        guard let person else { return true }
        if let assignee = todo.assignee { return assignee == person }
        return todo.family != nil && todo.family == person.family
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

    func observances(in interval: DateInterval) -> [Date: [Holiday]] {
        showsObservances && !holidayRegions.isEmpty
            ? Holidays.observances(in: holidayRegions, overlapping: interval) : [:]
    }

    func color(for event: Event) -> Color {
        if event.isBirthday, let birthdayColor { return birthdayColor }
        return event.calendar?.id.flatMap { colors[$0] } ?? .gray
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

/// Ein Eintrag im Raster und in der Tagesliste: eigener Termin, Abo-Termin, Gerätekalender, Todo oder besonderer Tag.
struct CalendarEntry: Identifiable {
    enum Source {
        case event(Occurrence)
        case subscription
        case device
        case todo(TodoItem)
        /// Besonderer Tag ohne Feiertag, z. B. 1. Advent.
        case observance
    }

    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let color: Color
    let source: Source

    var occurrence: Occurrence? {
        if case .event(let occurrence) = source { return occurrence }
        return nil
    }

    var isDevice: Bool {
        if case .device = source { return true }
        return false
    }

    var isObservance: Bool {
        if case .observance = source { return true }
        return false
    }

    /// Gerätekalender und besondere Tage stehen zurückhaltender da als eigene Termine.
    var isMuted: Bool { isDevice || isObservance }

    var todo: TodoItem? {
        if case .todo(let todo) = source { return todo }
        return nil
    }

    /// Eigene Termine und Todos lassen sich auf einen anderen Tag ziehen, Abos und Gerätekalender nicht.
    var isMovable: Bool { occurrence != nil || todo != nil }

    var isBirthday: Bool { occurrence?.event.isBirthday == true }

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
