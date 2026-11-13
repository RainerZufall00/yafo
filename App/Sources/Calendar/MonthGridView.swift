import CoreData
import SwiftUI
import YafoKit

/// Monatsraster mit umrandeten Termin-Chips: Titel direkt im Tag, mehrtägige und
/// ganztägige Termine als durchgehendes Band. Was nicht passt, zeigt „+n“.
/// Lange auf einen Tag drücken legt dort einen Termin an; Termine und Todos lassen sich verschieben.
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
    @FetchRequest private var todos: FetchedResults<TodoItem>

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
        _todos = FetchRequest(sortDescriptors: [SortDescriptor(\.dueDate)], predicate: Repository.duePredicate(interval))
    }

    var body: some View {
        let occurrences = events.filter(style.includes).flatMap { $0.occurrences(overlapping: interval) }
        let visible = style.entries(occurrences: occurrences, subscribed: subscribed,
                                    external: model.external.items(overlapping: interval), todos: todos,
                                    observancesIn: interval)
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
    @Environment(\.calendarActions) private var actions
    let week: [MonthGrid.Day]
    let entries: [CalendarEntry]
    let holidays: [Date: [Holiday]]
    let schoolHolidays: [Date: [String]]
    @Binding var selectedDay: Date
    let onOpenDay: ((Date) -> Void)?
    @State private var dropTarget: Date?

    /// iPhone: kompakt, damit mehrere Chips pro Tag passen. iPad: größer und besser lesbar.
    private var isRegular: Bool { sizeClass == .regular }
    private var headerHeight: CGFloat { isRegular ? 26 : 19 }
    private var chipHeight: CGFloat { isRegular ? 20 : 14 }
    /// Zweizeilige Chips, wenn die Woche dafür Platz hat: Titel stehen dann meist ganz da.
    private var tallChipHeight: CGFloat { isRegular ? 34 : 23 }
    private var chipSpacing: CGFloat { 2 }
    private var fontSize: CGFloat { isRegular ? 12 : 9 }

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = geometry.size.width / 7
            let available = geometry.size.height - headerHeight - 2
            let needed = layout(maxLanes: .max).laneCount
            let isTall = CGFloat(needed) * (tallChipHeight + chipSpacing) <= available
            let chipHeight = isTall ? tallChipHeight : chipHeight
            let lanes = Int(available / (chipHeight + chipSpacing))
            let layout = layout(maxLanes: max(lanes, 0))
            let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(week) { day in
                        DayBackground(day: day, isSelected: day.date == selectedDay,
                                      isHoliday: holidays[day.date] != nil,
                                      isSchoolHoliday: schoolHolidays[day.date] != nil,
                                      titles: (holidays[day.date] ?? []).map { $0.name() }
                                          + (schoolHolidays[day.date] ?? []) + titles(on: day.date),
                                      isDropTarget: dropTarget == day.date,
                                      fontSize: isRegular ? 15 : 12.5)
                            .frame(width: columnWidth)
                            .onTapGesture { open(day.date) }
                            .onLongPressGesture(minimumDuration: 0.4) { actions.createEvent(day.date) }
                    }
                }

                ForEach(layout.items) { item in
                    if let entry = byID[item.id] {
                        EventChip(title: entry.title, color: entry.color,
                                  icon: entry.todo != nil ? "circle" : nil, isMuted: entry.isMuted,
                                  continuesBefore: item.continuesBefore, continuesAfter: item.continuesAfter,
                                  fontSize: fontSize, lineLimit: isTall && !item.isSpanning ? 2 : 1)
                            .frame(width: CGFloat(item.lastColumn - item.firstColumn + 1) * columnWidth - 3,
                                   height: chipHeight)
                            // Antippen öffnet den Tag unter dem Finger, lange drücken hebt den Termin an.
                            .gesture(SpatialTapGesture().onEnded { tap in
                                let column = item.firstColumn + Int((tap.location.x + 1.5) / columnWidth)
                                if week.indices.contains(column) { open(week[column].date) }
                            })
                            .calendarDraggable(entry)
                            .allowsHitTesting(entry.isMovable)
                            .offset(x: CGFloat(item.firstColumn) * columnWidth + 1.5,
                                    y: headerHeight + CGFloat(item.lane) * (chipHeight + chipSpacing))
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
            .calendarDrop(entries: entries, hovered: $dropTarget) { location in
                let column = Int(location.x / columnWidth)
                return week.indices.contains(column) ? week[column].date : nil
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(.separator).frame(height: 0.5)
        }
        .clipped()
    }

    private func open(_ day: Date) {
        selectedDay = day
        onOpenDay?(day)
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
    var isDropTarget = false
    let fontSize: CGFloat

    private var isToday: Bool { Calendar.current.isDateInToday(day.date) }
    private var isWeekend: Bool { Calendar.current.isDateInWeekend(day.date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(day.date.formatted(.dateTime.day()))
                .font(.system(size: fontSize, weight: isToday || isSelected ? .bold : .medium))
                .foregroundStyle(isToday ? Color.white : isHoliday ? Color(hex: CalendarColors.publicHoliday)
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
            if isSelected {
                Color.accentColor.opacity(0.12)
            } else if isSchoolHoliday {
                // Ferien als Fläche, damit sie keine Termine aus der Zelle verdrängen.
                Color(hex: CalendarColors.schoolHoliday).opacity(0.45)
            } else if isWeekend || !day.isInMonth {
                Color.secondary.opacity(0.06)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(.separator).frame(width: 0.5)
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.12))
            }
        }
        .opacity(day.isInMonth ? 1 : 0.6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
        .accessibilityValue(titles.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Touch and hold to add an event.")
    }
}

/// Termin im Raster: umrandet in der Kalenderfarbe, Schrift in Textfarbe – so bleibt sie auch klein
/// lesbar. Lange Titel werden erst etwas kleiner, bevor sie abgeschnitten werden.
/// Die Jahresansicht nutzt `isFilled` für kräftige Bänder.
struct EventChip: View {
    let title: String
    let color: Color
    /// SF Symbol vor dem Titel, z. B. ein Kreis für Todos.
    var icon: String?
    /// Gerätekalender: grau statt in Textfarbe.
    var isMuted = false
    var isFilled = false
    var continuesBefore = false
    var continuesAfter = false
    var fontSize: CGFloat = 10.5
    var lineLimit = 1

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: continuesBefore ? 0 : 4,
                                           bottomLeadingRadius: continuesBefore ? 0 : 4,
                                           bottomTrailingRadius: continuesAfter ? 0 : 4,
                                           topTrailingRadius: continuesAfter ? 0 : 4)
        label
            .font(.system(size: fontSize, weight: .semibold))
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.8)
            .truncationMode(.tail)
            .lineSpacing(-1)
            .foregroundStyle(isFilled ? Color.white : isMuted ? Color.secondary : Color.primary)
            .padding(.horizontal, 2.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background {
                if isFilled { shape.fill(color) } else { shape.strokeBorder(color, lineWidth: 1.2) }
            }
            .contentShape(shape)
            .accessibilityHidden(true)
    }

    private var label: Text {
        if let icon { Text("\(Image(systemName: icon)) \(title)") } else { Text(title) }
    }
}
