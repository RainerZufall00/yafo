import Foundation

/// Ein VEVENT aus einer ICS-Datei, bereits in absolute Zeiten umgerechnet.
nonisolated public struct ICSEvent: Equatable, Sendable {
    public var uid: String
    public var summary: String
    public var location: String?
    public var notes: String?
    public var start: Date
    /// Exklusives Ende; bei Ganztägigem 0 Uhr des Folgetags.
    public var end: Date
    public var isAllDay: Bool
    /// Zeitzone des Beginns (TZID), `nil` bei UTC, floating oder ganztägig.
    public var timeZone: String?
    public var recurrenceRule: String?
    public var excludedDates: [Date]
    /// Gesetzt bei einem geänderten Vorkommen einer Serie: dessen ursprünglicher Beginn.
    public var recurrenceID: Date?
    public var isCancelled: Bool
    /// Was yafo nicht übernimmt (Gäste, Anhänge, Videokonferenz-Links).
    public var hasAttendees: Bool
    public var hasAttachments: Bool
    public var hasConferenceLink: Bool

    public init(uid: String, summary: String, location: String?, notes: String?, start: Date, end: Date,
                isAllDay: Bool, timeZone: String?, recurrenceRule: String?, excludedDates: [Date],
                recurrenceID: Date?, isCancelled: Bool, hasAttendees: Bool, hasAttachments: Bool,
                hasConferenceLink: Bool) {
        self.uid = uid
        self.summary = summary
        self.location = location
        self.notes = notes
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.timeZone = timeZone
        self.recurrenceRule = recurrenceRule
        self.excludedDates = excludedDates
        self.recurrenceID = recurrenceID
        self.isCancelled = isCancelled
        self.hasAttendees = hasAttendees
        self.hasAttachments = hasAttachments
        self.hasConferenceLink = hasConferenceLink
    }
}

