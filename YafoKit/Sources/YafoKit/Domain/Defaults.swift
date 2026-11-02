import Foundation

/// Vorgaben für Erinnerungen ab Werk. Offsets in Sekunden vor dem Bezugszeitpunkt.
nonisolated public enum AlertDefaults {
    /// Termine mit Uhrzeit: 30 Minuten vorher.
    public static let timedEventOffset: Double = 30 * 60
    /// Ganztägig: am Vortag um 18 Uhr, also 6 Stunden vor 0 Uhr des Termintags.
    public static let allDayEventOffset: Double = 6 * 60 * 60
    /// Todos: am Fälligkeitstag um 9 Uhr, also 9 Stunden *nach* 0 Uhr (negativer Offset).
    public static let todoOffset: Double = -9 * 60 * 60
    /// Geburtstage: am Tag selbst um 9 Uhr.
    public static let birthdayOffset: Double = -9 * 60 * 60
}

/// Standardfarben je Kalendertyp (siehe Farbsystem in docs/).
nonisolated public enum CalendarColors {
    public static let sharedDefault = "#2F80ED"      // Blau
    public static let personalDefault = "#27AE60"    // Grün
    public static let publicHoliday = "#EB5757"      // Rot
    public static let schoolHoliday = "#FFD8A8"      // Helles Orange
    public static let external = "#8E8E93"           // Grau

    /// Weitere geteilte Kalender bekommen der Reihe nach eigene, kräftige Farben.
    public static let additionalShared = ["#9B51E0", "#F2994A", "#00B8A9", "#EB5794", "#5B6CFF"]

    public static func defaultColor(for kind: CalendarKind, existingSharedCount: Int = 0) -> String {
        switch kind {
        case .personal:
            return personalDefault
        case .shared where existingSharedCount == 0:
            return sharedDefault
        case .shared:
            return additionalShared[(existingSharedCount - 1) % additionalShared.count]
        }
    }
}

nonisolated public enum Initials {
    /// „Anna Maria Schmidt“ → „AS“, „Mama“ → „MA“, leerer Name → „?“.
    public static func make(from name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace || $0 == "-" })
        guard let first = words.first?.first else { return "?" }
        if words.count > 1, let last = words.last?.first {
            return String([first, last]).uppercased()
        }
        return String(words[0].prefix(2)).uppercased()
    }
}
