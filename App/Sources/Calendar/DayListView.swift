import CoreData
import SwiftUI
import YafoKit

/// Der gewählte Tag: oben Feiertage, Ferien und ganztägige Termine als Karten, darunter
/// die Zeitleiste mit Uhrzeiten für alle Termine mit Uhrzeit.
struct DayListView: View {
    @Environment(AppModel.self) private var model
    let day: Date
    let style: CalendarStyle
    var showsHeader = true

    private let interval: DateInterval
    @FetchRequest private var events: FetchedResults<Event>
    @FetchRequest private var subscribed: FetchedResults<SubscribedEvent>

    init(day: Date, style: CalendarStyle, showsHeader: Bool = true) {
        self.day = day
        self.showsHeader = showsHeader
        self.style = style
        interval = DateInterval(start: day, end: Calendar.current.date(byAdding: .day, value: 1, to: day)!)
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
            .sorted(by: CalendarEntry.listOrder)
        // Ganztägig oder über den ganzen Tag: oben als Karte, alles andere in der Zeitleiste.
        let allDay = visible.filter { $0.isAllDay || ($0.start <= interval.start && $0.end >= interval.end) }
        let timed = visible.filter { !($0.isAllDay || ($0.start <= interval.start && $0.end >= interval.end)) }
        let holidays = style.holidays(in: interval)[day] ?? []
        let schoolHolidays = style.schoolHolidays(in: subscribed)[day] ?? []
        let topCount = allDay.count + holidays.count + schoolHolidays.count + (visible.isEmpty ? 1 : 0)

        VStack(spacing: 0) {
            if showsHeader || topCount > 0 {
                Group {
                    // Viele ganztägige Einträge scrollen für sich, damit die Zeitleiste sichtbar bleibt.
                    if topCount > 3 {
                        ScrollView {
                            topSection(allDay: allDay, holidays: holidays, schoolHolidays: schoolHolidays,
                                       isEmpty: visible.isEmpty)
                        }
                        .frame(maxHeight: 190)
                    } else {
                        topSection(allDay: allDay, holidays: holidays, schoolHolidays: schoolHolidays,
                                   isEmpty: visible.isEmpty)
                    }
                }
                Divider()
            }
            DayTimeline(day: day, entries: timed)
        }
    }

