import Foundation
import NaturalLanguage

/// Ein erkannter, noch nicht gespeicherter Termin, z. B. aus einem Screenshot.
/// Bei ganztägigen Terminen ist `end` der Beginn des letzten Tags (wie im Editor angezeigt).
nonisolated public struct EventProposal: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?

    public init(title: String, start: Date, end: Date, isAllDay: Bool, location: String? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
    }

    /// Aus den Textfeldern des Sprachmodells: Datum „yyyy-MM-dd“, Uhrzeit „HH:mm“.
    /// Ohne Uhrzeit ganztägig, ohne Ende eine Stunde. `nil`, wenn das Datum nicht lesbar ist.
    public init?(title: String, date: String, startTime: String?, endDate: String?, endTime: String?,
                 location: String?, calendar: Calendar = .current) {
        guard let day = Self.day(from: date, calendar: calendar) else { return nil }
        let lastDay = endDate.flatMap { Self.day(from: $0, calendar: calendar) }.map { max($0, day) } ?? day
        let trimmedLocation = location?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.location = trimmedLocation?.isEmpty == false ? trimmedLocation : nil
        if let startTime = Self.time(from: startTime), let start = Self.date(day, startTime, calendar) {
            isAllDay = false
            self.start = start
            let end = Self.time(from: endTime).flatMap { Self.date(lastDay, $0, calendar) }
            self.end = end.map { $0 > start ? $0 : start.addingTimeInterval(3600) } ?? start.addingTimeInterval(3600)
        } else {
            isAllDay = true
            start = day
            end = lastDay
        }
    }

    /// Werte zum Speichern; ganztägig mit exklusivem Ende wie in `Event`.
    public func draftTimes(calendar: Calendar = .current) -> (start: Date, end: Date) {
        guard isAllDay else { return (start, max(end, start)) }
        let first = calendar.startOfDay(for: start)
        let last = max(calendar.startOfDay(for: end), first)
        return (first, calendar.date(byAdding: .day, value: 1, to: last)!)
    }

    private static func day(from text: String, calendar: Calendar) -> Date? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == parts[2] else { return nil }
        return date
    }

    private static func time(from text: String?) -> (hour: Int, minute: Int)? {
        guard let text else { return nil }
        let parts = text.trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == ":" || $0 == "." }).compactMap { Int($0) }
        guard let hour = parts.first, (0...23).contains(hour) else { return nil }
        let minute = parts.count > 1 ? parts[1] : 0
        return (0...59).contains(minute) ? (hour, minute) : nil
    }

    private static func date(_ day: Date, _ time: (hour: Int, minute: Int), _ calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day)
    }
}

