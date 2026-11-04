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

    /// Alter am Tag `now` für jemanden, der an `birthDate` geboren ist.
    public static func age(birthDate: Date, now: Date = .now, calendar: Calendar = .current) -> Int {
        max(0, yearsBetween(birthDate, now, calendar: calendar))
    }

    /// Volle Jahre von `start` bis `end`; negativ, wenn `start` in der Zukunft liegt.
    static func yearsBetween(_ start: Date, _ end: Date, calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: start), to = calendar.startOfDay(for: end)
        return from > to ? -1 : calendar.dateComponents([.year], from: from, to: to).year ?? 0
    }

    /// Geburtsdatum mit Tag und Monat aus `day`, so dass die Person am Tag `now` `age` Jahre alt ist.
    public static func birthDate(sameDayAs day: Date, age: Int, now: Date = .now,
                                 calendar: Calendar = .current) -> Date {
        let thisYear = calendar.component(.year, from: now)
        let candidate = date(sameDayAs: day, year: thisYear - age, calendar: calendar)
        // Hatte die Person dieses Jahr noch nicht Geburtstag, ist sie ein Jahr früher geboren.
        return yearsBetween(candidate, now, calendar: calendar) < age
            ? date(sameDayAs: day, year: thisYear - age - 1, calendar: calendar)
            : candidate
    }

    /// Letzter Geburtstag mit Tag und Monat aus `day`, der nicht nach `now` liegt. So bleibt der Tag
    /// erhalten, wenn ein Geburtstag ohne Jahr ein Geburtsdatum bekommt (das nicht in der Zukunft liegt).
    public static func latestPast(sameDayAs day: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        birthDate(sameDayAs: day, age: 0, now: now, calendar: calendar)
    }

    /// Tag und Monat aus `day` im Jahr `year`; der 29. Februar wird in Nicht-Schaltjahren zum 28.
    static func date(sameDayAs day: Date, year: Int, calendar: Calendar) -> Date {
        var parts = calendar.dateComponents([.month, .day], from: day)
        parts.year = year
        if let date = calendar.date(from: parts), calendar.component(.day, from: date) == parts.day {
            return date
        }
        parts.day = 28
        return calendar.date(from: parts)!
    }

    /// Jährlich; wer am 29. Februar Geburtstag hat, feiert sonst am 28.
    public static func rule(for day: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.month, .day], from: day)
        return components.month == 2 && components.day == 29
            ? "FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=-1"
            : "FREQ=YEARLY"
    }
}
