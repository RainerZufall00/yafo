import CoreData
import Foundation

/// Ein oder mehrere ganztägige Termine, die nach demselben Geburtstag aussehen (z. B. aus einem
/// importierten Kalender: eine Serie oder ein Termin pro Jahr). Umwandeln macht daraus einen Geburtstag.
public struct BirthdaySuggestion: Identifiable {
    /// Zuerst der Termin, der zum Geburtstag wird (eine Jahresserie, sonst der früheste); die übrigen
    /// sind Doppel aus anderen Jahren und werden beim Umwandeln gelöscht.
    public let events: [Event]
    public let name: String
    public let birthYear: Int?

    public var event: Event { events[0] }
    public var id: NSManagedObjectID { event.objectID }
    /// Tag und Monat zählen.
    public var day: Date { event.start ?? .distantPast }
    public var duplicates: ArraySlice<Event> { events.dropFirst() }
}

extension Repository {
    /// Ganztägige Termine, deren Titel nach Geburtstag aussieht und die noch keine sind.
    /// `dismissed` sind `id`s von Terminen, deren Vorschlag weggeklickt wurde.
    public func birthdaySuggestions(dismissed: Set<String> = []) -> [BirthdaySuggestion] {
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.predicate = Self.birthdayCandidatePredicate
        return Self.birthdaySuggestions(among: (try? context.fetch(request)) ?? [], dismissed: dismissed)
    }

    /// Vorschlag für genau diesen Termin, samt Doppeln im selben Kalender.
    public func birthdaySuggestion(for event: Event) -> BirthdaySuggestion? {
        guard !event.isBirthday, event.isAllDay, let title = event.title,
              BirthdayDetector.guess(title: title) != nil else { return nil }
        return birthdaySuggestions().first { $0.events.contains(event) }
    }

    /// Für `@FetchRequest`: ganztägige Termine, die keine Geburtstage sind.
    public static var birthdayCandidatePredicate: NSPredicate {
        NSPredicate(format: "isAllDay == YES AND (kindRaw == nil OR kindRaw != %@) AND calendar != nil",
                    EventKind.birthday.rawValue)
    }

    /// Gruppiert nach Kalender, Name und Tag: Ein Termin je Jahr wird zu einem Vorschlag.
    public static func birthdaySuggestions(among events: some Sequence<Event>, dismissed: Set<String> = [],
                                           calendar cal: Calendar = .current) -> [BirthdaySuggestion] {
        var groups: [SuggestionKey: (guess: BirthdayDetector.Guess, events: [Event])] = [:]
        for event in events {
            guard !event.isBirthday, event.isAllDay, let start = event.start, let title = event.title,
                  let guess = BirthdayDetector.guess(title: title, calendar: cal) else { continue }
            let parts = cal.dateComponents([.month, .day], from: start)
            let key = SuggestionKey(calendar: event.calendar?.objectID, name: guess.name.lowercased(),
                          month: parts.month ?? 0, day: parts.day ?? 0)
            var group = groups[key] ?? (guess, [])
            group.events.append(event)
            if group.guess.birthYear == nil { group.guess.birthYear = guess.birthYear }
            groups[key] = group
        }
        return groups.values.compactMap { group in
            let events = group.events.sorted {
                ($0.isRecurring ? 0 : 1, $0.start ?? .distantPast) < ($1.isRecurring ? 0 : 1, $1.start ?? .distantPast)
            }
            guard !events.contains(where: { $0.id.map { dismissed.contains($0.uuidString) } ?? false }) else { return nil }
            return BirthdaySuggestion(events: events, name: group.guess.name, birthYear: group.guess.birthYear)
        }
        .sorted { lhs, rhs in
            let l = cal.dateComponents([.month, .day], from: lhs.day), r = cal.dateComponents([.month, .day], from: rhs.day)
            return (l.month ?? 0, l.day ?? 0, lhs.name) < (r.month ?? 0, r.day ?? 0, rhs.name)
        }
    }

    /// Macht aus dem Vorschlag einen Geburtstag (jährlich, mit Alter, wenn das Jahr bekannt ist) und
    /// löscht die Doppel aus anderen Jahren.
    @discardableResult
    public func convertToBirthday(_ suggestion: BirthdaySuggestion) -> Event? {
        let event = suggestion.event
        guard let calendar = event.calendar, let start = event.start else { return nil }
        for duplicate in suggestion.duplicates { delete(duplicate) }
        return updateBirthday(event, name: suggestion.name, day: start, birthYear: suggestion.birthYear,
                              calendar: calendar, notes: event.notes)
    }
}

private struct SuggestionKey: Hashable {
    let calendar: NSManagedObjectID?
    let name: String
    let month: Int, day: Int
}

// MARK: - Geburtstagsfarbe

extension Repository {
    /// `CalendarAppearance.calendarID` für die eigene Farbe aller Geburtstage (nur für einen selbst).
    public static let birthdayAppearanceID = "birthdays"
    /// Gespeicherter Wert: Geburtstage in der Farbe ihres Kalenders.
    public static let calendarColorMarker = "calendar"

    /// Farbe der Geburtstage als Hex; `nil` heißt: Farbe des Kalenders.
    public func birthdayColor() -> String? {
        Self.birthdayColor(appearanceColor: birthdayAppearance()?.color)
    }

    /// Aus dem gespeicherten Wert: ohne Eintrag die Vorgabe, mit Marker die Kalenderfarbe.
    public nonisolated static func birthdayColor(appearanceColor: String?) -> String? {
        switch appearanceColor {
        case nil, "": CalendarColors.birthdayDefault
        case calendarColorMarker: nil
        case let color?: color
        }
    }

    /// `nil` setzt die Geburtstage auf die Farbe ihres Kalenders.
    public func setBirthdayColor(_ color: String?) {
        let appearance = birthdayAppearance() ?? {
            let new = insert(CalendarAppearance.self, into: persistence.privateStore)
            new.calendarID = Self.birthdayAppearanceID
            return new
        }()
        appearance.color = color ?? Self.calendarColorMarker
    }

    /// Farbe eines Termins als Hex: Geburtstage in ihrer eigenen Farbe, sonst die des Kalenders.
    public func color(of event: Event) -> String {
        if event.isBirthday, let color = birthdayColor() { return color }
        return event.calendar.map(color(of:)) ?? CalendarColors.personalDefault
    }

    private func birthdayAppearance() -> CalendarAppearance? {
        let request = NSFetchRequest<CalendarAppearance>(entityName: "CalendarAppearance")
        request.predicate = NSPredicate(format: "calendarID == %@", Self.birthdayAppearanceID)
        request.affectedStores = [persistence.privateStore]
        return (try? context.fetch(request))?.first
    }
}
