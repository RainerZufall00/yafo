import Foundation

/// Region für gesetzliche Feiertage: deutsche Bundesländer, Österreich, Schweiz (allgemein).
nonisolated public enum HolidayRegion: String, CaseIterable, Sendable, Identifiable {
    case bw = "DE-BW", by = "DE-BY", be = "DE-BE", bb = "DE-BB", hb = "DE-HB", hh = "DE-HH"
    case he = "DE-HE", mv = "DE-MV", ni = "DE-NI", nw = "DE-NW", rp = "DE-RP", sl = "DE-SL"
    case sn = "DE-SN", st = "DE-ST", sh = "DE-SH", th = "DE-TH"
    case at = "AT"
    case ch = "CH"

    public var id: String { rawValue }

    /// Schlüssel der Quelle, gleich für alle Kalender, die sie abonnieren.
    public var sourceKey: String { "feiertage:\(rawValue)" }

    /// Kürzel für die Beschriftung, z. B. „BY“.
    public var shortName: String { rawValue.split(separator: "-").last.map(String.init) ?? rawValue }

    public var germanName: String {
        switch self {
        case .bw: "Baden-Württemberg"
        case .by: "Bayern"
        case .be: "Berlin"
        case .bb: "Brandenburg"
        case .hb: "Bremen"
        case .hh: "Hamburg"
        case .he: "Hessen"
        case .mv: "Mecklenburg-Vorpommern"
        case .ni: "Niedersachsen"
        case .nw: "Nordrhein-Westfalen"
        case .rp: "Rheinland-Pfalz"
        case .sl: "Saarland"
        case .sn: "Sachsen"
        case .st: "Sachsen-Anhalt"
        case .sh: "Schleswig-Holstein"
        case .th: "Thüringen"
        case .at: "Österreich"
        case .ch: "Schweiz"
        }
    }

    public var isGerman: Bool { rawValue.hasPrefix("DE-") }
}

nonisolated public struct Holiday: Equatable, Sendable {
    /// 0 Uhr des Feiertags (lokal).
    public let date: Date
    public let germanName: String
    public let englishName: String

    public func name(languageCode: String? = Locale.current.language.languageCode?.identifier) -> String {
        languageCode == "de" ? germanName : englishName
    }
}

