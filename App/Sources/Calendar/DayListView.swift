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
    @FetchRequest private var todos: FetchedResults<TodoItem>
    @Environment(\.calendarActions) private var actions

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
        _todos = FetchRequest(sortDescriptors: [SortDescriptor(\.dueDate)], predicate: Repository.duePredicate(interval))
    }

    var body: some View {
        let occurrences = events.filter(style.includes).flatMap { $0.occurrences(overlapping: interval) }
        let visible = style.entries(occurrences: occurrences, subscribed: subscribed,
                                    external: model.external.items(overlapping: interval), todos: todos)
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
                    } else if let todo = entry.todo {
                        TodoEntryRow(todo: todo, color: entry.color) { actions.openTodo(todo) }
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
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color, lineWidth: 1.2))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

/// Abo-Termin oder Termin aus einem Gerätekalender: nur lesen, ohne Teilnehmer.
struct ExternalEntryRow: View {
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
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(entry.color.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Fälliges Todo in der Tagesliste: abhaken direkt hier, antippen öffnet es.
struct TodoEntryRow: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var todo: TodoItem
    let color: Color
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy) {
                    model.repository.complete(todo)
                    model.save()
                }
            } label: {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(color)
            }
            .buttonStyle(.plain)
            .frame(width: 52, alignment: .trailing)
            .accessibilityLabel("Mark as done")

            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title ?? "")
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text("To-do")
                    if todo.recurrenceRule != nil {
                        Image(systemName: "repeat").accessibilityLabel("Repeating")
                    }
                    if let family = todo.family?.name {
                        Text("· \(family)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let assignee = todo.assignee {
                MemberAvatar(member: assignee, size: 24)
            }
        }
        .padding(.vertical, 8)
        .padding(.trailing, 10)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Edit", onOpen)
    }
}

/// iPhone: Tage als Seiten mit den Termin-Karten; seitlich wischen blättert zum Vor- bzw. Folgetag.
/// Ein Jahr in jede Richtung ab dem geöffneten Tag; gebaut werden nur die sichtbaren Seiten.
struct DayPage: View {
    let style: CalendarStyle
    /// Meldet den angezeigten Tag, damit das Monatsraster beim Zurückgehen dort steht.
    var onDayChange: ((Date) -> Void)?

    private let days: [Date]
    @State private var day: Date
    @State private var scrolledDay: Date?
    @State private var showingEditor = false

    init(day: Date, style: CalendarStyle, onDayChange: ((Date) -> Void)? = nil) {
        let start = Calendar.current.startOfDay(for: day)
        self.style = style
        self.onDayChange = onDayChange
        days = (-366...366).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
        _day = State(initialValue: start)
        _scrolledDay = State(initialValue: start)
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(days, id: \.self) { page in
                    DayListView(day: page, style: style, showsHeader: false)
                        .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $scrolledDay)
        .onChange(of: scrolledDay) {
            guard let scrolledDay, scrolledDay != day else { return }
            day = scrolledDay
            onDayChange?(scrolledDay)
        }
        // Wischen allein wäre für VoiceOver nicht erreichbar: Drei-Finger-Wischen blättert.
        .accessibilityScrollAction { edge in
            switch edge {
            case .leading: show(offset: -1)
            case .trailing: show(offset: 1)
            default: break
            }
        }
        .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("New Event", systemImage: "plus") { showingEditor = true }
        }
        .sheet(isPresented: $showingEditor) {
            EventEditorView(initialDay: day)
        }
    }

    private func show(offset: Int) {
        guard let target = Calendar.current.date(byAdding: .day, value: offset, to: day),
              days.contains(target) else { return }
        withAnimation(.snappy) { scrolledDay = target }
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
