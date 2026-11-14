import Foundation

/// Verteilt die Termine mit Uhrzeit eines Tages auf die Zeitleiste der Tagesansicht:
/// Was sich überschneidet, steht nebeneinander in Spalten; jede Gruppe sich überschneidender
/// Termine teilt die Breite unter sich auf. Termine über Mitternacht werden auf den Tag gekürzt.
nonisolated public struct DayLayout<ID: Hashable> {
    public struct Entry {
        public let id: ID
        public let start: Date
        public let end: Date

        public init(id: ID, start: Date, end: Date) {
            self.id = id
            self.start = start
            self.end = end
        }
    }

    public struct Item: Identifiable {
        public let id: ID
        /// Uhrzeit in Minuten ab 0 Uhr (Wanduhr, auch an Tagen mit Zeitumstellung), 0…1440.
        public let startMinute: Double
        public let endMinute: Double
        public let column: Int
        /// Spalten der Gruppe, zu der der Termin gehört.
        public let columnCount: Int
        /// Beginnt vor bzw. endet nach diesem Tag.
        public let continuesBefore: Bool
        public let continuesAfter: Bool
    }

    private struct Span {
        let entry: Entry
        let start: Double
        let end: Double
        /// Für die Überschneidung: mindestens `minimumMinutes` lang, so hoch wird der Termin gezeichnet.
        let layoutEnd: Double
        let before: Bool
        let after: Bool
    }

    public let items: [Item]

    /// `minimumMinutes`: kürzeste dargestellte Dauer, damit kurze Termine lesbar bleiben
    /// und sich ihre Kästen nicht überdecken.
    public init(day: Date, entries: [Entry], minimumMinutes: Double = 0, calendar: Calendar = .current) {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        func minute(_ date: Date) -> Double {
            let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
            return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + Double(parts.second ?? 0) / 60
        }

        let spans: [Span] = entries.compactMap { entry -> Span? in
            // Was genau um 0 Uhr endet, gehört nicht mehr zu diesem Tag; ein Termin ohne Dauer
            // um 0 Uhr schon.
            guard entry.start < dayEnd, entry.start >= dayStart || entry.end > dayStart else { return nil }
            let before = entry.start < dayStart
            let after = entry.end > dayEnd
            let start = before ? 0 : minute(entry.start)
            let end = entry.end >= dayEnd ? 1440 : max(minute(entry.end), start)
            return Span(entry: entry, start: start, end: end, layoutEnd: max(end, start + minimumMinutes),
                        before: before, after: after)
        }
        .sorted { ($0.start, -$0.end) < ($1.start, -$1.end) }

        var items: [Item] = []
        var group: [(span: Span, column: Int)] = []
        var columnEnds: [Double] = []
        var groupEnd = -Double.infinity

        func closeGroup() {
            for (span, column) in group {
                items.append(Item(id: span.entry.id, startMinute: span.start, endMinute: span.end, column: column,
                                  columnCount: columnEnds.count, continuesBefore: span.before,
                                  continuesAfter: span.after))
            }
            group = []
            columnEnds = []
        }

        for span in spans {
            if !group.isEmpty, span.start >= groupEnd { closeGroup() }
            if let free = columnEnds.firstIndex(where: { $0 <= span.start }) {
                columnEnds[free] = span.layoutEnd
                group.append((span, free))
            } else {
                columnEnds.append(span.layoutEnd)
                group.append((span, columnEnds.count - 1))
            }
            groupEnd = group.count == 1 ? span.layoutEnd : max(groupEnd, span.layoutEnd)
        }
        closeGroup()
        self.items = items
    }
}
