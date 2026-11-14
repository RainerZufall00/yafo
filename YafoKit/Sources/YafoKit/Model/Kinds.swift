import Foundation

/// Erwachsener (eigener Apple Account) oder Kind (Profil, ggf. später mit Account verknüpft).
public enum MemberKind: String, CaseIterable, Sendable {
    case adult
    case child
}

public enum CalendarKind: String, CaseIterable, Sendable {
    /// Familienkalender, liegt im Share der Familie.
    case shared
    /// Eigener Kalender, liegt nur im privaten Store.
    case personal
}

/// Normaler Termin oder Geburtstag (ganztägig, jährlich, mit Alter).
public enum EventKind: String, CaseIterable, Sendable {
    case event
    case birthday
}

/// Darstellung der Termine eines Kalenders, pro Nutzer (`CalendarAppearance`). Die Jahresansicht
/// zeigt mehrtägige Termine immer als volles Band.
public enum EventStyle: String, CaseIterable, Sendable {
    /// Farbiger Rand (Standard).
    case outlined
    /// Schraffur mit farbigem Rand.
    case hatched
    /// Volle Farbe mit weißer Schrift.
    case filled
}

public enum SubscriptionKind: String, CaseIterable, Sendable {
    case publicHolidays
    case schoolHolidays
    case ics
}

public enum OwnerTransferStatus: String, CaseIterable, Sendable {
    case requested
    case accepted
    case shared
    case completed
    case cancelled
}
