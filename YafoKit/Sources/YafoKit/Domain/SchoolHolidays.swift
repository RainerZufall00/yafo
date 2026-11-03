import Foundation

/// Bundesland bzw. Kanton für Schulferien, mit den Codes der OpenHolidays API.
nonisolated public struct SchoolHolidayRegion: Hashable, Identifiable, Sendable {
    public enum Country: String, CaseIterable, Sendable {
        case de = "DE", at = "AT", ch = "CH"
    }

    public let code: String
    public let name: String

    public var id: String { code }
    public var country: Country { Country(rawValue: String(code.prefix(2))) ?? .de }
    public var shortName: String { code.split(separator: "-").last.map(String.init) ?? code }
    public var sourceKey: String { "ferien:\(code)" }

    public static func region(code: String?) -> SchoolHolidayRegion? {
        all.first { $0.code == code }
    }

    public static func regions(in country: Country) -> [SchoolHolidayRegion] {
        all.filter { $0.country == country }
    }

    /// Gleiche Region wie bei den Feiertagen, soweit es sie gibt (für die Vorauswahl).
    public static func matching(_ holidayRegion: HolidayRegion) -> SchoolHolidayRegion? {
        region(code: holidayRegion.rawValue)
    }

    public static let all: [SchoolHolidayRegion] = [
        ("DE-BW", "Baden-Württemberg"), ("DE-BY", "Bayern"), ("DE-BE", "Berlin"), ("DE-BB", "Brandenburg"),
        ("DE-HB", "Bremen"), ("DE-HH", "Hamburg"), ("DE-HE", "Hessen"), ("DE-MV", "Mecklenburg-Vorpommern"),
        ("DE-NI", "Niedersachsen"), ("DE-NW", "Nordrhein-Westfalen"), ("DE-RP", "Rheinland-Pfalz"),
        ("DE-SL", "Saarland"), ("DE-SN", "Sachsen"), ("DE-ST", "Sachsen-Anhalt"), ("DE-SH", "Schleswig-Holstein"),
        ("DE-TH", "Thüringen"),
        ("AT-BL", "Burgenland"), ("AT-KÄ", "Kärnten"), ("AT-NÖ", "Niederösterreich"), ("AT-OÖ", "Oberösterreich"),
        ("AT-SB", "Salzburg"), ("AT-SM", "Steiermark"), ("AT-TI", "Tirol"), ("AT-VA", "Vorarlberg"),
        ("AT-WI", "Wien"),
        ("CH-AG", "Aargau"), ("CH-AI", "Appenzell Innerrhoden"), ("CH-AR", "Appenzell Ausserrhoden"),
        ("CH-BE", "Bern"), ("CH-BL", "Basel-Landschaft"), ("CH-BS", "Basel-Stadt"), ("CH-FR", "Freiburg"),
        ("CH-GE", "Genf"), ("CH-GL", "Glarus"), ("CH-GR", "Graubünden"), ("CH-JU", "Jura"), ("CH-LU", "Luzern"),
        ("CH-NE", "Neuenburg"), ("CH-NW", "Nidwalden"), ("CH-OW", "Obwalden"), ("CH-SG", "St. Gallen"),
        ("CH-SH", "Schaffhausen"), ("CH-SO", "Solothurn"), ("CH-SZ", "Schwyz"), ("CH-TG", "Thurgau"),
        ("CH-TI", "Tessin"), ("CH-UR", "Uri"), ("CH-VD", "Waadt"), ("CH-VS", "Wallis"), ("CH-ZG", "Zug"),
        ("CH-ZH", "Zürich"),
    ].map { SchoolHolidayRegion(code: $0.0, name: $0.1) }
}

/// Schulferien aus der OpenHolidays API (Daten unter ODbL-1.0).
nonisolated public enum SchoolHolidays {
    /// Quelle; später ein eigener Spiegel, den eine GitHub Action wöchentlich aktualisiert.
    public static let baseURL = URL(string: "https://openholidaysapi.org")!
    /// Höchstens einmal pro Woche neu laden.
    public static let refreshInterval: TimeInterval = 7 * 24 * 3600

    /// Die API liefert höchstens drei Jahre am Stück: Vorjahr bis nächstes Jahr.
    public static func url(for region: SchoolHolidayRegion, around now: Date = .now,
                           calendar: Calendar = .current) -> URL {
        let year = calendar.component(.year, from: now)
        var components = URLComponents(url: baseURL.appending(path: "SchoolHolidays"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "countryIsoCode", value: region.country.rawValue),
            URLQueryItem(name: "subdivisionCode", value: region.code),
            URLQueryItem(name: "validFrom", value: "\(year - 1)-01-01"),
            URLQueryItem(name: "validTo", value: "\(year + 1)-12-31"),
        ]
        return components.url!
    }

    private struct APIHoliday: Decodable {
        struct Name: Decodable {
            let language: String
            let text: String
        }
        let id: String
        let startDate: String
        let endDate: String
        let name: [Name]
    }

    /// Ferien als ganztägige Einträge; das Enddatum der API ist inklusiv.
    public static func parse(_ data: Data, languageCode: String? = Locale.current.language.languageCode?.identifier,
                             calendar: Calendar = .current) throws -> [SubscriptionEntry] {
        let language = (languageCode ?? "en").uppercased()
        return try JSONDecoder().decode([APIHoliday].self, from: data).compactMap { holiday in
            guard let start = day(holiday.startDate, calendar: calendar),
                  let last = day(holiday.endDate, calendar: calendar) else { return nil }
            let title = holiday.name.first { $0.language == language }?.text
                ?? holiday.name.first { $0.language == "EN" }?.text
                ?? holiday.name.first?.text ?? ""
            return SubscriptionEntry(uid: holiday.id, title: title, start: start,
                                     end: calendar.date(byAdding: .day, value: 1, to: last)!, isAllDay: true)
        }
    }

    private static func day(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
