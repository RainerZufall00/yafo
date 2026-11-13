import Foundation

/// Erkennt Termine, die eigentlich Geburtstage sind („Geburtstag Oma“, „Max's birthday“, „🎂 Lena (1990)“),
/// etwa nach dem Import eines Familienkalenders. Feiern und Partys zählen nicht: Das sind echte Termine.
nonisolated public enum BirthdayDetector {
    public struct Guess: Equatable, Sendable {
        public var name: String
        public var birthYear: Int?

        public init(name: String, birthYear: Int? = nil) {
            self.name = name
            self.birthYear = birthYear
        }
    }

    /// Name und, falls im Titel, Geburtsjahr; `nil`, wenn der Titel nicht nach Geburtstag aussieht
    /// oder kein Name übrig bleibt.
    public static func guess(title: String, now: Date = .now, calendar: Calendar = .current) -> Guess? {
        let lower = title.lowercased()
        guard keywords.contains(where: { lower.contains($0) }) || lower.contains(geb),
              !exclusions.contains(where: { lower.contains($0) }) else { return nil }

        var name = title
        var birthYear: Int?
        let currentYear = calendar.component(.year, from: now)
        // Jahr in Klammern, nach Stern oder allein: „(1985)“, „*1956“, „1990“.
        if let match = name.firstMatch(of: yearPattern), let year = Int(match.output.1), (1900...currentYear).contains(year) {
            birthYear = year
            name.removeSubrange(match.range)
        }
        for pattern in removals {
            name = name.replacing(pattern, with: " ")
        }
        name = name
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—:,;|/.!()").union(.whitespaces))
        guard !name.isEmpty, name.contains(where: \.isLetter) else { return nil }
        return Guess(name: name, birthYear: birthYear)
    }

    private static let keywords = ["geburtstag", "birthday", "bday", "b-day", "🎂"]
    /// „Geb.“ bzw. „Geb“ als eigenes Wort, nicht in „Gebäude“.
    private static var geb: Regex<AnyRegexOutput> { pattern(#"\bgeb\b\.?"#) }

    private static let exclusions = ["feier", "party", "kindergeburtstag", "geschenk", "gift", "einladung",
                                     "invitation", "celebration", "brunch", "essen", "dinner"]

    private static var yearPattern: Regex<(Substring, Substring)> { /[(*]?\s*\b((?:19|20)\d\d)\b\s*\)?/ }

    private static var removals: [Regex<AnyRegexOutput>] {
        [
            #"hat\s+geburtstag"#,
            #"\d{1,3}\s*\.\s*(?=geburtstag)"#,
            #"geburtstag[es]*(\s+(von|vom|der|des))?"#,
            #"\bgeb\b\.?(\s+(von|vom))?"#,
            #"['’]s\s+(birthday|bday|b-day)"#,
            #"\b(happy\s+)?(birthday|bday|b-day)(\s+of)?\b"#,
            #"\(\s*\d{1,3}\s*\)"#,
            #"\bwird\s+\d{1,3}\b"#,
            #"\bturns\s+\d{1,3}\b"#,
            #"[🎂🎉🎈🥳🎁🍰]"#,
        ].map(pattern)
    }

    private static func pattern(_ string: String) -> Regex<AnyRegexOutput> {
        // Feste Muster: ein Fehler wäre ein Programmierfehler.
        try! Regex(string).ignoresCase()
    }
}