    private func topSection(allDay: [CalendarEntry], holidays: [Holiday], schoolHolidays: [String],
                            isEmpty: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsHeader {
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
            }
            ForEach(holidays, id: \.germanName) { holiday in
                HolidayRow(name: holiday.name())
            }
            ForEach(schoolHolidays, id: \.self) { name in
                SchoolHolidayRow(name: name)
            }
            if isEmpty {
                Text("No events")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(allDay) { entry in
                EntryLink(entry: entry) {
                    if let occurrence = entry.occurrence {
                        EventRow(occurrence: occurrence, color: entry.color)
                    } else {
                        ExternalEntryRow(entry: entry)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// Eigene Termine öffnen die Details; Abo- und Gerätetermine sind nur zum Lesen.
private struct EntryLink<Content: View>: View {
    let entry: CalendarEntry
    @ViewBuilder let label: () -> Content

    var body: some View {
        if let occurrence = entry.occurrence {
            NavigationLink {
                EventDetailView(event: occurrence.event, originalStart: occurrence.originalStart, color: entry.color)
            } label: {
                label()
            }
            .buttonStyle(.plain)
        } else {
            label()
        }
    }
}

/// Zeitleiste des Tages: eine Zeile pro Stunde, Termine nach Beginn und Dauer, sich
/// überschneidende nebeneinander. Heute zeigt eine rote Linie die aktuelle Uhrzeit.
private struct DayTimeline: View {
    let day: Date
    let entries: [CalendarEntry]

    @ScaledMetric(relativeTo: .caption) private var hourHeight: CGFloat = 54
    private let labelWidth: CGFloat = 52
    /// Platz über 0 Uhr und unter 24 Uhr für die Beschriftung.
    private let inset: CGFloat = 10
    /// Kürzeste dargestellte Dauer, damit auch kurze Termine einen lesbaren Kasten haben.
    private let minimumMinutes: Double = 30

    var body: some View {
        let layout = DayLayout<String>(day: day, entries: entries.map { .init(id: $0.id, start: $0.start, end: $0.end) },
                               minimumMinutes: minimumMinutes)
        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let isToday = Calendar.current.isDateInToday(day)
        // Heute ab der aktuellen Stunde, sonst ab dem ersten Termin, ohne Termine ab 7 Uhr.
        let firstHour = isToday ? Calendar.current.component(.hour, from: .now)
            : layout.items.map { Int($0.startMinute / 60) }.min() ?? 8
        let scrollHour = max(firstHour - 1, 0)

        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    hourGrid
                    GeometryReader { geometry in
                        let columnsWidth = max(geometry.size.width - labelWidth - 12, 40)
                        ZStack(alignment: .topLeading) {
                            ForEach(layout.items) { item in
                                if let entry = byID[item.id] {
                                    let width = columnsWidth / CGFloat(item.columnCount)
                                    let height = CGFloat(max(item.endMinute - item.startMinute, minimumMinutes) / 60)
                                        * hourHeight - 2
                                    EntryLink(entry: entry) {
                                        TimelineBlock(entry: entry, height: height,
                                                      continuesBefore: item.continuesBefore,
                                                      continuesAfter: item.continuesAfter)
                                    }
                                    .frame(width: width - 2, height: height)
                                    .offset(x: labelWidth + 4 + CGFloat(item.column) * width,
                                            y: y(minute: item.startMinute) + 1)
                                }
                            }
                            if isToday {
                                TimelineView(.everyMinute) { context in
                                    nowLine(width: columnsWidth + 8)
                                        .offset(x: labelWidth, y: y(minute: minuteOfDay(context.date)) - 4)
                                }
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .frame(height: hourHeight * 24 + inset * 2)
            }
            .task(id: day) {
                proxy.scrollTo(scrollHour, anchor: .top)
            }
        }
    }

    /// Stundenlinien mit Uhrzeit, die Beschriftung mittig auf der Linie.
    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(0...24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 6) {
                    Text(Self.hourLabel(hour))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: labelWidth - 6, alignment: .trailing)
                        .offset(y: -7)
                    Rectangle()
                        .fill(.separator)
                        .frame(height: 0.5)
                }
                .frame(height: hour == 24 ? 1 : hourHeight, alignment: .top)
                .id(hour)
            }
        }
        .padding(.top, inset)
        .accessibilityHidden(true)
    }

    private func nowLine(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Circle().fill(.red).frame(width: 8, height: 8)
            Rectangle().fill(.red).frame(height: 1.5)
        }
        .frame(width: width, height: 8)
    }

    private func y(minute: Double) -> CGFloat {
        inset + CGFloat(minute / 60) * hourHeight
    }

    private func minuteOfDay(_ date: Date) -> Double {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    /// „08:00“ bzw. „8:00 AM“; Stunde 24 als „00:00“. Ein fester Tag ohne Zeitumstellung,
    /// damit jede Stunde existiert.
    private static func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: hour % 24)) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Ein Termin in der Zeitleiste, gezeichnet nach der Darstellung seines Kalenders.
private struct TimelineBlock: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: CalendarEntry
    let height: CGFloat
    let continuesBefore: Bool
    let continuesAfter: Bool

    private var timeText: String {
        if let occurrence = entry.occurrence { return occurrence.timeText }
        return "\(entry.start.formatted(date: .omitted, time: .shortened)) – \(entry.end.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: continuesBefore ? 0 : 6,
                                           bottomLeadingRadius: continuesAfter ? 0 : 6,
                                           bottomTrailingRadius: continuesAfter ? 0 : 6,
                                           topTrailingRadius: continuesBefore ? 0 : 6)
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(entry.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(height > 44 ? 2 : 1)
                if height < 34 {
                    Text(entry.start.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .opacity(0.8)
                        .lineLimit(1)
                }
            }
            if height >= 34 {
                Text(timeText)
                    .font(.caption2)
                    .opacity(0.85)
                    .lineLimit(1)
            }
            if height >= 60, let subtitle = entry.location ?? entry.occurrence?.event.calendar?.displayName {
                Text(subtitle)
                    .font(.caption2)
                    .opacity(0.85)
                    .lineLimit(1)
            }
            if height >= 84, let event = entry.occurrence?.event, !event.sortedParticipants.isEmpty {
                HStack(spacing: -5) {
                    ForEach(event.sortedParticipants.prefix(4)) { member in
                        MemberAvatar(member: member, size: 18)
                            .background(Circle().fill(Color(.systemBackground)))
                    }
                }
                .padding(.top, 2)
            }
        }
        .foregroundStyle(entry.eventStyle.textColor(for: entry.color, in: colorScheme))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(EventBackground(shape: shape, color: entry.color, style: entry.eventStyle))
        .clipShape(shape)
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.title + ", " + timeText)
    }
}

