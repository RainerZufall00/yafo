import Foundation

/// Ein Termin aus einer abonnierten Quelle, so wie er im lokalen Cache liegt: Serien sind
/// bereits in einzelne Vorkommen aufgelöst.
nonisolated public struct SubscriptionEntry: Equatable, Sendable {
    public var uid: String
    public var title: String
    public var start: Date
    /// Exklusives Ende; bei Ganztägigem 0 Uhr des Folgetags.
    public var end: Date
    public var isAllDay: Bool
    public var location: String?

    public init(uid: String, title: String, start: Date, end: Date, isAllDay: Bool, location: String? = nil) {
        self.uid = uid
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
    }
}

nonisolated public enum SubscriptionFeed {
    /// Zeitraum, für den Abos zwischengespeichert werden: ein Jahr zurück, zwei voraus.
    public static func window(around now: Date = .now, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.date(byAdding: .year, value: -1, to: calendar.startOfDay(for: now))!
        return DateInterval(start: start, end: calendar.date(byAdding: .year, value: 3, to: start)!)
    }

    /// Löst Serien im Zeitraum auf, lässt EXDATEs weg und ersetzt geänderte Vorkommen.
    public static func entries(from events: [ICSEvent], in window: DateInterval,
                               calendar: Calendar = .current) -> [SubscriptionEntry] {
        let overrides = Dictionary(
            events.compactMap { event in event.recurrenceID.map { (OverrideKey(uid: event.uid, start: $0), event) } },
            uniquingKeysWith: { _, last in last })
        var result: [SubscriptionEntry] = []

        for event in events where event.recurrenceID == nil && !event.isCancelled {
            let title = event.summary.isEmpty ? String(localized: "Untitled") : event.summary
            let duration = event.end.timeIntervalSince(event.start)
            guard let rule = event.recurrenceRule.flatMap(RecurrenceRule.init(rrule:)) else {
                if event.start < window.end && event.end > window.start {
                    result.append(SubscriptionEntry(uid: event.uid, title: title, start: event.start, end: event.end,
                                                    isAllDay: event.isAllDay, location: event.location))
                }
                continue
            }
            var seriesCalendar = Calendar(identifier: .gregorian)
            seriesCalendar.timeZone = event.timeZone.flatMap(TimeZone.init(identifier:)) ?? calendar.timeZone
            let excluded = Set(event.excludedDates)
            let from = window.start.addingTimeInterval(-max(duration, 0))
            for start in rule.startDates(seriesStart: event.start, from: from, to: window.end, calendar: seriesCalendar)
            where !excluded.contains(start) {
                let uid = "\(event.uid)#\(Int(start.timeIntervalSince1970))"
                if let override = overrides[OverrideKey(uid: event.uid, start: start)] {
                    guard !override.isCancelled else { continue }
                    result.append(SubscriptionEntry(uid: uid, title: override.summary.isEmpty ? title : override.summary,
                                                    start: override.start, end: override.end,
                                                    isAllDay: override.isAllDay, location: override.location))
                } else {
                    result.append(SubscriptionEntry(uid: uid, title: title, start: start,
                                                    end: start.addingTimeInterval(duration),
                                                    isAllDay: event.isAllDay, location: event.location))
                }
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    private struct OverrideKey: Hashable {
        let uid: String
        let start: Date
    }

    /// Schlüssel einer ICS-Quelle: `webcal` wird zu `https`, Host klein, Leerraum weg. So
    /// zählt dieselbe Adresse in zwei Kalendern nur einmal.
    public static func sourceKey(forICS address: String) -> String? {
        normalizedURL(address).map { "ics:\($0.absoluteString)" }
    }

    public static func normalizedURL(_ address: String) -> URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("webcal://") { text = "https://" + text.dropFirst("webcal://".count) }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host, !host.isEmpty else { return nil }
        components.scheme = scheme
        components.host = host.lowercased()
        return components.url
    }
}
