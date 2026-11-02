import CoreData
import SwiftUI
import YafoKit

/// Zwölf Mini-Monate: 3 × 4 auf dem iPhone, 4 × 3 auf dem iPad. Tage mit Terminen sind
/// dezent markiert; Tippen auf einen Monat öffnet die Monatsansicht.
struct YearView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let year: Date
    let style: CalendarStyle
    let onSelectMonth: (Date) -> Void

    private let interval: DateInterval
    @FetchRequest private var events: FetchedResults<Event>

    init(year: Date, style: CalendarStyle, onSelectMonth: @escaping (Date) -> Void) {
        self.year = year
        self.style = style
        self.onSelectMonth = onSelectMonth
        interval = Calendar.current.dateInterval(of: .year, for: year)!
        _events = FetchRequest(sortDescriptors: [SortDescriptor(\.start)],
                               predicate: Repository.overlapPredicate(interval))
    }

    private var months: [Date] {
        (0..<12).compactMap { Calendar.current.date(byAdding: .month, value: $0, to: interval.start) }
    }

    var body: some View {
        let calendar = Calendar.current
        let busyDays = Set(events.filter(style.includes)
            .flatMap { $0.occurrences(overlapping: interval) }
            .flatMap { calendar.days(from: $0.start, to: $0.end) })
        let columns = sizeClass == .regular ? 4 : 3

        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: columns), spacing: 20) {
                ForEach(months, id: \.self) { month in
                    Button {
                        onSelectMonth(month)
                    } label: {
                        MiniMonth(month: month, busyDays: busyDays)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(month.formatted(.dateTime.month(.wide).year()))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}

private struct MiniMonth: View {
    let month: Date
    let busyDays: Set<Date>

    var body: some View {
        let calendar = Calendar.current
        let grid = MonthGrid(containing: month)
        let isCurrentMonth = calendar.isDate(month, equalTo: .now, toGranularity: .month)

        VStack(alignment: .leading, spacing: 4) {
            Text(month.formatted(.dateTime.month(.abbreviated)))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isCurrentMonth ? Color.accentColor : Color.primary)
            Grid(horizontalSpacing: 0, verticalSpacing: 1) {
                ForEach(grid.weeks, id: \.first?.date) { week in
                    GridRow {
                        ForEach(week) { day in
                            dayCell(day, calendar: calendar)
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func dayCell(_ day: MonthGrid.Day, calendar: Calendar) -> some View {
        if day.isInMonth {
            let isToday = calendar.isDateInToday(day.date)
            Text(day.date.formatted(.dateTime.day()))
                .font(.system(size: 9, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.white : calendar.isDateInWeekend(day.date) ? Color.secondary : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 14)
                .background {
                    if isToday {
                        Circle().fill(Color.accentColor)
                    } else if busyDays.contains(day.date) {
                        Circle().fill(Color.accentColor.opacity(0.18))
                    }
                }
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 14)
        }
    }
}
