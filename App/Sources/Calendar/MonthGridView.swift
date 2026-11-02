import CoreData
import SwiftUI
import YafoKit

/// Monatsraster mit farbigen Termin-Chips: Titel direkt im Tag, mehrtägige und
/// ganztägige Termine als durchgehendes Band. Was nicht passt, zeigt „+n“.
struct MonthGridView: View {
    let grid: MonthGrid
    @Binding var selectedDay: Date
    let style: CalendarStyle

    @FetchRequest private var events: FetchedResults<Event>

    init(grid: MonthGrid, selectedDay: Binding<Date>, style: CalendarStyle) {
        self.grid = grid
        _selectedDay = selectedDay
        self.style = style
        let start = grid.days.first?.date ?? grid.month
        let end = Calendar.current.date(byAdding: .day, value: 1, to: grid.days.last?.date ?? grid.month)!
        _events = FetchRequest(sortDescriptors: [SortDescriptor(\.start)], predicate: overlapPredicate(start, end))
    }

    var body: some View {
        let visible = events.filter(style.includes)
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
                WeekRow(week: week, events: visible, style: style, selectedDay: $selectedDay)
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

private struct WeekRow: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let week: [MonthGrid.Day]
    let events: [Event]
    let style: CalendarStyle
    @Binding var selectedDay: Date

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
            let byID = Dictionary(events.map { ($0.objectID, $0) }, uniquingKeysWith: { first, _ in first })

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(week) { day in
                        DayBackground(day: day, isSelected: day.date == selectedDay,
                                      titles: titles(on: day.date), fontSize: isRegular ? 15 : 12.5)
                            .frame(width: columnWidth)
                            .onTapGesture { selectedDay = day.date }
                    }
                }

                ForEach(layout.items) { item in
                    if let event = byID[item.id] {
                        EventChip(title: event.title ?? "", color: style.color(for: event), isSpanning: item.isSpanning,
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

    private func layout(maxLanes: Int) -> WeekLayout<NSManagedObjectID> {
        let entries = events.compactMap { event -> WeekLayout<NSManagedObjectID>.Entry? in
            guard let start = event.start, let end = event.end else { return nil }
            return .init(id: event.objectID, start: start, end: end, isAllDay: event.isAllDay)
        }
        return WeekLayout(weekStart: week[0].date, entries: entries, maxLanes: maxLanes)
    }

    private func titles(on day: Date) -> [String] {
        let calendar = Calendar.current
        return events.filter { event in
            guard let start = event.start, let end = event.end else { return false }
            return calendar.days(from: start, to: end).contains(day)
        }
        .compactMap(\.title)
    }
}

private struct DayBackground: View {
    let day: MonthGrid.Day
    let isSelected: Bool
    let titles: [String]
    let fontSize: CGFloat

    private var isToday: Bool { Calendar.current.isDateInToday(day.date) }
    private var isWeekend: Bool { Calendar.current.isDateInWeekend(day.date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(day.date.formatted(.dateTime.day()))
                .font(.system(size: fontSize, weight: isToday || isSelected ? .bold : .medium))
                .foregroundStyle(isToday ? Color.white : day.isInMonth ? Color.primary : Color.secondary)
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
            if isSelected {
                Color.accentColor.opacity(0.12)
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

/// Ganztägig/mehrtägig: volle Farbe mit weißer Schrift. Mit Uhrzeit: getönter Hintergrund,
/// Schrift in der Kalenderfarbe.
struct EventChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let color: Color
    let isSpanning: Bool
    var continuesBefore = false
    var continuesAfter = false
    var fontSize: CGFloat = 10.5

    var body: some View {
        Text(title)
            .font(.system(size: fontSize, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(isSpanning ? Color.white : textColor)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: continuesBefore ? 0 : 4,
                                       bottomLeadingRadius: continuesBefore ? 0 : 4,
                                       bottomTrailingRadius: continuesAfter ? 0 : 4,
                                       topTrailingRadius: continuesAfter ? 0 : 4)
                    .fill(isSpanning ? color : color.opacity(colorScheme == .dark ? 0.3 : 0.18))
            )
            .accessibilityHidden(true)
    }

    private var textColor: Color {
        colorScheme == .dark ? color.mix(with: .white, by: 0.35) : color.mix(with: .black, by: 0.3)
    }
}
