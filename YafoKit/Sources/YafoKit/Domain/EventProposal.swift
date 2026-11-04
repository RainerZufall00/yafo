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
    /// Koordinaten „Breite,Länge“ wie in `Event.geo`, sobald der Ort in Apple Maps gefunden ist.
    public var geo: String?
    /// RRULE ohne „RRULE:“, `nil` für einen einzelnen Termin.
    public var recurrenceRule: String?

    /// Wiederholung, wie sie in Texten vorkommt („jeden Dienstag“, „alle zwei Wochen“, „monthly“).
    public enum Repeat: String, Sendable, CaseIterable {
        case daily, weekly, biweekly, monthly, yearly
    }

    public init(title: String, start: Date, end: Date, isAllDay: Bool, location: String? = nil,
                recurrenceRule: String? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.recurrenceRule = recurrenceRule
    }

    /// Aus den Textfeldern des Sprachmodells: Datum „yyyy-MM-dd“, Uhrzeit „HH:mm“.
    /// Ohne Uhrzeit ganztägig, ohne Ende eine Stunde. `nil`, wenn das Datum nicht lesbar ist.
    /// Wiederholung: `repeats` wie `Repeat`, Wochentage als „MO“ … „SU“, letzter Tag „yyyy-MM-dd“.
    public init?(title: String, date: String, startTime: String?, endDate: String?, endTime: String?,
                 location: String?, repeats: String? = nil, repeatWeekdays: [String] = [],
                 repeatUntil: String? = nil, calendar: Calendar = .current) {
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
        if let repeats = repeats.flatMap({ Repeat(rawValue: $0.lowercased()) }) {
            let codes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
            let weekdays = Set(repeatWeekdays.compactMap { code in
                codes.firstIndex(of: String(code.uppercased().prefix(2))).map { $0 + 1 }
            })
            applyRepeat(repeats, weekdays: weekdays,
                        until: repeatUntil.flatMap { Self.day(from: $0, calendar: calendar) }, calendar: calendar)
        }
    }

    /// Setzt die Regel. Liegt der Beginn nicht auf einem der Wochentage, rückt der Termin auf den
    /// nächsten passenden Tag, damit das erste Vorkommen zur Regel passt. Ein Ende vor dem Beginn
    /// wird ignoriert.
    public mutating func applyRepeat(_ repeats: Repeat, weekdays: Set<Int> = [], until: Date? = nil,
                                     calendar: Calendar = .current) {
        let weekly = repeats == .weekly || repeats == .biweekly
        if weekly, !weekdays.isEmpty {
            var shift = 0
            while shift < 7,
                  let day = calendar.date(byAdding: .day, value: shift, to: start),
                  !weekdays.contains(calendar.component(.weekday, from: day)) {
                shift += 1
            }
            if shift > 0, shift < 7 {
                start = calendar.date(byAdding: .day, value: shift, to: start)!
                end = calendar.date(byAdding: .day, value: shift, to: end)!
            }
        }
        var rule: RecurrenceRule
        switch repeats {
        case .daily: rule = RecurrenceRule(frequency: .daily)
        case .weekly, .biweekly: rule = RecurrenceRule(frequency: .weekly, interval: repeats == .weekly ? 1 : 2)
        case .monthly: rule = RecurrenceRule(frequency: .monthly)
        case .yearly: rule = RecurrenceRule(frequency: .yearly)
        }
        // Wie im Editor: nur der Wochentag des Beginns steht nicht extra in der Regel.
        if weekly, !weekdays.isEmpty, weekdays != [calendar.component(.weekday, from: start)] {
            rule.byDay = weekdays.sorted().map { RecurrenceRule.Weekday($0) }
        }
        if let until, calendar.startOfDay(for: until) >= calendar.startOfDay(for: start) {
            // Der ganze letzte Tag zählt noch mit.
            rule.until = calendar.date(byAdding: .second, value: 86_399, to: calendar.startOfDay(for: until))
        }
        recurrenceRule = rule.rruleString
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
                if match.resultType == .date, match.date != nil {
                    dates.append((index, match))
                } else if match.resultType == .address {
                    addresses.append((index, fullAddress(match.range, in: lines, at: index)))
                }
            }
        }
        let today = calendar.startOfDay(for: now)
        var result: [EventProposal] = []
        func add(_ proposal: EventProposal) {
            if !result.contains(where: { $0.start == proposal.start && $0.title == proposal.title }) {
                result.append(proposal)
            }
        }
        func pieces(_ index: Int) -> [DatePiece] {
            let ns = lines[index] as NSString
            return dates.filter { $0.line == index }.compactMap { item in
                item.match.date.map { DatePiece(text: ns.substring(with: item.match.range),
                                                before: ns.substring(to: item.match.range.location),
                                                date: $0, duration: item.match.duration) }
            }
        }
        var consumed = Set<Int>()
        for (index, line) in lines.enumerated() where !consumed.contains(index) {
            let matches = dates.filter { $0.line == index }.map(\.match)
            let ns = line as NSString
            let nearbyAddress = addresses.first { abs($0.line - index) <= 3 }?.text
            // Eine Zeile mit „jeden Dienstag“ o. Ä. ist eine Serie, ihre Datumsangaben gehören dazu.
            // Steht die Uhrzeit allein in der nächsten Zeile (Umbruch der Texterkennung), zählt sie mit.
            var seriesPieces = pieces(index)
            if !seriesPieces.contains(where: { containsTime($0.text) }), index + 1 < lines.count,
               RepeatCue(in: lines[index + 1]) == nil {
                let next = pieces(index + 1)
                if !next.isEmpty, next.allSatisfy({ !hasExplicitDay($0.text) }),
                   next.contains(where: { containsTime($0.text) }) {
                    seriesPieces += next
                    consumed.insert(index + 1)
                }
            }
            if let cue = RepeatCue(in: line),
               var proposal = recurring(cue, pieces: seriesPieces, today: today, calendar: calendar) {
                let first = min(cue.range.location, matches.map(\.range.location).min() ?? .max)
                let last = max(NSMaxRange(cue.range), matches.map { NSMaxRange($0.range) }.max() ?? 0)
                proposal.title = title(before: ns.substring(to: first), after: ns.substring(from: last),
                                       above: Array(lines[..<index]))
                proposal.location = nearbyAddress
                    ?? place(in: sentence(after: ns.substring(from: last), below: Array(lines[(index + 1)...])))
                add(proposal)
                continue
            }
            consumed.remove(index + 1)
            for match in matches {
                guard let date = match.date, !isTimeOnly(ns.substring(with: match.range)) else { continue }
                let hasTime = containsTime(ns.substring(with: match.range))
                let start = hasTime ? date : calendar.startOfDay(for: date)
                guard start >= today else { continue }
                let end: Date
                if hasTime {
                    end = start.addingTimeInterval(match.duration > 0 ? match.duration : 3600)
                } else {
                    end = match.duration >= 86_400
                        ? calendar.startOfDay(for: date.addingTimeInterval(match.duration)) : start
                }
                let before = ns.substring(to: match.range.location)
                let after = ns.substring(from: NSMaxRange(match.range))
                let title = title(before: before, after: after, above: Array(lines[..<index]))
                let location = nearbyAddress
                    ?? place(in: sentence(after: after, below: Array(lines[(index + 1)...])))
                add(EventProposal(title: title, start: start, end: end, isAllDay: !hasTime, location: location))
            }
        }
        return result
    }

    // MARK: Serien

    /// Hinweis auf eine Wiederholung in einer Zeile, mit den genannten Wochentagen.
    struct RepeatCue {
        var repeats: EventProposal.Repeat
        var weekdays: Set<Int>
        /// Erste Fundstelle, für den Titel davor.
        var range: NSRange

        private static let weekdayNames: [(String, Int)] = [
            ("sonntag", 1), ("montag", 2), ("dienstag", 3), ("mittwoch", 4), ("donnerstag", 5),
            ("freitag", 6), ("samstag", 7), ("sonnabend", 7),
            ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4), ("thursday", 5),
            ("friday", 6), ("saturday", 7),
        ]
        private static let weekdayPattern = weekdayNames.map(\.0).joined(separator: "|")

        /// Reihenfolge zählt: „alle zwei Wochen“ vor „Woche“.
        private static let frequencies: [(EventProposal.Repeat, String)] = [
            (.biweekly, #"\balle\s+(?:zwei|2)\s+wochen\b|\b(?:14|vierzehn)[- ]?tägig\b|\bzweiwöchentlich\b|\bevery\s+(?:other|second|two|2)\s+weeks?\b|\bbi-?weekly\b|\bfortnightly\b"#),
            (.daily, #"\btäglich\b|\bjeden\s+tag\b|\bevery\s+day\b|\bdaily\b"#),
            (.weekly, #"\bwöchentlich\b|\bjede\s+woche\b|\bevery\s+week\b|\bweekly\b"#),
            (.monthly, #"\bmonatlich\b|\bjeden\s+monat\b|\bevery\s+month\b|\bmonthly\b"#),
            (.yearly, #"\bjährlich\b|\bjedes\s+jahr\b|\bevery\s+year\b|\byearly\b|\bannually\b"#),
        ]

        init?(in line: String) {
            let whole = NSRange(location: 0, length: (line as NSString).length)
            func find(_ pattern: String) -> [NSTextCheckingResult] {
                (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))?.matches(in: line, range: whole) ?? []
            }
            let frequency = Self.frequencies.lazy.compactMap { repeats, pattern in
                find(pattern).first.map { (repeats, $0.range) }
            }.first
            // „jeden Dienstag“, „every Monday“ oder „dienstags“, „Mondays“.
            let everyDay = find(#"\b(?:jeden|jede|jeder|immer|every|each)\s+(?:"# + Self.weekdayPattern + #")\b"#).first
            let pluralDay = find(#"\b(?:"# + Self.weekdayPattern + #")s\b"#).first
            guard frequency != nil || everyDay != nil || pluralDay != nil else { return nil }

            var weekdays = Set<Int>()
            for match in find(#"\b("# + Self.weekdayPattern + #")s?\b"#) {
                let name = (line as NSString).substring(with: match.range(at: 1)).lowercased()
                if let day = Self.weekdayNames.first(where: { $0.0 == name })?.1 { weekdays.insert(day) }
            }
            let ranges = [frequency?.1, everyDay?.range, pluralDay?.range].compactMap { $0 }
            range = ranges.min { $0.location < $1.location }!
            repeats = frequency?.0 ?? .weekly
            self.weekdays = repeats == .weekly || repeats == .biweekly ? weekdays : []
        }
    }

    /// Erster Termin der Serie: ab einem genannten Datum (sonst heute) der nächste passende Wochentag,
    /// Uhrzeit und Dauer aus der Zeile, Ende der Serie aus „bis …“. `nil`, wenn der Tag offen bleibt
    /// (z. B. „monatlich“ ohne Datum).
    /// Eine erkannte Datumsangabe mit dem Text davor in ihrer Zeile.
    struct DatePiece {
        var text: String
        var before: String
        var date: Date
        var duration: TimeInterval
    }

    private static func recurring(_ cue: RepeatCue, pieces: [DatePiece],
                                  today: Date, calendar: Calendar) -> EventProposal? {
        var firstDay: Date?
        var until: Date?
        var time: (start: Date, duration: TimeInterval)?
        for piece in pieces {
            let (text, before, date) = (piece.text, piece.before, piece.date)
            if text.range(of: #"^(bis|until|till|through)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                until = date.addingTimeInterval(piece.duration)
                continue
            }
            if before.range(of: #"\b(bis(\s+zum)?|until|till|through)\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                until = date
                continue
            }
            if time == nil, containsTime(text) { time = (date, piece.duration) }
            if firstDay == nil, hasExplicitDay(text) { firstDay = calendar.startOfDay(for: date) }
        }
        if cue.weekdays.isEmpty, cue.repeats != .daily, firstDay == nil { return nil }
        var day = firstDay ?? today
        if !cue.weekdays.isEmpty {
            for _ in 0..<7 where !cue.weekdays.contains(calendar.component(.weekday, from: day)) {
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
        }
        if let until, until < day { return nil }
        var proposal: EventProposal
        if let time {
            let parts = calendar.dateComponents([.hour, .minute], from: time.start)
            let start = calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day)!
            proposal = EventProposal(title: "", start: start,
                                     end: start.addingTimeInterval(time.duration > 0 ? time.duration : 3600),
                                     isAllDay: false)
        } else {
            proposal = EventProposal(title: "", start: day, end: day, isAllDay: true)
        }
        proposal.applyRepeat(cue.repeats, weekdays: cue.weekdays, until: until, calendar: calendar)
        return proposal
    }

    /// Steht ein Kalendertag drin („10.11.2026“, „12. Nov“, „March 3“) und nicht nur ein Wochentag?
    private static func hasExplicitDay(_ text: String) -> Bool {
        let months = "jan|feb|mär|mar|apr|mai|may|jun|jul|aug|sep|okt|oct|nov|dez|dec"
        let pattern = #"\d{1,2}\.\s?\d{1,2}\.?|\d{4}-\d{2}-\d{2}|\d{1,2}\.?\s*(?:"# + months
            + #")|(?:"# + months + #")\p{L}*\s+\d{1,2}\b"#
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: Titel

    /// Erst der Text vor dem Datum, dann ein kurzes Etikett dahinter, dann die Zeilen darüber
    /// (ohne Anreden wie „Liebe Eltern,“ und ohne fertige Sätze davor).
    private static func title(before: String, after: String, above: [String]) -> String {
        let ownSentence = before.components(separatedBy: CharacterSet(charactersIn: ".!?")).last ?? before
        if let phrase = phrase(in: ownSentence) { return phrase }
        // Kurzes Etikett, das der Tagger nicht als Substantiv kennt („Chor“, „Kita“).
        let own = clean(ownSentence)
        if let first = own.first, first.isUppercase, own.split(separator: " ").count <= 3 { return own }
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
        let trailing: Set<String> = ["am", "um", "ab", "immer", "von", "bis", "vom", "on", "at", "from", "to", "-", "–", "—", ",", ":"]
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
            text += "\n" + line
        }
        return text.components(separatedBy: CharacterSet(charactersIn: ".!?")).first ?? text
    }

    /// „in der Aula“, „im Gemeindehaus“, „at the Town Hall“ → der Ort. Der Name endet am Zeilenende.
    private static func place(in text: String) -> String? {
        let pattern = #"\b(?:in der|in dem|im|in|at the|at)\s+(\p{Lu}[\p{L}-]+(?:\h+\p{Lu}[\p{L}-]+)*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    // MARK: Datum

    /// Nur Uhrzeit oder Zeitspanne ohne Tag: „11:58“, „16:00-17:00 Uhr“, „15–18 Uhr“.
    private static func isTimeOnly(_ text: String) -> Bool {
        let time = #"\d{1,2}(?:[:.]\d{2})?\s*(?:Uhr|h)?"#
        return text.range(of: #"^\s*"# + time + #"\s*(?:[-–]\s*"# + time + #")?\s*$"#,
                          options: [.regularExpression, .caseInsensitive]) != nil
            && text.range(of: #"[:.]\d{2}|Uhr|\dh"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: Adresse

    /// Die Datenerkennung liefert oft nur „Leopoldstraße 50“; Postleitzahl und Ort dahinter oder
    /// in der nächsten Zeile gehören dazu, damit Apple Maps die richtige Stadt findet.
    private static func fullAddress(_ range: NSRange, in lines: [String], at index: Int) -> String {
        let ns = lines[index] as NSString
        var text = ns.substring(with: range)
        let rest = ns.substring(from: NSMaxRange(range))
        if let postal = rest.range(of: #"^\s*,?\s*\d{4,5}(?:\s+\p{L}[\p{L} .-]*)?\s*$"#, options: .regularExpression) {
            text += ", " + rest[postal].trimmingCharacters(in: CharacterSet(charactersIn: ", "))
            // Ort in der nächsten Zeile („80802“ / „München“).
            if rest.range(of: #"\d\s*$"#, options: .regularExpression) != nil, index + 1 < lines.count,
               lines[index + 1].range(of: #"^\p{Lu}[\p{L} .-]{1,30}$"#, options: .regularExpression) != nil {
                text += " " + lines[index + 1]
            }
        }
        return text
    }

    private static func containsTime(_ text: String) -> Bool {
        text.range(of: #"\d{1,2}[:.]\d{2}(?![.\d])|\d{1,2}\s*(Uhr|am|pm|h)\b"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }
}
