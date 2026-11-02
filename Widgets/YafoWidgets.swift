import SwiftUI
import WidgetKit
import YafoKit

@main
struct YafoWidgetBundle: WidgetBundle {
    var body: some Widget {
        UpcomingWidget()
        NextEventWidget()
    }
}

// MARK: - Daten

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let items: [WidgetSnapshot.Item]
}

/// Liest den Schnappschuss, den die App in die App Group schreibt. Neue Einträge gibt es,
/// wenn ein Termin endet, und um Mitternacht; die App lädt die Timeline nach jedem Sync neu.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, items: SampleData.items)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let items = WidgetSnapshot.load().upcoming(from: .now)
        completion(SnapshotEntry(date: .now, items: context.isPreview && items.isEmpty ? SampleData.items : items))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let now = Date.now
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        var dates = Set(snapshot.items.map(\.end).filter { $0 > now && $0 < midnight })
        dates.insert(now)
        dates.insert(midnight)
        let entries = dates.sorted().prefix(40).map { SnapshotEntry(date: $0, items: snapshot.upcoming(from: $0)) }
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}

// MARK: - Nächste Termine (Startbildschirm)

struct UpcomingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "de.yafo.upcoming", provider: SnapshotProvider()) { entry in
            UpcomingView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Upcoming")
        .description("Today's and the next events as colored cards.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct UpcomingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    /// Platz in Zeilen: eine Karte zählt 2, eine Tagesüberschrift 1.
    private var rowBudget: Int {
        family == .systemLarge ? 18 : 8
    }

    /// So viele Termine, wie samt Tagesüberschriften in das Widget passen.
    private var fittingItems: [WidgetSnapshot.Item] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: entry.date)
        var used = 0
        var lastDay: Date?
        var result: [WidgetSnapshot.Item] = []
        for item in entry.items {
            let day = max(calendar.startOfDay(for: item.start), today)
            let cost = 2 + (day == lastDay ? 0 : 1)
            guard used + cost <= rowBudget else { break }
            used += cost
            lastDay = day
            result.append(item)
        }
        return result
    }

    var body: some View {
        let items = fittingItems
        if items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No upcoming events")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 5) {
                ForEach(groups(items), id: \.day) { group in
                    Text(dayTitle(group.day))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Calendar.current.isDateInToday(group.day) ? Color.accentColor : .secondary)
                    ForEach(group.items) { item in
                        if family == .systemSmall {
                            CompactCard(item: item)
                        } else {
                            EventCard(item: item)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func groups(_ items: [WidgetSnapshot.Item]) -> [(day: Date, items: [WidgetSnapshot.Item])] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: entry.date)
        var result: [(day: Date, items: [WidgetSnapshot.Item])] = []
        for item in items {
            // Laufende mehrtägige Termine zählen zu heute.
            let day = max(calendar.startOfDay(for: item.start), today)
            if result.last?.day == day {
                result[result.count - 1].items.append(item)
            } else {
                result.append((day, [item]))
            }
        }
        return result
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInTomorrow(day) { return String(localized: "Tomorrow") }
        return family == .systemSmall
            ? day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            : day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// Wie die Karten der Tagesliste in der App: Zeit, Farbstreifen, Titel, Kalender bzw. Ort.
struct EventCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: WidgetSnapshot.Item

    var body: some View {
        let color = Color(hex: item.colorHex)
        HStack(spacing: 8) {
            Group {
                if item.isBirthday {
                    Image(systemName: "birthday.cake.fill")
                        .foregroundStyle(color)
                } else if item.isAllDay {
                    Text("All day")
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(item.start.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11, weight: .semibold))
                        Text(item.end.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 42, alignment: .trailing)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            HStack(spacing: -4) {
                ForEach(item.initials.prefix(3), id: \.self) { initials in
                    Text(initials)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                        .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5))
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.trailing, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(colorScheme == .dark ? 0.25 : 0.13)))
    }

    private var subtitle: String {
        if item.isBirthday, let age = item.age { return String(localized: "Turns \(age)") }
        return item.location ?? item.calendarName
    }
}

/// Klein: nur Farbstreifen, Titel und Zeit.
struct CompactCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: WidgetSnapshot.Item

    var body: some View {
        let color = Color(hex: item.colorHex)
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.isBirthday ? "🎂 \(item.title)" : item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(item.timeText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(colorScheme == .dark ? 0.25 : 0.13)))
    }
}

// MARK: - Nächster Termin (Sperrbildschirm)

struct NextEventWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "de.yafo.next", provider: SnapshotProvider()) { entry in
            NextEventView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Next Event")
        .description("Your next event on the Lock Screen.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct NextEventView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let next = entry.items.first {
            if family == .accessoryInline {
                Text("\(next.timeText) \(next.title)")
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(dayText(next.start) + " · " + next.timeText)
                        .font(.caption2.weight(.semibold))
                        .widgetAccentable()
                    Text(next.title)
                        .font(.headline)
                        .lineLimit(1)
                    if let second = entry.items.dropFirst().first {
                        Text("\(second.timeText) \(second.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("No upcoming events")
        }
    }

    private func dayText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) || date < entry.date { return String(localized: "Today") }
        if calendar.isDateInTomorrow(date) { return String(localized: "Tomorrow") }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }
}

// MARK: - Hilfen

extension WidgetSnapshot.Item {
    var timeText: String {
        if isBirthday, let age { return String(localized: "Turns \(age)") }
        if isAllDay { return String(localized: "All day") }
        return start.formatted(date: .omitted, time: .shortened)
    }
}

extension Color {
    /// `#RRGGBB` wie in der App.
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x8E8E93
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

enum SampleData {
    static var items: [WidgetSnapshot.Item] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func at(_ day: Int, _ hour: Int) -> Date {
            calendar.date(byAdding: .hour, value: day * 24 + hour, to: today)!
        }
        return [
            .init(id: "1", title: String(localized: "Dentist"), start: at(0, 9), end: at(0, 10), isAllDay: false,
                  colorHex: "#27AE60", calendarName: "", location: nil, isBirthday: false, age: nil, initials: []),
            .init(id: "2", title: String(localized: "Zoo"), start: at(0, 14), end: at(0, 17), isAllDay: false,
                  colorHex: "#2F80ED", calendarName: "", location: nil, isBirthday: false, age: nil, initials: ["A", "M"]),
            .init(id: "3", title: String(localized: "Swimming"), start: at(1, 16), end: at(1, 17), isAllDay: false,
                  colorHex: "#9B51E0", calendarName: "", location: nil, isBirthday: false, age: nil, initials: ["M"]),
        ]
    }
}