/// Termine in erkanntem Text finden, ohne Sprachmodell: Datumsangaben per `NSDataDetector`,
/// Titel per Wortarten (`NLTagger`) aus der Datumszeile oder den Zeilen davor, Ort aus einer
/// Adresse in der Nähe oder „in der Aula“ hinter dem Datum. Fallback ohne Apple Intelligence.
nonisolated public enum TextEventExtractor {
    public static func proposals(in lines: [String], now: Date = .now,
                                 calendar: Calendar = .current) -> [EventProposal] {
        let lines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue
                                                 | NSTextCheckingResult.CheckingType.address.rawValue) else { return [] }
        var dates: [(line: Int, match: NSTextCheckingResult)] = []
        var addresses: [(line: Int, text: String)] = []
        for (index, line) in lines.enumerated() {
            let ns = line as NSString
            for match in detector.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                let text = ns.substring(with: match.range)
                if match.resultType == .date, match.date != nil, !isTimeOnly(text) {
                    dates.append((index, match))
                } else if match.resultType == .address {
                    addresses.append((index, text))
                }
            }
        }
        let today = calendar.startOfDay(for: now)
        var result: [EventProposal] = []
        for (index, match) in dates {
            guard let date = match.date else { continue }
            let line = lines[index] as NSString
            let hasTime = containsTime(line.substring(with: match.range))
            let start = hasTime ? date : calendar.startOfDay(for: date)
            guard start >= today else { continue }
            let end: Date
            if hasTime {
                end = start.addingTimeInterval(match.duration > 0 ? match.duration : 3600)
            } else {
                end = match.duration >= 86_400
                    ? calendar.startOfDay(for: date.addingTimeInterval(match.duration)) : start
            }
            let before = line.substring(to: match.range.location)
            let after = line.substring(from: NSMaxRange(match.range))
            let title = title(before: before, after: after, above: Array(lines[..<index]))
            let location = addresses.first { abs($0.line - index) <= 3 }?.text
                ?? place(in: sentence(after: after, below: Array(lines[(index + 1)...])))
            let proposal = EventProposal(title: title, start: start, end: end, isAllDay: !hasTime, location: location)
            if !result.contains(where: { $0.start == proposal.start && $0.title == proposal.title }) {
                result.append(proposal)
            }
        }
        return result
    }

    // MARK: Titel

    /// Erst der Text vor dem Datum, dann ein kurzes Etikett dahinter, dann die Zeilen darüber
    /// (ohne Anreden wie „Liebe Eltern,“ und ohne fertige Sätze davor).
    private static func title(before: String, after: String, above: [String]) -> String {
        let ownSentence = before.components(separatedBy: CharacterSet(charactersIn: ".!?")).last ?? before
        if let phrase = phrase(in: ownSentence) { return phrase }
        let label = after.components(separatedBy: CharacterSet(charactersIn: ".!?")).first ?? ""
        if let phrase = phrase(in: label), words(of: label).first?.tag == .noun { return phrase }
        for line in above.reversed().prefix(3) {
            if line.hasSuffix(".") || line.hasSuffix("!") || line.hasSuffix("?") { break }
            if line.hasSuffix(",") { continue }
            if let phrase = phrase(in: line) { return phrase }
        }
        return clean(ownSentence)
    }

    /// Kurzes Etikett ohne Verb („Kindergeburtstag von Mia“) ganz, sonst das erste Substantiv
    /// samt direkt folgenden („parent meeting“). `nil`, wenn kein Substantiv vorkommt.
    private static func phrase(in text: String) -> String? {
        let tagged = words(of: text)
        guard let first = tagged.firstIndex(where: { $0.tag == .noun }) else { return nil }
        if tagged.count <= 5, !tagged.contains(where: { $0.tag == .verb }) {
            let label = clean(text)
            if !label.isEmpty { return label }
        }
        let run = tagged[first...].prefix { $0.tag == .noun }.map(\.word).joined(separator: " ")
        return run.prefix(1).uppercased() + run.dropFirst()
    }

    private static func words(of text: String) -> [(word: String, tag: NLTag?)] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var result: [(String, NLTag?)] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            result.append((String(text[range]), tag))
            return true
        }
        return result
    }

    /// Füllwörter, Artikel und Satzzeichen an den Rändern entfernen („Elternabend am“ → „Elternabend“).
    private static func clean(_ text: String) -> String {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let trailing: Set<String> = ["am", "um", "ab", "von", "bis", "vom", "on", "at", "from", "to", "-", "–", "—", ",", ":"]
        let leading = trailing.union(["der", "die", "das", "the", "a", "an"])
        while let last = words.last, trailing.contains(last.lowercased()) { words.removeLast() }
        while let first = words.first, leading.contains(first.lowercased()) { words.removeFirst() }
        return words.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces).subtracting(["(", ")", "\"", "„", "“"]))
    }

    // MARK: Ort

    /// Rest des Satzes hinter dem Datum, auch über Zeilenumbrüche („… um 19:30“ / „Uhr in der Aula statt.“).
    private static func sentence(after: String, below: [String]) -> String {
        var text = after
        for line in below.prefix(2) {
            if text.contains(where: { ".!?".contains($0) }) { break }
            text += " " + line
        }
        return text.components(separatedBy: CharacterSet(charactersIn: ".!?")).first ?? text
    }

    /// „in der Aula“, „im Gemeindehaus“, „at the Town Hall“ → der Ort.
    private static func place(in text: String) -> String? {
        let pattern = #"\b(?:in der|in dem|im|in|at the|at)\s+(\p{Lu}[\p{L}-]+(?:\s+\p{Lu}[\p{L}-]+)*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    // MARK: Datum

    private static func isTimeOnly(_ text: String) -> Bool {
        text.range(of: #"^\s*\d{1,2}[:.]\d{2}\s*(Uhr|h)?\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func containsTime(_ text: String) -> Bool {
        text.range(of: #"\d{1,2}[:.]\d{2}(?![.\d])|\d{1,2}\s*(Uhr|am|pm|h)\b"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }
}
