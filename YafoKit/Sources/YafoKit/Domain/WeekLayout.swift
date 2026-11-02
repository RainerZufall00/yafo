import Foundation

/// Verteilt die Termine einer Woche auf Spuren (Zeilen) im Monatsraster.
/// Mehrtägige und ganztägige Termine kommen zuerst und laufen als Band über ihre Tage;
/// passt nicht alles in `maxLanes`, zeigt die letzte Spur „+n“ für die betroffenen Tage.
nonisolated public struct WeekLayout<ID: Hashable> {
    public struct Entry {
        public let id: ID
        public let start: Date
        public let end: Date
        public let isAllDay: Bool

        public init(id: ID, start: Date, end: Date, isAllDay: Bool) {
            self.id = id
            self.start = start
            self.end = end
            self.isAllDay = isAllDay
        }
    }

    public struct Item: Identifiable {
        public let id: ID
        public let firstColumn: Int
        public let lastColumn: Int
        public let lane: Int
        /// Beginnt vor bzw. endet nach dieser Woche.
        public let continuesBefore: Bool
        public let continuesAfter: Bool
        /// Ganztägig oder über mehrere Tage: als volles Band darstellen.
        public let isSpanning: Bool
    }

    private struct Placed {
        let entry: Entry
        let first: Int, last: Int
        let before: Bool, after: Bool
        let spanning: Bool
    }

    public let items: [Item]
    /// Pro Spalte: wie viele Termine nicht angezeigt werden.
    public let hiddenCounts: [Int]

    public init(weekStart: Date, entries: [Entry], maxLanes: Int, calendar: Calendar = .current) {
        let weekStart = calendar.startOfDay(for: weekStart)

        let placed: [Placed] = entries.compactMap { entry in
            let columns = calendar.days(from: entry.start, to: entry.end).map {
                calendar.dateComponents([.day], from: weekStart, to: $0).day ?? 0
            }
            guard let minColumn = columns.min(), let maxColumn = columns.max(),
                  maxColumn >= 0, minColumn <= 6 else { return nil }
            return Placed(entry: entry, first: max(minColumn, 0), last: min(maxColumn, 6),
                          before: minColumn < 0, after: maxColumn > 6,
                          spanning: entry.isAllDay || columns.count > 1)
        }
        .sorted { a, b in
            if a.spanning != b.spanning { return a.spanning }
            if a.entry.start != b.entry.start { return a.entry.start < b.entry.start }
            return (a.last - a.first) > (b.last - b.first)
        }

        // Jeder Termin in die niedrigste Spur, die an all seinen Tagen frei ist.
        var occupied: [[Bool]] = []
        var lanes: [Int] = []
        for item in placed {
            let columns = item.first...item.last
            var lane = 0
            while lane < occupied.count, columns.contains(where: { occupied[lane][$0] }) {
                lane += 1
            }
            if lane == occupied.count {
                occupied.append(Array(repeating: false, count: 7))
            }
            for column in columns { occupied[lane][column] = true }
            lanes.append(lane)
        }

        var counts = Array(repeating: 0, count: 7)
        for item in placed {
            for column in item.first...item.last { counts[column] += 1 }
        }
        let overflowing = Set((0..<7).filter { counts[$0] > maxLanes })

        var items: [Item] = []
        var hidden = Array(repeating: 0, count: 7)
        for (item, lane) in zip(placed, lanes) {
            let columns = item.first...item.last
            let isVisible = lane < maxLanes - 1
                || lane == maxLanes - 1 && !columns.contains(where: overflowing.contains)
            if isVisible {
                items.append(Item(id: item.entry.id, firstColumn: item.first, lastColumn: item.last, lane: lane,
                                  continuesBefore: item.before, continuesAfter: item.after,
                                  isSpanning: item.spanning))
            } else {
                for column in columns { hidden[column] += 1 }
            }
        }
        self.items = items
        hiddenCounts = hidden
    }
}
