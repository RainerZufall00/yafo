import CoreData
import Foundation

extension Repository {
    /// Sichtbare Termine von heute bis `days` Tage voraus, Ganztägiges je Tag zuerst.
    public func widgetSnapshot(now: Date = .now, days: Int = 14, limit: Int = 40) -> WidgetSnapshot {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let interval = DateInterval(start: start, end: calendar.date(byAdding: .day, value: days, to: start)!)
        let items = occurrences(overlapping: interval)
            .filter { occurrence in
                occurrence.end > now && occurrence.event.calendar.map(isVisible) ?? false
            }
            .sorted {
                let lhsDay = calendar.startOfDay(for: max($0.start, start))
                let rhsDay = calendar.startOfDay(for: max($1.start, start))
                return (lhsDay, $0.isAllDay ? 0 : 1, $0.start) < (rhsDay, $1.isAllDay ? 0 : 1, $1.start)
            }
            .prefix(limit)
            .map { occurrence in
                let event = occurrence.event
                return WidgetSnapshot.Item(
                    id: "\(event.id?.uuidString ?? "")-\(Int(occurrence.originalStart.timeIntervalSince1970))",
                    title: occurrence.title, start: occurrence.start, end: occurrence.end,
                    isAllDay: occurrence.isAllDay,
                    colorHex: event.calendar.map(color(of:)) ?? CalendarColors.personalDefault,
                    calendarName: event.calendar?.name ?? "", location: occurrence.location,
                    isBirthday: event.isBirthday, age: occurrence.age,
                    initials: (event.participants ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
                        .compactMap(\.initials))
            }
        return WidgetSnapshot(generatedAt: now, items: Array(items))
    }
}
