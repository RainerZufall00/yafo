import CoreData
import SwiftUI
import YafoKit

/// Ansicht im Kalender-Tab: Woche, Monat oder Jahr. Wird gemerkt.
enum CalendarMode: String, CaseIterable, Identifiable {
    case week, month, year

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    var systemImage: String {
        switch self {
        case .week: "rectangle.split.1x2"
        case .month: "calendar"
        case .year: "square.grid.3x3"
        }
    }
}

/// Eine Woche als sieben Zeilen über die ganze Höhe: links Wochentag und Datum, rechts die Termine
/// als Kacheln nebeneinander (Titel oben, Uhrzeit und Dauer unten). Lesbarer als ein Stundenraster
/// mit sieben schmalen Spalten auf dem iPhone.
struct WeekPageView: View {
    @Environment(AppModel.self) private var model
    let days: [Date]
    @Binding var selectedDay: Date
    let style: CalendarStyle
    var onOpenDay: ((Date) -> Void)?

    private let interval: DateInterval
    @FetchRequest private var events: FetchedResults<Event>
    @FetchRequest private var subscribed: FetchedResults<SubscribedEvent>
    @FetchRequest private var todos: FetchedResults<TodoItem>
    @State private var dropTarget: Date?

    init(weekStart: Date, selectedDay: Binding<Date>, style: CalendarStyle, onOpenDay: ((Date) -> Void)? = nil) {
        let cal = Calendar.current
        days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
        _selectedDay = selectedDay
        self.style = style
        self.onOpenDay = onOpenDay
        interval = DateInterval(start: weekStart, end: cal.date(byAdding: .day, value: 7, to: weekStart)!)
        _events = FetchRequest(sortDescriptors: [SortDescriptor(\.start)],
                               predicate: Repository.overlapPredicate(interval))
        _subscribed = FetchRequest(sortDescriptors: [SortDescriptor(\.start)],
                                   predicate: Repository.cachePredicate(sourceKeys: style.subscriptionKeys,
                                                                        interval: interval))
        _todos = FetchRequest(sortDescriptors: [SortDescriptor(\.dueDate)], predicate: Repository.duePredicate(interval))
    }

    var body: some View {
        let occurrences = events.filter(style.includes).flatMap { $0.occurrences(overlapping: interval) }
        let entries = style.entries(occurrences: occurrences, subscribed: subscribed,
                                    external: model.external.items(overlapping: interval), todos: todos,
                                    specialDaysIn: interval)
            .sorted(by: CalendarEntry.listOrder)
        let holidays = style.holidays(in: interval)
        let schoolHolidays = style.schoolHolidays(in: subscribed)
        VStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let end = Calendar.current.date(byAdding: .day, value: 1, to: day)!
                WeekDayRow(day: day,
                           isSelected: day == selectedDay,
                           isDropTarget: dropTarget == day,
                           holidays: (holidays[day] ?? []).map { $0.name() },
                           schoolHolidays: schoolHolidays[day] ?? [],
                           entries: entries.filter { $0.start < end && $0.end > day },
                           onOpen: {
                               selectedDay = day
                               onOpenDay?(day)
                           })
                    .frame(maxHeight: .infinity)
                    .calendarDrop(entries: entries, hovered: $dropTarget) { _ in day }
                Divider()
            }
        }
    }
}