/// Gesetzliche Feiertage, berechnet nach Ostertermin und Feiertagsgesetzen. Damit sind sie
/// ohne Netz und für jedes Jahr da.
nonisolated public enum Holidays {
    public static func holidays(in region: HolidayRegion, year: Int, calendar: Calendar = .current) -> [Holiday] {
        let easter = easterSunday(year: year, calendar: calendar)
        func fixed(_ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day))!
        }
        func easterOffset(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: easter)!
        }
        var list: [(Date, String, String)] = []
        func add(_ date: Date, _ german: String, _ english: String, if condition: Bool = true) {
            if condition { list.append((date, german, english)) }
        }
        let r = region

        switch region {
        case .at:
            add(fixed(1, 1), "Neujahr", "New Year's Day")
            add(fixed(1, 6), "Heilige Drei Könige", "Epiphany")
            add(easterOffset(1), "Ostermontag", "Easter Monday")
            add(fixed(5, 1), "Staatsfeiertag", "Labour Day")
            add(easterOffset(39), "Christi Himmelfahrt", "Ascension Day")
            add(easterOffset(50), "Pfingstmontag", "Whit Monday")
            add(easterOffset(60), "Fronleichnam", "Corpus Christi")
            add(fixed(8, 15), "Mariä Himmelfahrt", "Assumption Day")
            add(fixed(10, 26), "Nationalfeiertag", "National Day")
            add(fixed(11, 1), "Allerheiligen", "All Saints' Day")
            add(fixed(12, 8), "Mariä Empfängnis", "Immaculate Conception")
            add(fixed(12, 25), "Christtag", "Christmas Day")
            add(fixed(12, 26), "Stefanitag", "St. Stephen's Day")

        case .ch:
            // In (fast) allen Kantonen; kantonale Feiertage kommen mit den OpenHolidays-Daten.
            add(fixed(1, 1), "Neujahr", "New Year's Day")
            add(fixed(1, 2), "Berchtoldstag", "Berchtold's Day")
            add(easterOffset(-2), "Karfreitag", "Good Friday")
            add(easterOffset(1), "Ostermontag", "Easter Monday")
            add(easterOffset(39), "Auffahrt", "Ascension Day")
            add(easterOffset(50), "Pfingstmontag", "Whit Monday")
            add(fixed(8, 1), "Bundesfeiertag", "Swiss National Day")
            add(fixed(12, 25), "Weihnachtstag", "Christmas Day")
            add(fixed(12, 26), "Stephanstag", "St. Stephen's Day")

        default:
            add(fixed(1, 1), "Neujahr", "New Year's Day")
            add(fixed(1, 6), "Heilige Drei Könige", "Epiphany", if: [.bw, .by, .st].contains(r))
            add(fixed(3, 8), "Internationaler Frauentag", "International Women's Day",
                if: (r == .be && year >= 2019) || (r == .mv && year >= 2023))
            add(easterOffset(-2), "Karfreitag", "Good Friday")
            add(easter, "Ostersonntag", "Easter Sunday", if: r == .bb)
            add(easterOffset(1), "Ostermontag", "Easter Monday")
            add(fixed(5, 1), "Tag der Arbeit", "Labour Day")
            add(easterOffset(39), "Christi Himmelfahrt", "Ascension Day")
            add(easterOffset(49), "Pfingstsonntag", "Whit Sunday", if: r == .bb)
            add(easterOffset(50), "Pfingstmontag", "Whit Monday")
            add(easterOffset(60), "Fronleichnam", "Corpus Christi", if: [.bw, .by, .he, .nw, .rp, .sl].contains(r))
            add(fixed(8, 15), "Mariä Himmelfahrt", "Assumption Day", if: [.sl, .by].contains(r))
            add(fixed(9, 20), "Weltkindertag", "World Children's Day", if: r == .th && year >= 2019)
            add(fixed(10, 3), "Tag der Deutschen Einheit", "German Unity Day")
            add(fixed(10, 31), "Reformationstag", "Reformation Day",
                if: [.bb, .mv, .sn, .st, .th].contains(r) || ([.hb, .hh, .ni, .sh].contains(r) && year >= 2018))
            add(fixed(11, 1), "Allerheiligen", "All Saints' Day", if: [.bw, .by, .nw, .rp, .sl].contains(r))
            add(repentanceDay(year: year, calendar: calendar), "Buß- und Bettag", "Day of Repentance", if: r == .sn)
            add(fixed(12, 25), "1. Weihnachtstag", "Christmas Day")
            add(fixed(12, 26), "2. Weihnachtstag", "Boxing Day")
        }
        return list.sorted { $0.0 < $1.0 }.map { Holiday(date: $0.0, germanName: $0.1, englishName: $0.2) }
    }

    /// Feiertage aller `regions` im Intervall, je Tag; gleiche Namen erscheinen nur einmal.
    public static func holidays(in regions: Set<HolidayRegion>, overlapping interval: DateInterval,
                                calendar: Calendar = .current) -> [Date: [Holiday]] {
        byDay(regions: regions, interval: interval, calendar: calendar) { holidays(in: $0, year: $1, calendar: calendar) }
    }

    /// Besondere Tage aller `regions` im Intervall, je Tag; gleiche Namen erscheinen nur einmal.
    /// Gesetzliche Feiertage einer der Regionen fallen weg (z. B. Ostersonntag in Brandenburg).
    public static func observances(in regions: Set<HolidayRegion>, overlapping interval: DateInterval,
                                   calendar: Calendar = .current) -> [Date: [Holiday]] {
        let publicDays = holidays(in: regions, overlapping: interval, calendar: calendar)
        return byDay(regions: regions, interval: interval, calendar: calendar) {
            observances(in: $0, year: $1, calendar: calendar)
        }.compactMapValues { list in
            let filtered = list.filter { day in
                !(publicDays[day.date] ?? []).contains { $0.germanName == day.germanName }
            }
            return filtered.isEmpty ? nil : filtered
        }
    }

    private static func byDay(regions: Set<HolidayRegion>, interval: DateInterval, calendar: Calendar,
                              list: (HolidayRegion, Int) -> [Holiday]) -> [Date: [Holiday]] {
        let firstYear = calendar.component(.year, from: interval.start)
        let lastYear = calendar.component(.year, from: interval.end)
        var result: [Date: [Holiday]] = [:]
        for region in regions.sorted(by: { $0.rawValue < $1.rawValue }) {
            for year in firstYear...lastYear {
                for holiday in list(region, year)
                where interval.contains(holiday.date) && holiday.date < interval.end {
                    if !(result[holiday.date] ?? []).contains(where: { $0.germanName == holiday.germanName }) {
                        result[holiday.date, default: []].append(holiday)
                    }
                }
            }
        }
        return result
    }

    /// Besondere Tage ohne Feiertagsstatus: Advent, Brauchtum, Gedenk- und Aktionstage. Gesetzliche Feiertage
    /// der Region sind ausgenommen (Ostersonntag nur dort, wo er keiner ist). Für die Anzeige als Hinweis im Kalender.
    public static func observances(in region: HolidayRegion, year: Int, calendar: Calendar = .current) -> [Holiday] {
        let easter = easterSunday(year: year, calendar: calendar)
        func fixed(_ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day))!
        }
        func easterOffset(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: easter)!
        }
        /// `n`-ter Sonntag im Monat.
        func sunday(_ n: Int, of month: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, weekday: 1, weekdayOrdinal: n))!
        }
        let fourthAdvent = fourthAdventSunday(year: year, calendar: calendar)
        func beforeFourthAdvent(weeks: Int) -> Date {
            calendar.date(byAdding: .day, value: -7 * weeks, to: fourthAdvent)!
        }
        let germany = region.isGerman
        var list: [(Date, String, String)] = []
        func add(_ date: Date, _ german: String, _ english: String, if condition: Bool = true) {
            if condition { list.append((date, german, english)) }
        }

        add(fixed(2, 14), "Valentinstag", "Valentine's Day")
        add(easterOffset(-52), "Weiberfastnacht", "Women's Carnival Day", if: germany)
        add(easterOffset(-48), "Rosenmontag", "Rose Monday", if: germany)
        add(easterOffset(-47), region == .ch ? "Fasnachtsdienstag" : "Faschingsdienstag", "Shrove Tuesday")
        add(easterOffset(-46), "Aschermittwoch", "Ash Wednesday")
        add(easterOffset(-7), "Palmsonntag", "Palm Sunday")
        add(easterOffset(-3), "Gründonnerstag", "Maundy Thursday")
        add(easterOffset(-1), "Karsamstag", "Holy Saturday")
        add(easter, "Ostersonntag", "Easter Sunday")
        add(sunday(2, of: 5), "Muttertag", "Mother's Day")
        add(easterOffset(39), "Vatertag", "Father's Day", if: germany)
        add(sunday(2, of: 6), "Vatertag", "Father's Day", if: region == .at)
        add(sunday(1, of: 6), "Vatertag", "Father's Day", if: region == .ch)
        add(easterOffset(49), "Pfingstsonntag", "Whit Sunday")
        add(sunday(1, of: 10), "Erntedankfest", "Harvest Festival", if: germany)
        add(fixed(10, 31), "Reformationstag", "Reformation Day", if: germany)
        add(fixed(10, 31), "Halloween", "Halloween")
        add(fixed(11, 1), "Allerheiligen", "All Saints' Day", if: germany)
        add(fixed(11, 2), "Allerseelen", "All Souls' Day", if: region != .ch)
        add(fixed(11, 11), "Sankt Martin", "St. Martin's Day")
        add(beforeFourthAdvent(weeks: 5), "Volkstrauertag", "Day of Mourning", if: germany)
        add(repentanceDay(year: year, calendar: calendar), "Buß- und Bettag", "Day of Repentance", if: germany)
        add(beforeFourthAdvent(weeks: 4), "Totensonntag", "Sunday of the Dead", if: germany)
        add(beforeFourthAdvent(weeks: 3), "1. Advent", "1st Sunday of Advent")
        add(beforeFourthAdvent(weeks: 2), "2. Advent", "2nd Sunday of Advent")
        add(beforeFourthAdvent(weeks: 1), "3. Advent", "3rd Sunday of Advent")
        add(fourthAdvent, "4. Advent", "4th Sunday of Advent")
        add(fixed(12, 6), "Nikolaus", "St. Nicholas Day")
        add(fixed(12, 24), "Heiligabend", "Christmas Eve")
        add(fixed(12, 31), "Silvester", "New Year's Eve")

        let publicNames = Set(holidays(in: region, year: year, calendar: calendar).map(\.germanName))
        return list.filter { !publicNames.contains($0.1) }
            .sorted { $0.0 < $1.0 }.map { Holiday(date: $0.0, germanName: $0.1, englishName: $0.2) }
    }

    /// 4. Advent: der letzte Sonntag vor dem 25. Dezember (frühestens am 18., spätestens am 24.).
    static func fourthAdventSunday(year: Int, calendar: Calendar) -> Date {
        let christmas = calendar.date(from: DateComponents(year: year, month: 12, day: 25))!
        let weekday = calendar.component(.weekday, from: christmas)  // 1 = Sonntag
        return calendar.date(byAdding: .day, value: -(weekday == 1 ? 7 : weekday - 1), to: christmas)!
    }

    /// Ostersonntag nach der Gaußschen Osterformel (gregorianisch, anonymer Algorithmus).
    public static func easterSunday(year: Int, calendar: Calendar = .current) -> Date {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Buß- und Bettag: der Mittwoch vor dem 23. November.
    static func repentanceDay(year: Int, calendar: Calendar) -> Date {
        let nov23 = calendar.date(from: DateComponents(year: year, month: 11, day: 23))!
        let weekday = calendar.component(.weekday, from: nov23)  // 1 = Sonntag, 4 = Mittwoch
        let back = (weekday - 4 + 7) % 7
        return calendar.date(byAdding: .day, value: -(back == 0 ? 7 : back), to: nov23)!
    }
}