/// Termin als farbig getönte Karte: Uhrzeit links, Farbstreifen, Titel, Teilnehmer.
struct EventRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let occurrence: Occurrence
    let color: Color

    private var event: Event { occurrence.event }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 1) {
                if event.isBirthday {
                    Image(systemName: "birthday.cake.fill")
                        .font(.title3)
                        .foregroundStyle(color)
                        .accessibilityLabel("Birthday")
                } else if occurrence.isAllDay {
                    Text("All day")
                        .font(.caption.weight(.semibold))
                } else {
                    Text(occurrence.start.formatted(date: .omitted, time: .shortened))
                        .font(.caption.weight(.semibold))
                    Text(occurrence.end.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 52, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(event.isBirthday ? occurrence.title : occurrence.displayTitle)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    if occurrence.isRecurring && !event.isBirthday {
                        Image(systemName: "repeat")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Repeating")
                    }
                }
                if event.isBirthday, occurrence.age != nil {
                    Text(occurrence.timeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let subtitle = occurrence.location ?? event.calendar?.displayName {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: -6) {
                ForEach(event.sortedParticipants.prefix(4)) { member in
                    MemberAvatar(member: member, size: 24)
                        .background(Circle().fill(Color(.systemBackground)))
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.trailing, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(colorScheme == .dark ? 0.22 : 0.12))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

/// Abo-Termin oder Termin aus einem Gerätekalender: nur lesen, ohne Teilnehmer.
struct ExternalEntryRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: CalendarEntry

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 1) {
                if entry.isAllDay {
                    Text("All day")
                        .font(.caption.weight(.semibold))
                } else {
                    Text(entry.start.formatted(date: .omitted, time: .shortened))
                        .font(.caption.weight(.semibold))
                    Text(entry.end.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 52, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(entry.color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.body.weight(entry.isDevice ? .regular : .semibold))
                    .foregroundStyle(entry.isDevice ? .secondary : .primary)
                    .lineLimit(2)
                if let location = entry.location {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: entry.isDevice ? "iphone" : "link")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(entry.isDevice ? Text("Device calendar") : Text("Subscription"))
        }
        .padding(.vertical, 8)
        .padding(.trailing, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(entry.color.opacity(colorScheme == .dark ? 0.18 : 0.08))
        )
        .accessibilityElement(children: .combine)
    }
}

/// iPhone: ein Tag als eigene Seite mit den Termin-Karten.
struct DayPage: View {
    let day: Date
    let style: CalendarStyle
    @State private var showingEditor = false

    var body: some View {
        DayListView(day: day, style: style, showsHeader: false)
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("New Event", systemImage: "plus") { showingEditor = true }
            }
            .sheet(isPresented: $showingEditor) {
                EventEditorView(initialDay: day)
            }
    }
}

/// Feiertag in der Tagesliste: rote Fahne und Name.
struct HolidayRow: View {
    let name: String

    var body: some View {
        let red = Color(hex: CalendarColors.publicHoliday)
        HStack(spacing: 10) {
            Image(systemName: "flag.fill")
                .foregroundStyle(red)
                .frame(width: 52, alignment: .trailing)
            Text(name)
                .font(.body.weight(.semibold))
                .foregroundStyle(red)
            Spacer()
        }
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(red.opacity(0.1)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Public holiday: \(name)"))
    }
}

/// Schulferien in der Tagesliste: orange Fläche mit Namen.
struct SchoolHolidayRow: View {
    let name: String

    var body: some View {
        let orange = Color(hex: CalendarColors.schoolHoliday)
        HStack(spacing: 10) {
            Image(systemName: "backpack.fill")
                .foregroundStyle(.orange)
                .frame(width: 52, alignment: .trailing)
            Text(name)
                .font(.body.weight(.semibold))
            Spacer()
        }
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(orange.opacity(0.5)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("School holidays: \(name)"))
    }
}
