import CoreData
import SwiftUI
import YafoKit

/// Monatsraster mit farbigen Termin-Chips: Titel direkt im Tag, mehrtägige und
/// ganztägige Termine als durchgehendes Band. Was nicht passt, zeigt „+n“.
struct MonthGridView: View {
    @Environment(AppModel.self) private var model
    let grid: MonthGrid
    @Binding var selectedDay: Date
    let style: CalendarStyle
    /// Antippen eines Tages, zusätzlich zur Auswahl (iPhone: Tagesansicht öffnen).
    var onOpenDay: ((Date) -> Void)?

    private let interval: DateInterval
    @FetchRequest private var events: FetchedResults<Event>
    @FetchRequest private var subscribed: FetchedResults<SubscribedEvent>

    init(grid: MonthGrid, selectedDay: Binding<Date>, style: CalendarStyle, onOpenDay: ((Date) -> Void)? = nil) {
        self.grid = grid
        self.onOpenDay = onOpenDay
        _selectedDay = selectedDay
        self.style = style
        let start = grid.days.first?.date ?? grid.month
        let end = Calendar.current.date(byAdding: .day, value: 1, to: grid.days.last?.date ?? grid.month)!
        interval = DateInterval(start: start, end: end)
        _events = FetchRequest(sortDescriptors: [SortDescriptor(\.start)],
                               predicate: Repository.overlapPredicate(interval))
        _subscribed = FetchRequest(sortDescriptors: [SortDescriptor(\.start)],
                                   predicate: Repository.cachePredicate(sourceKeys: style.subscriptionKeys,
                                                                        interval: interval))
    }

