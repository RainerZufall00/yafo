import Foundation

/// Ein aus einem Screenshot erkannter Termin, noch ohne Kalender. Steht in der Vorschau zur
/// Bearbeitung und wandert aus der Share Extension über die App Group in die App.
/// Ganztägige Termine enden wie in der App exklusiv um 0 Uhr des Folgetags.
nonisolated public struct EventSuggestion: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?

    public init(id: UUID = UUID(), title: String, start: Date, end: Date, isAllDay: Bool, location: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
    }

    /// Bringt Beginn und Ende in die Form, in der die App Termine speichert.
    public func normalized(calendar: Calendar = .current) -> EventSuggestion {
        var copy = self
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.location = location.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        if isAllDay {
            copy.start = calendar.startOfDay(for: start)
            let lastDay = calendar.startOfDay(for: max(end.addingTimeInterval(-1), start))
            copy.end = calendar.date(byAdding: .day, value: 1, to: max(lastDay, copy.start))!
        } else if end <= start {
            copy.end = start.addingTimeInterval(3600)
        }
        return copy
    }

    // MARK: - Ausgabe des Sprachmodells

    /// Baut einen Vorschlag aus den Textfeldern, die das Sprachmodell liefert
    /// (`yyyy-MM-dd'T'HH:mm` oder `yyyy-MM-dd`). Ohne lesbaren Beginn gibt es keinen Vorschlag.
    public static func fromModel(title: String, start: String, end: String, isAllDay: Bool, location: String,
                                 calendar: Calendar = .current) -> EventSuggestion? {
        guard let begin = parseDate(start, calendar: calendar) else { return nil }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let allDay = isAllDay || !begin.hasTime
        let finish = parseDate(end, calendar: calendar)
        var endDate: Date
        if allDay {
            endDate = finish?.date ?? begin.date
            // Das Modell nennt bei ganztägigen Terminen meist den letzten Tag, nicht den Folgetag.
            endDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))!
        } else if let finish, finish.hasTime {
            endDate = finish.date
        } else {
            endDate = begin.date.addingTimeInterval(3600)
        }
        return EventSuggestion(title: title.isEmpty ? String(localized: "New Event") : title,
                               start: begin.date, end: endDate, isAllDay: allDay,
                               location: location).normalized(calendar: calendar)
    }

    private static func parseDate(_ text: String, calendar: Calendar) -> (date: Date, hasTime: Bool)? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let formats: [(String, Bool)] = [
            ("yyyy-MM-dd'T'HH:mm:ss", true), ("yyyy-MM-dd'T'HH:mm", true), ("yyyy-MM-dd HH:mm", true),
            ("yyyy-MM-dd", false),
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        for (format, hasTime) in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return (date, hasTime) }
        }
        return nil
    }
}

// MARK: - Erkennung ohne Sprachmodell

/// Fallback für Geräte ohne Apple Intelligence: Datumsangaben per `NSDataDetector` im
/// erkannten Text suchen, der Titel kommt aus der Zeile drumherum.
nonisolated public enum EventSuggestionDetector {
    public static func suggestions(in text: String, now: Date = .now, calendar: Calendar = .current,
                                   limit: Int = 10) -> [EventSuggestion] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var result: [EventSuggestion] = []
        var seen = Set<Date>()

        for (index, line) in lines.enumerated() where !line.isEmpty {
            let range = NSRange(line.startIndex..., in: line)
            for match in detector.matches(in: line, range: range) {
                guard let date = match.date, let matchRange = Range(match.range, in: line) else { continue }
                // Vergangenes ist auf einem Screenshot fast immer ein Sendedatum, kein Termin.
                guard date >= calendar.startOfDay(for: now), seen.insert(date).inserted else { continue }
                let matched = String(line[matchRange])
                let hasTime = containsTime(matched)
                let title = title(around: matchRange, in: line, lines: lines, index: index)
                let end: Date
                if hasTime {
                    end = match.duration > 0 ? date.addingTimeInterval(match.duration) : date.addingTimeInterval(3600)
                } else {
                    end = date
                }
                result.append(EventSuggestion(title: title, start: date, end: end, isAllDay: !hasTime)
                    .normalized(calendar: calendar))
                if result.count == limit { return result }
            }
        }
        return result
    }

    /// Uhrzeit im erkannten Datum: „15:30“, „15.30 Uhr“, „3 pm“, „15 Uhr“.
    static func containsTime(_ text: String) -> Bool {
        let patterns = [#"\d{1,2}[:.]\d{2}(?!\d)(?![.]\d)"#, #"\d{1,2}\s*(am|pm|a\.m\.|p\.m\.|uhr)\b"#]
        return patterns.contains { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    /// Rest der Zeile ohne das Datum; ist der zu kurz, die Zeile davor.
    private static func title(around range: Range<String.Index>, in line: String, lines: [String], index: Int) -> String {
        var rest = line
        rest.removeSubrange(range)
        let cleaned = clean(rest)
        if cleaned.count >= 3 { return cleaned }
        if let previous = lines[..<index].last(where: { !clean($0).isEmpty }) { return clean(previous) }
        return String(localized: "New Event")
    }

    /// Satzzeichen und Füllwörter rund um das herausgeschnittene Datum entfernen
    /// („Party on“ → „Party“, „Elternabend am“ → „Elternabend“).
    static func clean(_ text: String) -> String {
        let separators = CharacterSet(charactersIn: " \t,;:-–—|·•()[]")
        let fillers = #"(?i)^(?:on|at|from|until|am|um|ab|vom|bis|ist|is)\s+|\s+(?:on|at|from|until|am|um|ab|vom|bis|ist|is)$"#
        var result = text.trimmingCharacters(in: separators)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        while true {
            let trimmed = result.replacingOccurrences(of: fillers, with: "", options: .regularExpression)
                .trimmingCharacters(in: separators)
            if trimmed == result { return result }
            result = trimmed
        }
    }
}
