import CoreData
import SwiftUI
import YafoKit

/// Ganzes Jahr auf einem Bildschirm: eine Zeile pro Monat, eine Spalte pro Tag, Termine als
/// Balken über ihre Tage. Die Tagesspalten scrollen gemeinsam waagerecht, die Monatsnamen
/// bleiben links stehen. Auf dem iPad passen meist alle 31 Tage ohne Scrollen.
/// Tippen auf einen Tag öffnet ihn in der Monatsansicht.
struct YearView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let year: Date
    let style: CalendarStyle
    let onSelectDay: (Date) -> Void

    private let interval: DateInterval
    @FetchRequest private var events: FetchedResults<Event>
    @FetchRequest private var subscribed: FetchedResults<SubscribedEvent>

    init(year: Date, style: CalendarStyle, onSelectDay: @escaping (Date) -> Void) {
        self.year = year
        self.style = style
        self.onSelectDay = onSelectDay
        interval = Calendar.current.dateInterval(of: .year, for: year)!
        _events = FetchRequest(sortDescriptors: [SortDescriptor(\.start)],
                               predicate: Repository.overlapPredicate(interval))
        _subscribed = FetchRequest(sortDescriptors: [SortDescriptor(\.start)],
                                   predicate: Repository.cachePredicate(sourceKeys: style.subscriptionKeys,
                                                                        interval: interval))
    }

    private var metrics: YearMetrics { sizeClass == .regular ? .regular : .compact }

    var body: some View {
        let calendar = Calendar.current
        let occurrences = events.filter(style.includes).flatMap { $0.occurrences(overlapping: interval) }
        let entries = style.entries(occurrences: occurrences, subscribed: subscribed,
                                    external: model.external.items(overlapping: interval))
        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let holidays = style.holidays(in: interval)
        let schoolHolidays = style.schoolHolidays(in: subscribed)
        let monthRows = rows(entries: entries, calendar: calendar)
        let titles = dayTitles(entries: entries, holidays: holidays, schoolHolidays: schoolHolidays,
                               calendar: calendar)
        let metrics = self.metrics

        GeometryReader { geometry in
            let dayWidth = max(metrics.minDayWidth, (geometry.size.width - metrics.labelWidth - 4) / 31)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            ForEach(monthRows) { row in
                                monthLabel(row.month, calendar: calendar)
                                    .frame(width: metrics.labelWidth, height: metrics.height(lanes: row.lanes),
                                           alignment: .top)
                                    .id(row.month)
                            }
                        }
                        ScrollView(.horizontal) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(monthRows) { row in
                                    YearMonthRow(row: row, byID: byID, holidays: holidays,
                                                 schoolHolidays: schoolHolidays, titles: titles,
                                                 dayWidth: dayWidth, metrics: metrics, onSelectDay: onSelectDay)
                                        .frame(width: dayWidth * 31, height: metrics.height(lanes: row.lanes),
                                               alignment: .topLeading)
                                }
                            }
                            .padding(.trailing, 4)
                        }
                        .scrollIndicators(.hidden)
                        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    }
                    .padding(.bottom, 16)
                }
                .onAppear {
                    // Im laufenden Jahr den aktuellen Monat ins Bild holen.
                    if let current = monthRows.first(where: { calendar.isDate($0.month, equalTo: .now, toGranularity: .month) }) {
                        proxy.scrollTo(current.month, anchor: .center)
                    }
                }
            }
        }
    }

    private func monthLabel(_ month: Date, calendar: Calendar) -> some View {
        let isCurrent = calendar.isDate(month, equalTo: .now, toGranularity: .month)
        return Button {
            onSelectDay(isCurrent ? calendar.startOfDay(for: .now) : month)
        } label: {
            Text(month.formatted(.dateTime.month(.abbreviated)).replacingOccurrences(of: ".", with: "").uppercased())
                .font(.system(size: metrics.labelFontSize, weight: .semibold))
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Rectangle().fill(.separator).frame(height: 0.5)
        }
        .accessibilityLabel(month.formatted(.dateTime.month(.wide).year()))
        .accessibilityAddTraits(.isHeader)
    }

    /// Je Monat ein Layout über alle seine Tage; Termine über den Monatswechsel laufen in
    /// beiden Zeilen mit offenem Ende weiter.
    private func rows(entries: [CalendarEntry], calendar: Calendar) -> [YearRow] {
        (0..<12).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: interval.start),
                  let monthInterval = calendar.dateInterval(of: .month, for: month),
                  let dayCount = calendar.range(of: .day, in: .month, for: month)?.count else { return nil }
            let layoutEntries = entries
                .filter { $0.start < monthInterval.end && $0.end >= monthInterval.start }
                .map { WeekLayout<String>.Entry(id: $0.id, start: $0.start, end: $0.end, isAllDay: $0.isAllDay) }
            let layout = WeekLayout(start: month, columns: dayCount, entries: layoutEntries,
                                    maxLanes: metrics.maxLanes, calendar: calendar)
            let days = (0..<dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: month) }
            return YearRow(month: month, days: days, layout: layout,
                           lanes: min(max(layout.laneCount, metrics.minLanes), metrics.maxLanes))
        }
    }

    /// Für VoiceOver: alles, was an einem Tag los ist.
    private func dayTitles(entries: [CalendarEntry], holidays: [Date: [Holiday]], schoolHolidays: [Date: [String]],
                           calendar: Calendar) -> [Date: [String]] {
        var result: [Date: [String]] = [:]
        for (day, list) in holidays { result[day, default: []] += list.map { $0.name() } }
        for (day, list) in schoolHolidays { result[day, default: []] += list }
        for entry in entries.sorted(by: CalendarEntry.listOrder) {
            for day in calendar.days(from: entry.start, to: entry.end) { result[day, default: []].append(entry.title) }
        }
        return result
    }
}

