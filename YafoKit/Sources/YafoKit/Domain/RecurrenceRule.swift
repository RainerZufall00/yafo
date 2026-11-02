import Foundation

/// Wiederholungsregel nach RFC 5545 (RRULE). Unterstützt FREQ, INTERVAL, COUNT, UNTIL, BYDAY
/// (auch mit Ordinalzahl wie `2MO` oder `-1FR`), BYMONTHDAY, BYMONTH und WKST.
/// Unbekannte Teile (z. B. aus einem Import) bleiben beim Speichern erhalten, werden aber
/// beim Berechnen ignoriert.
nonisolated public struct RecurrenceRule: Equatable, Sendable {
    public enum Frequency: String, Sendable, CaseIterable {
        case daily = "DAILY"
        case weekly = "WEEKLY"
        case monthly = "MONTHLY"
        case yearly = "YEARLY"
    }

    /// Wochentag wie bei `Calendar` (1 = Sonntag … 7 = Samstag), optional mit Ordinalzahl
    /// innerhalb des Monats (1 = erster, -1 = letzter).
    public struct Weekday: Hashable, Sendable {
        public var weekday: Int
        public var ordinal: Int?

        public init(_ weekday: Int, ordinal: Int? = nil) {
            self.weekday = weekday
            self.ordinal = ordinal
        }
    }

    public var frequency: Frequency
    public var interval: Int
    public var count: Int?
    /// Letzter möglicher Beginn (inklusiv).
    public var until: Date?
    public var byDay: [Weekday]
    public var byMonthDay: [Int]
    public var byMonth: [Int]
    public var weekStart: Int
    /// Nicht unterstützte Teile, z. B. `BYSETPOS=-1`, unverändert für die Rückgabe.
    public var otherParts: [String]

    public init(frequency: Frequency, interval: Int = 1, count: Int? = nil, until: Date? = nil,
                byDay: [Weekday] = [], byMonthDay: [Int] = [], byMonth: [Int] = [], weekStart: Int = 2) {
        self.frequency = frequency
        self.interval = max(interval, 1)
        self.count = count
        self.until = until
        self.byDay = byDay
        self.byMonthDay = byMonthDay
        self.byMonth = byMonth
        self.weekStart = weekStart
        otherParts = []
    }

    // MARK: - Text

    private static let weekdayCodes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]

    public init?(rrule: String) {
        var text = rrule.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.uppercased().hasPrefix("RRULE:") { text.removeFirst(6) }
        var values: [String: String] = [:]
        var other: [String] = []
        for part in text.split(separator: ";") where !part.isEmpty {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return nil }
            let key = pair[0].uppercased()
            switch key {
            case "FREQ", "INTERVAL", "COUNT", "UNTIL", "BYDAY", "BYMONTHDAY", "BYMONTH", "WKST":
                values[key] = pair[1].uppercased()
            default:
                other.append(String(part))
            }
        }
        guard let freq = values["FREQ"].flatMap(Frequency.init(rawValue:)) else { return nil }
        self.init(frequency: freq)
        if let raw = values["INTERVAL"] {
            guard let value = Int(raw), value > 0 else { return nil }
            interval = value
        }
        if let raw = values["COUNT"] {
            guard let value = Int(raw), value > 0 else { return nil }
            count = value
        }
        if let raw = values["UNTIL"] {
            guard let date = Self.parseUntil(raw) else { return nil }
            until = date
        }
        if let raw = values["BYDAY"] {
            for item in raw.split(separator: ",") {
                let code = String(item.suffix(2))
                guard let index = Self.weekdayCodes.firstIndex(of: code) else { return nil }
                let prefix = item.dropLast(2)
                var ordinal: Int?
                if !prefix.isEmpty {
                    guard let value = Int(prefix.replacingOccurrences(of: "+", with: "")), value != 0 else { return nil }
                    ordinal = value
                }
                byDay.append(Weekday(index + 1, ordinal: ordinal))
            }
        }
        if let raw = values["BYMONTHDAY"] {
            byMonthDay = raw.split(separator: ",").compactMap { Int($0) }.filter { $0 != 0 && abs($0) <= 31 }
        }
        if let raw = values["BYMONTH"] {
            byMonth = raw.split(separator: ",").compactMap { Int($0) }.filter { (1...12).contains($0) }
        }
        if let raw = values["WKST"], let index = Self.weekdayCodes.firstIndex(of: raw) {
            weekStart = index + 1
        }
        otherParts = other
    }

    public var rruleString: String {
        var parts = ["FREQ=\(frequency.rawValue)"]
        if interval > 1 { parts.append("INTERVAL=\(interval)") }
        if !byDay.isEmpty {
            parts.append("BYDAY=" + byDay.map { day in
                (day.ordinal.map(String.init) ?? "") + Self.weekdayCodes[day.weekday - 1]
            }.joined(separator: ","))
        }
        if !byMonthDay.isEmpty { parts.append("BYMONTHDAY=" + byMonthDay.map(String.init).joined(separator: ",")) }
        if !byMonth.isEmpty { parts.append("BYMONTH=" + byMonth.map(String.init).joined(separator: ",")) }
        if weekStart != 2 { parts.append("WKST=\(Self.weekdayCodes[weekStart - 1])") }
        if let count {
            parts.append("COUNT=\(count)")
        } else if let until {
            parts.append("UNTIL=\(Self.formatUntil(until))")
        }
        return (parts + otherParts).joined(separator: ";")
    }

    private static let utc = TimeZone(identifier: "UTC")!

    private static func parseUntil(_ raw: String) -> Date? {
        let digits = raw.filter(\.isNumber)
        func number(_ range: Range<Int>) -> Int? {
            guard digits.count >= range.upperBound else { return nil }
            let start = digits.index(digits.startIndex, offsetBy: range.lowerBound)
            let end = digits.index(digits.startIndex, offsetBy: range.upperBound)
            return Int(digits[start..<end])
        }
        guard let year = number(0..<4), let month = number(4..<6), let day = number(6..<8) else { return nil }
        var components = DateComponents(year: year, month: month, day: day)
        var calendar = Calendar(identifier: .gregorian)
        if digits.count >= 14, let hour = number(8..<10), let minute = number(10..<12), let second = number(12..<14) {
            components.hour = hour
            components.minute = minute
            components.second = second
            calendar.timeZone = raw.hasSuffix("Z") ? utc : .current
        } else {
            // Nur Datum: der ganze Tag zählt noch mit.
            components.hour = 23
            components.minute = 59
            components.second = 59
            calendar.timeZone = .current
        }
        return calendar.date(from: components)
    }

    private static func formatUntil(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02dT%02d%02d%02dZ", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }

    // MARK: - Berechnen

    /// Beginn aller Vorkommen mit `from <= Beginn < to`. COUNT zählt immer ab `seriesStart`.
    /// Die Uhrzeit bleibt in `calendar` (Zeitzone des Termins) gleich, auch über die Zeitumstellung.
    public func startDates(seriesStart: Date, from: Date, to: Date, calendar: Calendar) -> [Date] {
        // Sekundenbruchteile würden das erste Vorkommen vor den Serienbeginn rutschen lassen.
        let seriesStart = Date(timeIntervalSinceReferenceDate: seriesStart.timeIntervalSinceReferenceDate.rounded(.down))
        var result: [Date] = []
        var produced = 0
        let time = calendar.dateComponents([.hour, .minute, .second], from: seriesStart)
        let firstDay = calendar.startOfDay(for: seriesStart)

        for period in 0..<100_000 {
            guard let (periodStart, days) = candidateDays(period: period * interval, firstDay: firstDay,
                                                          calendar: calendar) else { break }
            if periodStart >= to { break }
            for day in days.sorted() {
                guard let start = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                                                second: time.second ?? 0, of: day),
                      start >= seriesStart else { continue }
                if let until, start > until { return result }
                if let count, produced >= count { return result }
                if start >= to { return result }
                produced += 1
                if start >= from { result.append(start) }
            }
        }
        return result
    }

    /// Anfang der Periode und die Tage (0 Uhr), die darin vorkommen.
    private func candidateDays(period: Int, firstDay: Date, calendar: Calendar) -> (Date, [Date])? {
        let firstComponents = calendar.dateComponents([.year, .month, .day, .weekday], from: firstDay)
        let weekdays = Set(byDay.filter { $0.ordinal == nil }.map(\.weekday))

        switch frequency {
        case .daily:
            guard let day = calendar.date(byAdding: .day, value: period, to: firstDay) else { return nil }
            let c = calendar.dateComponents([.month, .day, .weekday], from: day)
            let matches = (byMonth.isEmpty || byMonth.contains(c.month!))
                && (weekdays.isEmpty || weekdays.contains(c.weekday!))
                && (byMonthDay.isEmpty || monthDays(in: day, calendar: calendar).contains(c.day!))
            return (day, matches ? [day] : [])

        case .weekly:
            let back = (firstComponents.weekday! - weekStart + 7) % 7
            guard let firstWeek = calendar.date(byAdding: .day, value: -back, to: firstDay),
                  let week = calendar.date(byAdding: .day, value: period * 7, to: firstWeek) else { return nil }
            let selected = weekdays.isEmpty ? [firstComponents.weekday!] : Array(weekdays)
            let days = selected.compactMap { weekday in
                calendar.date(byAdding: .day, value: (weekday - weekStart + 7) % 7, to: week)
            }
            .filter { byMonth.isEmpty || byMonth.contains(calendar.component(.month, from: $0)) }
            return (week, days)

        case .monthly:
            guard let firstMonth = calendar.date(from: DateComponents(year: firstComponents.year,
                                                                      month: firstComponents.month, day: 1)),
                  let month = calendar.date(byAdding: .month, value: period, to: firstMonth) else { return nil }
            if !byMonth.isEmpty, !byMonth.contains(calendar.component(.month, from: month)) {
                return (month, [])
            }
            return (month, days(inMonth: month, defaultDay: firstComponents.day!, calendar: calendar))

        case .yearly:
            guard let year = calendar.date(from: DateComponents(year: firstComponents.year! + period, month: 1, day: 1))
            else { return nil }
            let months = byMonth.isEmpty ? [firstComponents.month!] : byMonth
            let days = months.flatMap { month -> [Date] in
                guard let start = calendar.date(byAdding: .month, value: month - 1, to: year) else { return [] }
                return self.days(inMonth: start, defaultDay: firstComponents.day!, calendar: calendar)
            }
            return (year, days)
        }
    }

    /// Tage eines Monats nach BYMONTHDAY bzw. BYDAY, sonst der Tag des Serienbeginns.
    /// Gibt es den Tag im Monat nicht (31. im April), fällt das Vorkommen aus.
    private func days(inMonth month: Date, defaultDay: Int, calendar: Calendar) -> [Date] {
        let length = calendar.range(of: .day, in: .month, for: month)!.count
        func date(_ day: Int) -> Date? { calendar.date(byAdding: .day, value: day - 1, to: month) }

        if !byMonthDay.isEmpty {
            let weekdays = Set(byDay.map(\.weekday))
            return monthDays(in: month, calendar: calendar).compactMap(date)
                .filter { weekdays.isEmpty || weekdays.contains(calendar.component(.weekday, from: $0)) }
        }
        if !byDay.isEmpty {
            let firstWeekday = calendar.component(.weekday, from: month)
            var result: [Date] = []
            for rule in byDay {
                // Alle Tage dieses Wochentags im Monat.
                let first = 1 + (rule.weekday - firstWeekday + 7) % 7
                let all = Array(stride(from: first, through: length, by: 7))
                if let ordinal = rule.ordinal {
                    let index = ordinal > 0 ? ordinal - 1 : all.count + ordinal
                    if all.indices.contains(index), let day = date(all[index]) { result.append(day) }
                } else {
                    result += all.compactMap(date)
                }
            }
            return result
        }
        return defaultDay <= length ? [date(defaultDay)].compactMap { $0 } : []
    }

    /// BYMONTHDAY aufgelöst für den Monat von `day`; negative Werte zählen vom Monatsende.
    private func monthDays(in day: Date, calendar: Calendar) -> [Int] {
        let length = calendar.range(of: .day, in: .month, for: day)!.count
        return byMonthDay.compactMap { value in
            let resolved = value > 0 ? value : length + 1 + value
            return (1...length).contains(resolved) ? resolved : nil
        }
    }
}