private struct WeekDayRow: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.calendarActions) private var actions
    let day: Date
    let isSelected: Bool
    let isDropTarget: Bool
    let holidays: [String]
    let schoolHolidays: [String]
    let entries: [CalendarEntry]
    let onOpen: () -> Void

    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var isWeekend: Bool { Calendar.current.isDateInWeekend(day) }
    /// Schmalste Kachel; daraus folgt, wie viele nebeneinander passen. Alle Kacheln sind gleich breit.
    private var minTileWidth: CGFloat { sizeClass == .regular ? 120 : 64 }
    private let spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: 0) {
            dateColumn
                .allowsHitTesting(false)
            GeometryReader { geometry in
                let tiles = tiles
                let available = geometry.size.width - 6
                let capacity = max(1, Int((available + spacing) / (minTileWidth + spacing)))
                let width = (available - spacing * CGFloat(capacity - 1)) / CGFloat(capacity)
                // Was nicht passt, zeigt die letzte Kachel als „+n“.
                let shown = tiles.count > capacity ? capacity - 1 : tiles.count
                HStack(spacing: spacing) {
                    ForEach(tiles.prefix(shown)) { tile in
                        tileView(tile).frame(width: width)
                    }
                    if tiles.count > shown {
                        Button(action: onOpen) {
                            Text("+\(tiles.count - shown)")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 1.2)
                                }
                        }
                        .buttonStyle(.plain)
                        .frame(width: width)
                        .accessibilityLabel(Text("\(tiles.count - shown) more"))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
        }
        // Tippen und langes Drücken auf freie Fläche; Kacheln darüber haben eigene Gesten
        // (Antippen öffnet, lange drücken hebt zum Verschieben an).
        .background {
            ZStack {
                background
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpen)
                    .onLongPressGesture(minimumDuration: 0.4) { actions.createEvent(day) }
            }
        }
        .overlay(alignment: .leading) {
            if isToday {
                Rectangle().fill(Color.accentColor).frame(width: 4)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Show Day", onOpen)
        .accessibilityAction(named: "New Event") { actions.createEvent(day) }
    }

    @ViewBuilder
    private var background: some View {
        if isToday {
            Color.accentColor.opacity(0.1)
        } else if isSelected && sizeClass == .regular {
            Color.accentColor.opacity(0.08)
        } else if !schoolHolidays.isEmpty {
            Color(hex: CalendarColors.schoolHoliday).opacity(0.3)
        } else if isWeekend {
            Color.secondary.opacity(0.05)
        }
    }

    private var dateColumn: some View {
        let accent = isToday ? Color.accentColor : holidays.isEmpty ? Color.primary : Color(hex: CalendarColors.publicHoliday)
        return VStack(spacing: 0) {
            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                .font(.subheadline)
                .foregroundStyle(isToday ? accent : holidays.isEmpty ? Color.secondary : accent)
            Text(day.formatted(.dateTime.day()))
                .font(.title2.weight(isToday ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(isToday ? Color.white : accent)
                .frame(minWidth: 36, minHeight: 36)
                .background {
                    if isToday { Circle().fill(Color.accentColor) }
                }
            if !schoolHolidays.isEmpty {
                Image(systemName: "backpack.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
                    .accessibilityLabel(Text("School holidays: \(schoolHolidays.joined(separator: ", "))"))
            }
        }
        .frame(width: 52)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Kacheln

    private struct Tile: Identifiable {
        let id: String
        let title: String
        let color: Color
        var icon: String?
        var time: String?
        var detail: String?
        var isMuted = false
        var entry: CalendarEntry?
    }

    private var tiles: [Tile] {
        var result: [Tile] = []
        for entry in entries {
            result.append(Tile(id: entry.id, title: entry.occurrence?.displayTitle ?? entry.title, color: entry.color,
                               icon: entry.todo != nil ? "circle" : entry.isHoliday ? "flag.fill" : nil,
                               time: timeText(entry),
                               detail: detailText(entry), isMuted: entry.isMuted, entry: entry))
        }
        return result
    }

    @ViewBuilder
    private func tileView(_ tile: Tile) -> some View {
        let content = EntryTile(title: tile.title, color: tile.color, icon: tile.icon, time: tile.time,
                                detail: tile.detail, isMuted: tile.isMuted)
        if let entry = tile.entry, let occurrence = entry.occurrence {
            Button { actions.openEvent(occurrence, entry.color) } label: { content }
                .buttonStyle(.plain)
                .calendarDraggable(entry)
        } else if let entry = tile.entry, let todo = entry.todo {
            Button { actions.openTodo(todo) } label: { content }
                .buttonStyle(.plain)
                .calendarDraggable(entry)
        } else {
            // Feiertage, Abos und Gerätekalender: Antippen öffnet den Tag.
            content.allowsHitTesting(false)
        }
    }

    /// Obere Zeile: Uhrzeit, „ganztägig“, Alter oder „To-do“.
    private func timeText(_ entry: CalendarEntry) -> String {
        if let occurrence = entry.occurrence, occurrence.event.isBirthday { return occurrence.timeText }
        if entry.todo != nil { return String(localized: "To-do") }
        if entry.isAllDay { return String(localized: "All day") }
        // Läuft der Termin schon seit dem Vortag, steht „…“ davor.
        if entry.start < day { return "… " + entry.end.formatted(date: .omitted, time: .shortened) }
        return entry.start.formatted(date: .omitted, time: .shortened)
    }

    /// Untere Zeile: Dauer bei Terminen mit Uhrzeit.
    private func detailText(_ entry: CalendarEntry) -> String? {
        guard !entry.isAllDay, entry.todo == nil, entry.start >= day else { return nil }
        let seconds = entry.end.timeIntervalSince(entry.start)
        guard seconds >= 60 else { return nil }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
}

/// Termin als Kachel: oben ein Balken in der Kalenderfarbe, umrandet statt gefüllt, damit der Text
/// gut lesbar bleibt. Titel bis zu drei Zeilen, unten Uhrzeit und Dauer.
struct EntryTile: View {
    let title: String
    let color: Color
    var icon: String?
    var time: String?
    var detail: String?
    var isMuted = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let icon {
                    Text("\(Image(systemName: icon)) \(title)")
                } else {
                    Text(title)
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isMuted ? Color.secondary : Color.primary)
            .lineLimit(4)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let time {
                Text(time)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 7)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .top) {
            color.frame(height: 3)
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(color.opacity(isMuted ? 0.6 : 1), lineWidth: 1.2) }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}

/// Leiste mit Wochen zum Antippen unter der Wochenansicht; folgt dem Blättern.
struct WeekStrip: View {
    let weeks: [Date]
    let selected: Date
    let onSelect: (Date) -> Void
    @State private var position: Date?

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 2) {
                ForEach(weeks, id: \.self) { week in
                    Button { onSelect(week) } label: { label(for: week) }
                        .buttonStyle(.plain)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: $position, anchor: .center)
        .contentMargins(.horizontal, 6, for: .scrollContent)
        .frame(height: 50)
        .padding(.vertical, 4)
        .background(.bar)
        .onAppear { position = selected }
        .onChange(of: selected) { withAnimation(.snappy) { position = selected } }
    }

    private func label(for week: Date) -> some View {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 6, to: week) ?? week
        let isSelected = week == selected
        let isCurrent = cal.isDate(week, equalTo: .now, toGranularity: .weekOfYear)
        let sameMonth = cal.isDate(week, equalTo: end, toGranularity: .month)
        let months = sameMonth ? week.formatted(.dateTime.month(.abbreviated))
            : "\(week.formatted(.dateTime.month(.abbreviated)))–\(end.formatted(.dateTime.month(.abbreviated)))"
        let days = "\(cal.component(.day, from: week))–\(cal.component(.day, from: end))"
        return VStack(spacing: 0) {
            Text(months)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(days)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .frame(width: 66, height: 46)
        .background {
            if isSelected {
                Capsule().fill(Color.accentColor)
            } else if isCurrent {
                Capsule().strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .contentShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((week..<end).formatted(.interval.day().month(.wide)))
        .accessibilityValue(isCurrent ? Text("This Week") : Text(""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
