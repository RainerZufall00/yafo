import Foundation

/// Schreibt Termine als iCalendar (RFC 5545), lesbar für jede Kalender-App.
/// Serien behalten ihre Regel; abgesagte Vorkommen werden EXDATE, geänderte eigene
/// VEVENTs mit RECURRENCE-ID.
nonisolated public enum ICSWriter {
    /// Ein Termin, wie er in die Datei geht; unabhängig von Core Data, damit testbar.
    public struct Item: Sendable {
        public struct Override: Sendable {
            public var originalStart: Date
            public var isCancelled: Bool
            public var title: String?
            public var start: Date?
            public var end: Date?
            public var location: String?
            public var notes: String?

            public init(originalStart: Date, isCancelled: Bool, title: String? = nil, start: Date? = nil,
                        end: Date? = nil, location: String? = nil, notes: String? = nil) {
                self.originalStart = originalStart
                self.isCancelled = isCancelled
                self.title = title
                self.start = start
                self.end = end
                self.location = location
                self.notes = notes
            }
        }

        public var uid: String
        public var title: String
        public var start: Date
        public var end: Date
        public var isAllDay: Bool
        public var timeZone: String?
        public var location: String?
        public var description: String?
        public var recurrenceRule: String?
        public var overrides: [Override]

        public init(uid: String, title: String, start: Date, end: Date, isAllDay: Bool, timeZone: String? = nil,
                    location: String? = nil, description: String? = nil, recurrenceRule: String? = nil,
                    overrides: [Override] = []) {
            self.uid = uid
            self.title = title
            self.start = start
            self.end = end
            self.isAllDay = isAllDay
            self.timeZone = timeZone
            self.location = location
            self.description = description
            self.recurrenceRule = recurrenceRule
            self.overrides = overrides
        }
    }

    public static func document(name: String?, items: [Item], now: Date = .now) -> String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//yafo//yafo//DE", "CALSCALE:GREGORIAN"]
        if let name { lines.append("X-WR-CALNAME:\(escape(name))") }
        let stamp = "DTSTAMP:\(utc(now))"
        for item in items {
            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(escape(item.uid))")
            lines.append(stamp)
            lines += dateLines(item, start: item.start, end: item.end)
            if let rule = item.recurrenceRule {
                lines.append("RRULE:\(rule)")
                for cancelled in item.overrides where cancelled.isCancelled {
                    lines.append(dateProperty("EXDATE", cancelled.originalStart, item))
                }
            }
            lines += textLines(title: item.title, location: item.location, description: item.description)
            lines.append("END:VEVENT")

            guard item.recurrenceRule != nil else { continue }
            for change in item.overrides where !change.isCancelled {
                let start = change.start ?? change.originalStart
                let end = change.end ?? start.addingTimeInterval(item.end.timeIntervalSince(item.start))
                lines.append("BEGIN:VEVENT")
                lines.append("UID:\(escape(item.uid))")
                lines.append(stamp)
                lines.append(dateProperty("RECURRENCE-ID", change.originalStart, item))
                lines += dateLines(item, start: start, end: end)
                lines += textLines(title: change.title ?? item.title, location: change.location ?? item.location,
                                   description: change.notes ?? item.description)
                lines.append("END:VEVENT")
            }
        }
        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    // MARK: Zeilen

    private static func dateLines(_ item: Item, start: Date, end: Date) -> [String] {
        [dateProperty("DTSTART", start, item), dateProperty("DTEND", item.isAllDay ? dayAfter(start, end) : end, item)]
    }

    /// Ganztägig ist DTEND der Tag nach dem letzten Tag; ein Ende im Lauf des letzten Tags
    /// (z. B. 23:59) oder gleich dem Beginn wird auf die nächste Mitternacht aufgerundet.
    private static func dayAfter(_ start: Date, _ end: Date) -> Date {
        let calendar = Calendar.current
        let lastDay = calendar.startOfDay(for: end)
        let rounded = lastDay == end ? end : calendar.date(byAdding: .day, value: 1, to: lastDay)!
        return max(rounded, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start))!)
    }

    private static func textLines(title: String, location: String?, description: String?) -> [String] {
        var lines = ["SUMMARY:\(escape(title))"]
        if let location, !location.isEmpty { lines.append("LOCATION:\(escape(location))") }
        if let description, !description.isEmpty { lines.append("DESCRIPTION:\(escape(description))") }
        return lines
    }

    /// Ganztägig als DATE, mit Zeitzone als lokale Zeit mit TZID, sonst UTC.
    static func dateProperty(_ name: String, _ date: Date, _ item: Item) -> String {
        if item.isAllDay {
            return "\(name);VALUE=DATE:\(format(date, "yyyyMMdd", TimeZone.current))"
        }
        if let id = item.timeZone, let zone = TimeZone(identifier: id), id != "UTC", id != "GMT" {
            return "\(name);TZID=\(id):\(format(date, "yyyyMMdd'T'HHmmss", zone))"
        }
        return "\(name):\(utc(date))"
    }

    private static func utc(_ date: Date) -> String {
        format(date, "yyyyMMdd'T'HHmmss'Z'", TimeZone(identifier: "UTC")!)
    }

    private static func format(_ date: Date, _ pattern: String, _ zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Zeilen über 75 Byte werden umbrochen; Fortsetzungszeilen beginnen mit einem Leerzeichen.
    /// Mehrbyte-Zeichen werden nicht zerteilt.
    static func fold(_ line: String) -> String {
        guard line.utf8.count > 75 else { return line }
        var parts: [String] = []
        var current = ""
        var bytes = 0
        for character in line {
            let size = String(character).utf8.count
            let limit = parts.isEmpty ? 75 : 74
            if bytes + size > limit {
                parts.append(current)
                current = ""
                bytes = 0
            }
            current.append(character)
            bytes += size
        }
        parts.append(current)
        return parts.joined(separator: "\r\n ")
    }
}

/// Tabellen als CSV (RFC 4180) mit UTF-8-BOM, damit Excel Umlaute richtig liest.
nonisolated public enum CSVWriter {
    public static func table(header: [String], rows: [[String]]) -> String {
        "\u{FEFF}" + ([header] + rows).map { $0.map(field).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == ";" || $0.isNewline }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
