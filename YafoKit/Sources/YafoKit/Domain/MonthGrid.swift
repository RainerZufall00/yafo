import Foundation

/// Raster einer Monatsansicht: ganze Wochen, beginnend mit dem Wochenstart des Kalenders.
nonisolated public struct MonthGrid: Sendable {
    public struct Day: Sendable, Hashable, Identifiable {
        public let date: Date
        public let isInMonth: Bool
        public var id: Date { date }
    }

    public let month: Date
    public let days: [Day]

    public var weeks: [[Day]] {
        stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    public init(containing date: Date, calendar: Calendar = .current) {
        let month = calendar.dateInterval(of: .month, for: date)!
        self.month = month.start
        let leading = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leading, to: month.start)!
        let daysInMonth = calendar.range(of: .day, in: .month, for: month.start)!.count
        let weekCount = Int((Double(leading + daysInMonth) / 7).rounded(.up))

        days = (0..<(weekCount * 7)).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: gridStart)!
            return Day(date: day, isInMonth: calendar.isDate(day, equalTo: month.start, toGranularity: .month))
        }
    }

    /// Kurze Wochentagsnamen in der Reihenfolge des Rasters.
    public static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }
}

nonisolated public extension Calendar {
    /// Die Tage (jeweils 0 Uhr), die ein Termin berührt. Das Ende ist exklusiv.
    func days(from start: Date, to end: Date) -> [Date] {
        let stop = max(start, end)
        let first = startOfDay(for: start)
        var last = startOfDay(for: stop)
        // Endet ein Termin genau um 0 Uhr (z. B. ganztägig, Ende exklusiv), zählt der Endtag nicht mit.
        if last > first, last == stop {
            last = date(byAdding: .day, value: -1, to: last)!
        }
        var result: [Date] = []
        var day = first
        while day <= last {
            result.append(day)
            day = date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }
}
