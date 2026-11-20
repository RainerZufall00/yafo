import Foundation

/// Kalender, der bei neuen Terminen vorausgewählt ist (Einstellung „Standardkalender“). Liegt in der
/// App Group, damit auch die Share Extension („Termin aus Screenshot“) ihn kennt. Nur auf dem Gerät,
/// jedes Familienmitglied wählt selbst.
public enum DefaultCalendar {
    public static let key = "defaultCalendarID"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: PersistenceController.appGroupIdentifier) ?? .standard
    }

    /// `id` des gewählten Kalenders; `nil` heißt „wie bisher“ (der älteste Kalender).
    public static var id: String? {
        get { defaults.string(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }

    /// Der gewählte Kalender, sonst (nicht gesetzt oder gelöscht) der erste der Liste.
    public static func pick(from calendars: some Collection<EventCalendar>) -> EventCalendar? {
        guard let id else { return calendars.first }
        return calendars.first { $0.id?.uuidString == id } ?? calendars.first
    }
}