    var body: some View {
        let occurrences = events.filter(style.includes).flatMap { $0.occurrences(overlapping: interval) }
        let visible = style.entries(occurrences: occurrences, subscribed: subscribed,
                                    external: model.external.items(overlapping: interval))
        let holidays = style.holidays(in: interval)
        let schoolHolidays = style.schoolHolidays(in: subscribed)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(MonthGrid.weekdaySymbols().enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)
            ForEach(grid.weeks, id: \.first?.date) { week in
                WeekRow(week: week, entries: visible, holidays: holidays, schoolHolidays: schoolHolidays,
                        selectedDay: $selectedDay, onOpenDay: onOpenDay)
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

private struct WeekRow: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let week: [MonthGrid.Day]
    let entries: [CalendarEntry]
    let holidays: [Date: [Holiday]]
    let schoolHolidays: [Date: [String]]
    @Binding var selectedDay: Date
    let onOpenDay: ((Date) -> Void)?

    /// iPhone: kompakt, damit drei Chips pro Tag passen. iPad: größer und besser lesbar.
    private var isRegular: Bool { sizeClass == .regular }
    private var headerHeight: CGFloat { isRegular ? 26 : 19 }
    private var chipHeight: CGFloat { isRegular ? 20 : 14 }
    private var chipSpacing: CGFloat { 2 }

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = geometry.size.width / 7
            let lanes = Int((geometry.size.height - headerHeight - 2) / (chipHeight + chipSpacing))
            let layout = layout(maxLanes: max(lanes, 0))
            let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(week) { day in
                        // Markiert nur auf dem iPad, wo die Tagesliste daneben steht.
                        DayBackground(day: day, isSelected: onOpenDay == nil && day.date == selectedDay,
                                      isHoliday: holidays[day.date] != nil,
                                      isSchoolHoliday: schoolHolidays[day.date] != nil,
                                      titles: (holidays[day.date] ?? []).map { $0.name() }
                                          + (schoolHolidays[day.date] ?? []) + titles(on: day.date),
                                      fontSize: isRegular ? 15 : 12.5)
                            .frame(width: columnWidth)
                            .onTapGesture {
                                selectedDay = day.date
                                onOpenDay?(day.date)
                            }
                    }
                }

                ForEach(layout.items) { item in
                    if let entry = byID[item.id] {
                        EventChip(title: entry.title, color: entry.color,
                                  isSpanning: item.isSpanning && !entry.isDevice, eventStyle: entry.eventStyle,
                                  continuesBefore: item.continuesBefore, continuesAfter: item.continuesAfter,
                                  fontSize: isRegular ? 12.5 : 10)
                            .frame(width: CGFloat(item.lastColumn - item.firstColumn + 1) * columnWidth - 3,
                                   height: chipHeight)
                            .offset(x: CGFloat(item.firstColumn) * columnWidth + 1.5,
                                    y: headerHeight + CGFloat(item.lane) * (chipHeight + chipSpacing))
                            .allowsHitTesting(false)
                    }
                }

                ForEach(Array(layout.hiddenCounts.enumerated()), id: \.offset) { column, count in
                    if count > 0 {
                        Text("+\(count)")
                            .font(.system(size: isRegular ? 12 : 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: columnWidth - 6, height: chipHeight, alignment: .leading)
                            .offset(x: CGFloat(column) * columnWidth + 4,
                                    y: headerHeight + CGFloat(max(lanes - 1, 0)) * (chipHeight + chipSpacing))
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(.separator).frame(height: 0.5)
        }
        .clipped()
    }

    private func layout(maxLanes: Int) -> WeekLayout<String> {
        let layoutEntries = entries.map {
            WeekLayout<String>.Entry(id: $0.id, start: $0.start, end: $0.end, isAllDay: $0.isAllDay)
        }
        return WeekLayout(weekStart: week[0].date, entries: layoutEntries, maxLanes: maxLanes)
    }

    private func titles(on day: Date) -> [String] {
        let calendar = Calendar.current
        return entries.filter { calendar.days(from: $0.start, to: $0.end).contains(day) }.map(\.title)
    }
}

private struct DayBackground: View {
    let day: MonthGrid.Day
    let isSelected: Bool
    let isHoliday: Bool
    let isSchoolHoliday: Bool
    let titles: [String]
    let fontSize: CGFloat

    private var isToday: Bool { Calendar.current.isDateInToday(day.date) }
    private var isWeekend: Bool { Calendar.current.isDateInWeekend(day.date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(day.date.formatted(.dateTime.day()))
                .font(.system(size: fontSize, weight: isToday || isSelected ? .bold : .medium))
                .foregroundStyle(isToday ? Color.white : isSelected ? Color.accentColor
                                 : isHoliday ? Color(hex: CalendarColors.publicHoliday)
                                 : day.isInMonth ? Color.primary : Color.secondary)
                .frame(minWidth: fontSize + 6, minHeight: fontSize + 6)
                .background {
                    if isToday { Circle().fill(Color.accentColor) }
                }
                .padding(.leading, 3)
                .padding(.top, 1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if isSchoolHoliday {
                // Ferien als Fläche, damit sie keine Termine aus der Zelle verdrängen.
                Color(hex: CalendarColors.schoolHoliday).opacity(0.45)
            } else if isWeekend || !day.isInMonth {
                Color.secondary.opacity(0.06)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(.separator).frame(width: 0.5)
        }
        .opacity(day.isInMonth ? 1 : 0.6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
        .accessibilityValue(titles.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Ganztägig/mehrtägig: volle Farbe mit weißer Schrift. Mit Uhrzeit nach der Darstellung
/// des Kalenders: umrandet, schraffiert oder gefüllt.
struct EventChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let color: Color
    let isSpanning: Bool
    var eventStyle: EventStyle = .outlined
    var continuesBefore = false
    var continuesAfter = false
    var fontSize: CGFloat = 10.5

    private var style: EventStyle { isSpanning ? .filled : eventStyle }

    var body: some View {
        Text(title)
            .font(.system(size: fontSize, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(style.textColor(for: color, in: colorScheme))
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                EventBackground(shape: UnevenRoundedRectangle(topLeadingRadius: continuesBefore ? 0 : 4,
                                                              bottomLeadingRadius: continuesBefore ? 0 : 4,
                                                              bottomTrailingRadius: continuesAfter ? 0 : 4,
                                                              topTrailingRadius: continuesAfter ? 0 : 4),
                                color: color, style: style)
            )
            .accessibilityHidden(true)
    }
}

/// Fläche eines Termins: volle Farbe, getönt mit Rand oder getönt mit Schraffur.
struct EventBackground<S: Shape>: View {
    @Environment(\.colorScheme) private var colorScheme
    let shape: S
    let color: Color
    let style: EventStyle

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        switch style {
        case .filled:
            shape.fill(color)
        case .outlined:
            shape.fill(color.opacity(isDark ? 0.26 : 0.14))
                // Doppelt breit und auf die Form beschnitten: 1 pt Rand innen.
                .overlay(shape.stroke(color, lineWidth: 2).clipShape(shape))
        case .hatched:
            shape.fill(color.opacity(isDark ? 0.18 : 0.1))
                .overlay(Hatching().stroke(color.opacity(isDark ? 0.6 : 0.45), lineWidth: 1.5).clipShape(shape))
        }
    }
}

/// Schräge Linien über die ganze Fläche.
struct Hatching: Shape {
    var spacing: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}

extension EventStyle {
    var title: String {
        switch self {
        case .outlined: String(localized: "Outlined")
        case .hatched: String(localized: "Hatched")
        case .filled: String(localized: "Filled")
        }
    }

    /// Weiß auf voller Farbe, sonst die Kalenderfarbe abgedunkelt bzw. aufgehellt.
    func textColor(for color: Color, in colorScheme: ColorScheme) -> Color {
        if self == .filled { return .white }
        return colorScheme == .dark ? color.mix(with: .white, by: 0.35) : color.mix(with: .black, by: 0.3)
    }
}
