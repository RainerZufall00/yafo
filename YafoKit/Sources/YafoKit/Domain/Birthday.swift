import Foundation

extension Event {
    public var kind: EventKind {
        get { kindRaw.flatMap(EventKind.init(rawValue:)) ?? .event }
        set { kindRaw = newValue.rawValue }
    }

    public var isBirthday: Bool { kind == .birthday }
}

extension Occurrence {
    /// Alter, das an diesem Geburtstag erreicht wird; `nil` ohne Geburtsjahr oder vor der Geburt.
    public var age: Int? {
        guard event.isBirthday, event.birthYear > 0 else { return nil }
        let age = Calendar.current.component(.year, from: start) - Int(event.birthYear)
        return age >= 0 ? age : nil
    }
}

/// Geburtstage sind ganztägige Jahresserien. Mit Geburtsjahr beginnt die Serie am Tag der Geburt,
/// sonst im Jahr des gewählten Tages.
nonisolated public enum Birthday {
    public static func seriesStart(day: Date, birthYear: Int?, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        if let birthYear, birthYear > 0 { components.year = birthYear }
        // 29. Februar in einem Nicht-Schaltjahr: auf den 28. ausweichen.
        let start = calendar.date(from: components).flatMap {
            calendar.component(.day, from: $0) == components.day ? $0 : nil
        } ?? calendar.date(from: DateComponents(year: components.year, month: components.month, day: 28))!
        return calendar.startOfDay(for: start)
    }

    /// Jährlich; wer am 29. Februar Geburtstag hat, feiert sonst am 28.
    public static func rule(for day: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.month, .day], from: day)
        return components.month == 2 && components.day == 29
            ? "FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=-1"
            : "FREQ=YEARLY"
    }
}