private struct YearRow: Identifiable {
    let month: Date
    let days: [Date]
    let layout: WeekLayout<String>
    let lanes: Int
    var id: Date { month }
}

private struct YearMetrics {
    let labelWidth: CGFloat
    let labelFontSize: CGFloat
    let minDayWidth: CGFloat
    let headerHeight: CGFloat
    let dayFontSize: CGFloat
    let chipHeight: CGFloat
    let chipFontSize: CGFloat
    let chipSpacing: CGFloat = 2
    let bottomPadding: CGFloat = 6
    let minLanes = 2
    let maxLanes: Int

    func height(lanes: Int) -> CGFloat {
        headerHeight + CGFloat(lanes) * (chipHeight + chipSpacing) + bottomPadding
    }

    static let compact = YearMetrics(labelWidth: 42, labelFontSize: 12, minDayWidth: 30, headerHeight: 17,
                                     dayFontSize: 9.5, chipHeight: 15, chipFontSize: 9.5, maxLanes: 4)
    static let regular = YearMetrics(labelWidth: 54, labelFontSize: 14, minDayWidth: 34, headerHeight: 21,
                                     dayFontSize: 11.5, chipHeight: 18, chipFontSize: 11, maxLanes: 5)
}

/// Ein Monat als Zeile: Tagesnummern oben, darunter die Spuren mit den Terminen.
private struct YearMonthRow: View {
    let row: YearRow
    let byID: [String: CalendarEntry]
    let holidays: [Date: [Holiday]]
    let schoolHolidays: [Date: [String]]
    let titles: [Date: [String]]
    let dayWidth: CGFloat
    let metrics: YearMetrics
    let onSelectDay: (Date) -> Void

    private var laneStep: CGFloat { metrics.chipHeight + metrics.chipSpacing }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(row.days, id: \.self) { day in
                    YearDayColumn(day: day, isHoliday: holidays[day] != nil,
                                  isSchoolHoliday: schoolHolidays[day] != nil,
                                  titles: titles[day] ?? [], height: metrics.headerHeight,
                                  fontSize: metrics.dayFontSize)
                        .frame(width: dayWidth)
                        .onTapGesture { onSelectDay(day) }
                }
            }

            ForEach(row.layout.items) { item in
                if let entry = byID[item.id] {
                    EventChip(title: entry.title, color: entry.color, isMuted: entry.isMuted,
                              isFilled: item.isSpanning && !entry.isMuted,
                              continuesBefore: item.continuesBefore, continuesAfter: item.continuesAfter,
                              fontSize: metrics.chipFontSize)
                        .frame(width: CGFloat(item.lastColumn - item.firstColumn + 1) * dayWidth - 3,
                               height: metrics.chipHeight)
                        .offset(x: CGFloat(item.firstColumn) * dayWidth + 1.5,
                                y: metrics.headerHeight + CGFloat(item.lane) * laneStep)
                        .allowsHitTesting(false)
                }
            }

            ForEach(Array(row.layout.hiddenCounts.enumerated()), id: \.offset) { column, count in
                if count > 0 {
                    Text("+\(count)")
                        .font(.system(size: metrics.chipFontSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: dayWidth - 4, height: metrics.chipHeight, alignment: .leading)
                        .offset(x: CGFloat(column) * dayWidth + 3,
                                y: metrics.headerHeight + CGFloat(max(row.lanes - 1, 0)) * laneStep)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .top) {
            Rectangle().fill(.separator).frame(height: 0.5)
        }
        .clipped()
    }
}

/// Eine Tagesspalte: Nummer oben, Wochenende grau, Schulferien als Fläche.
private struct YearDayColumn: View {
    let day: Date
    let isHoliday: Bool
    let isSchoolHoliday: Bool
    let titles: [String]
    let height: CGFloat
    let fontSize: CGFloat

    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var isWeekend: Bool { Calendar.current.isDateInWeekend(day) }

    var body: some View {
        VStack(spacing: 0) {
            Text(day.formatted(.dateTime.day()))
                .font(.system(size: fontSize, weight: isToday ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(isToday ? Color.white : isHoliday ? Color(hex: CalendarColors.publicHoliday)
                                 : Color.secondary)
                .frame(minWidth: fontSize + 6, minHeight: fontSize + 5)
                .background {
                    if isToday { Capsule().fill(Color.accentColor) }
                }
                .frame(height: height)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if isSchoolHoliday {
                Color(hex: CalendarColors.schoolHoliday).opacity(0.45)
            } else if isWeekend {
                Color.secondary.opacity(0.08)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(titles.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}