/// Liest VEVENTs aus iCalendar-Text (RFC 5545). Gemeinsam für Abos und Importe.
nonisolated public enum ICSParser {
    public static func parse(_ text: String, calendar: Calendar = .current) -> [ICSEvent] {
        var events: [ICSEvent] = []
        var current: [Property]?
        var depth = 0
        for line in unfold(text) {
            let property = Property(line)
            switch (property.name, property.value.uppercased()) {
            case ("BEGIN", "VEVENT"):
                current = []
                depth = 0
            case ("BEGIN", _) where current != nil:
                // Verschachtelte Komponenten (VALARM) überspringen.
                depth += 1
            case ("END", "VEVENT"):
                if let properties = current, let event = makeEvent(properties, calendar: calendar) {
                    events.append(event)
                }
                current = nil
            case ("END", _) where current != nil:
                depth -= 1
            default:
                if depth == 0 { current?.append(property) }
            }
        }
        return events
    }

    // MARK: Zeilen

    /// Fortsetzungszeilen beginnen mit Leerzeichen oder Tab und gehören zur vorigen Zeile.
    static func unfold(_ text: String) -> [String] {
        var lines: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else if !raw.isEmpty {
                lines.append(String(raw))
            }
        }
        return lines
    }

    struct Property {
        var name: String
        var parameters: [String: String]
        var value: String

        init(_ line: String) {
            // Name und Parameter enden am ersten Doppelpunkt außerhalb von Anführungszeichen.
            var inQuotes = false
            var split = line.endIndex
            for index in line.indices {
                let character = line[index]
                if character == "\"" { inQuotes.toggle() }
                if character == ":" && !inQuotes { split = index; break }
            }
            let head = line[..<split]
            value = split < line.endIndex ? String(line[line.index(after: split)...]) : ""
            let parts = head.split(separator: ";").map(String.init)
            name = parts.first?.uppercased() ?? ""
            var parameters: [String: String] = [:]
            for part in parts.dropFirst() {
                let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
                if pair.count == 2 {
                    parameters[pair[0].uppercased()] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
            self.parameters = parameters
        }
    }

    // MARK: Termin

    private static func makeEvent(_ properties: [Property], calendar: Calendar) -> ICSEvent? {
        func first(_ name: String) -> Property? { properties.first { $0.name == name } }

        guard let startProperty = first("DTSTART"),
              let start = parseDate(startProperty, calendar: calendar) else { return nil }
        let uid = first("UID")?.value ?? UUID().uuidString

        var end: Date
        if let endProperty = first("DTEND"), let parsed = parseDate(endProperty, calendar: calendar) {
            end = parsed.date
        } else if let duration = first("DURATION").flatMap({ parseDuration($0.value) }) {
            end = calendar.date(byAdding: duration, to: start.date) ?? start.date
        } else {
            end = start.isAllDay ? calendar.date(byAdding: .day, value: 1, to: start.date)! : start.date
        }
        if end < start.date { end = start.date }

        let excluded = properties.filter { $0.name == "EXDATE" }.flatMap { property in
            property.value.split(separator: ",").compactMap { value -> Date? in
                var single = property
                single.value = String(value)
                return parseDate(single, calendar: calendar)?.date
            }
        }

        return ICSEvent(
            uid: uid,
            summary: first("SUMMARY").map { unescape($0.value) } ?? "",
            location: first("LOCATION").map { unescape($0.value) }.flatMap { $0.isEmpty ? nil : $0 },
            notes: first("DESCRIPTION").map { unescape($0.value) }.flatMap { $0.isEmpty ? nil : $0 },
            start: start.date, end: end, isAllDay: start.isAllDay, timeZone: start.timeZone,
            recurrenceRule: first("RRULE")?.value,
            excludedDates: excluded,
            recurrenceID: first("RECURRENCE-ID").flatMap { parseDate($0, calendar: calendar)?.date },
            isCancelled: first("STATUS")?.value.uppercased() == "CANCELLED",
            hasAttendees: properties.contains { $0.name == "ATTENDEE" },
            hasAttachments: properties.contains { $0.name == "ATTACH" },
            hasConferenceLink: properties.contains { $0.name == "CONFERENCE" || $0.name == "X-GOOGLE-CONFERENCE" }
                || (first("DESCRIPTION")?.value.contains("meet.google.com") ?? false)
                || (first("DESCRIPTION")?.value.contains("zoom.us") ?? false))
    }

    // MARK: Werte

    struct ParsedDate {
        var date: Date
        var isAllDay: Bool
        var timeZone: String?
    }

    /// `20261103` (ganztägig, lokal 0 Uhr), `20261103T100000Z` (UTC),
    /// `20261103T100000` mit TZID oder floating (lokal).
    static func parseDate(_ property: Property, calendar: Calendar) -> ParsedDate? {
        let value = property.value.trimmingCharacters(in: .whitespaces)
        let digits = value.filter(\.isNumber)
        guard digits.count >= 8,
              let year = Int(digits.prefix(4)),
              let month = Int(digits.dropFirst(4).prefix(2)),
              let day = Int(digits.dropFirst(6).prefix(2)) else { return nil }

        if property.parameters["VALUE"] == "DATE" || !value.contains("T") {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
            return ParsedDate(date: calendar.startOfDay(for: date), isAllDay: true, timeZone: nil)
        }
        guard digits.count >= 14,
              let hour = Int(digits.dropFirst(8).prefix(2)),
              let minute = Int(digits.dropFirst(10).prefix(2)),
              let second = Int(digits.dropFirst(12).prefix(2)) else { return nil }

        var zoned = Calendar(identifier: .gregorian)
        var timeZoneID: String?
        if value.hasSuffix("Z") {
            zoned.timeZone = TimeZone(identifier: "UTC")!
        } else if let tzid = property.parameters["TZID"], let zone = timeZone(for: tzid) {
            zoned.timeZone = zone
            timeZoneID = zone.identifier
        } else {
            zoned.timeZone = calendar.timeZone
        }
        guard let date = zoned.date(from: DateComponents(year: year, month: month, day: day,
                                                         hour: hour, minute: minute, second: second))
        else { return nil }
        return ParsedDate(date: date, isAllDay: false, timeZone: timeZoneID)
    }

    /// TZIDs sind meist Olson-Namen; Outlook schreibt Windows-Namen wie „W. Europe Standard Time“.
    static func timeZone(for tzid: String) -> TimeZone? {
        if let zone = TimeZone(identifier: tzid) { return zone }
        let windows: [String: String] = [
            "W. Europe Standard Time": "Europe/Berlin",
            "Central Europe Standard Time": "Europe/Budapest",
            "Romance Standard Time": "Europe/Paris",
            "GMT Standard Time": "Europe/London",
            "UTC": "UTC",
            "Eastern Standard Time": "America/New_York",
            "Pacific Standard Time": "America/Los_Angeles",
        ]
        if let mapped = windows[tzid] { return TimeZone(identifier: mapped) }
        // Manche Exporte hängen Pfade an („/mozilla.org/.../Europe/Berlin“).
        return TimeZone(identifier: tzid.split(separator: "/").suffix(2).joined(separator: "/"))
    }

    /// `P1D`, `PT1H30M`, `P2W`, `-PT15M` (Vorzeichen wird ignoriert).
    static func parseDuration(_ value: String) -> DateComponents? {
        var components = DateComponents()
        var number = ""
        var inTime = false
        for character in value.uppercased() {
            switch character {
            case "P", "+", "-": continue
            case "T": inTime = true
            case "0"..."9": number.append(character)
            default:
                guard let amount = Int(number) else { return nil }
                switch (character, inTime) {
                case ("W", _): components.day = (components.day ?? 0) + amount * 7
                case ("D", _): components.day = (components.day ?? 0) + amount
                case ("H", true): components.hour = amount
                case ("M", true): components.minute = amount
                case ("S", true): components.second = amount
                default: return nil
                }
                number = ""
            }
        }
        return components
    }

    static func unescape(_ value: String) -> String {
        var result = ""
        var escaping = false
        for character in value {
            if escaping {
                switch character {
                case "n", "N": result.append("\n")
                default: result.append(character)
                }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        return result
    }
}
