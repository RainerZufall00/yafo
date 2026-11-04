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

/// Eine Woche als sieben Zeilen über die ganze Höhe: links Wochentag und Datum, rechts die
/// Termine mit Uhrzeit. Lesbarer als ein Stundenraster mit sieben schmalen Spalten auf dem iPhone.
struct WeekPageView: View {
    @Environment(AppModel.self) private var model
    let days: [Date]
    @Binding var selectedDay: Date
    let style: CalendarStyle
    var onOpenDay: ((Date) -> Void)?

    private let interval: DateInterval
    @FetchRequest private var events: FetchedResults<Event>
    @FetchRequest private var subscribed: FetchedResults<SubscribedEvent>

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
    }

    var body: some View {
        let occurrences = events.filter(style.includes).flatMap { $0.occurrences(overlapping: interval) }
        let entries = style.entries(occurrences: occurrences, subscribed: subscribed,
                                    external: model.external.items(overlapping: interval))
            .sorted(by: CalendarEntry.listOrder)
        let holidays = style.holidays(in: interval)
        let schoolHolidays = style.schoolHolidays(in: subscribed)
        VStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let end = Calendar.current.date(byAdding: .day, value: 1, to: day)!
                WeekDayRow(day: day,
                           isSelected: day == selectedDay,
                           holidays: (holidays[day] ?? []).map { $0.name() },
                           schoolHolidays: schoolHolidays[day] ?? [],
                           entries: entries.filter { $0.start < end && $0.end > day })
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedDay = day
                        onOpenDay?(day)
                    }
                Divider()
            }
        }
    }
}

private struct WeekDayRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let day: Date
    let isSelected: Bool
    let holidays: [String]
    let schoolHolidays: [String]
    let entries: [CalendarEntry]

    private let lineHeight: CGFloat = 21

    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var isWeekend: Bool { Calendar.current.isDateInWeekend(day) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            dateColumn
            GeometryReader { geometry in
                let lines = lines
                // Was nicht passt, zeigt „+n“ in der letzten Zeile.
                let capacity = max(1, Int(geometry.size.height / lineHeight))
                let shown = lines.count > capacity ? capacity - 1 : lines.count
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines.prefix(shown)) { line in
                        line.view
                            .frame(height: lineHeight)
                    }
                    if lines.count > shown {
                        Text("+\(lines.count - shown) more")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(height: lineHeight)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 12)
        .background(isSelected ? Color.accentColor.opacity(0.08) : (isWeekend ? Color.secondary.opacity(0.05) : .clear))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var dateColumn: some View {
        VStack(spacing: 1) {
            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(holidays.isEmpty ? Color.secondary : Color(hex: CalendarColors.publicHoliday))
            Text(day.formatted(.dateTime.day()))
                .font(.title3.weight(isToday ? .bold : .medium))
                .foregroundStyle(isToday ? Color.white : Color.primary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(isToday ? Color.accentColor : .clear))
        }
        .frame(width: 40)
        .padding(.top, 6)
    }

    private struct Line: Identifiable {
        let id: String
        let view: AnyView
    }

    private var lines: [Line] {
        var result: [Line] = []
        for name in holidays {
            result.append(Line(id: "h-\(name)", view: AnyView(
                Label(name, systemImage: "flag.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(hex: CalendarColors.publicHoliday))
                    .lineLimit(1))))
        }
        for name in schoolHolidays {
            result.append(Line(id: "s-\(name)", view: AnyView(
                Label(name, systemImage: "backpack.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .lineLimit(1))))
        }
        for entry in entries {
            result.append(Line(id: entry.id, view: AnyView(EntryLine(entry: entry, day: day))))
        }
        return result
    }
}

/// Ein Termin in der Wochenzeile: Ganztägiges als farbiges Band, sonst Uhrzeit und Titel.
private struct EntryLine: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: CalendarEntry
    let day: Date

    private var title: String { entry.occurrence?.displayTitle ?? entry.title }

    var body: some View {
        if entry.isAllDay || entry.occurrence?.event.isBirthday == true {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(entry.isDevice ? Color.secondary : Color.primary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 18)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(entry.color.opacity(colorScheme == .dark ? 0.35 : 0.22)))
        } else {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(entry.color)
                    .frame(width: 3, height: 14)
                Text(timeText)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 44, alignment: .trailing)
                Text(title)
                    .font(.footnote.weight(entry.isDevice ? .regular : .medium))
                    .foregroundStyle(entry.isDevice ? Color.secondary : Color.primary)
                    .lineLimit(1)
            }
        }
    }

    /// Beginn; läuft der Termin schon seit dem Vortag, steht „…“ davor.
    private var timeText: String {
        entry.start < day ? "… " + entry.end.formatted(date: .omitted, time: .shortened)
            : entry.start.formatted(date: .omitted, time: .shortened)
    }
}
