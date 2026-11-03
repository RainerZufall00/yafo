import CoreData
import SwiftUI
import YafoKit

/// Termine des gewählten Tages; Teilnehmer als Initialen-Avatare.
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if showsHeader {
                    Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 2)
                }
                ForEach(style.holidays(in: interval)[day] ?? [], id: \.germanName) { holiday in
                    HolidayRow(name: holiday.name())
                }
                ForEach(style.schoolHolidays(in: subscribed)[day] ?? [], id: \.self) { name in
                    SchoolHolidayRow(name: name)
                }
                if visible.isEmpty {
                    Text("No events")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
                ForEach(visible) { entry in
                    if let occurrence = entry.occurrence {
                        NavigationLink {
                            EventDetailView(event: occurrence.event, originalStart: occurrence.originalStart,
                                            color: entry.color)
                        } label: {
                            EventRow(occurrence: occurrence, color: entry.color)
                        }
                        .buttonStyle(.plain)
                    } else {
                        ExternalEntryRow(entry: entry)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
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
