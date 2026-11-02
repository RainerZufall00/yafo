import CoreData
import SwiftUI
import YafoKit

/// Termine des gewählten Tages; Teilnehmer als Initialen-Avatare.
struct DayListView: View {
    let day: Date
    let style: CalendarStyle

    private let interval: DateInterval
    @FetchRequest private var events: FetchedResults<Event>

    init(day: Date, style: CalendarStyle) {
        self.day = day
        self.style = style
        interval = DateInterval(start: day, end: Calendar.current.date(byAdding: .day, value: 1, to: day)!)
        _events = FetchRequest(sortDescriptors: [SortDescriptor(\.start)],
                               predicate: Repository.overlapPredicate(interval))
    }

    var body: some View {
        let visible = events.filter(style.includes)
            .flatMap { $0.occurrences(overlapping: interval) }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
                if visible.isEmpty {
                    Text("No events")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
                ForEach(visible) { occurrence in
                    NavigationLink {
                        EventDetailView(event: occurrence.event, originalStart: occurrence.originalStart,
                                        color: style.color(for: occurrence.event))
                    } label: {
                        EventRow(occurrence: occurrence, color: style.color(for: occurrence.event))
                    }
                    .buttonStyle(.plain)
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
                if occurrence.isAllDay {
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
                    Text(occurrence.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    if occurrence.isRecurring {
                        Image(systemName: "repeat")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Repeating")
                    }
                }
                if let subtitle = occurrence.location ?? event.calendar?.displayName {
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
