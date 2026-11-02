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
