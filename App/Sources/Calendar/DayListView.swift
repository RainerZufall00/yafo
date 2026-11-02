import CoreData
import SwiftUI
import YafoKit

/// Termine des gewählten Tages; Teilnehmer als Initialen-Avatare.
struct DayListView: View {
    let day: Date
    let style: CalendarStyle

    @FetchRequest private var events: FetchedResults<Event>

    init(day: Date, style: CalendarStyle) {
        self.day = day
        self.style = style
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        _events = FetchRequest(sortDescriptors: [SortDescriptor(\.isAllDay, order: .reverse),
                                                 SortDescriptor(\.start)],
                               predicate: overlapPredicate(day, end))
    }

    var body: some View {
        let visible = events.filter(style.includes)
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
                ForEach(visible) { event in
                    NavigationLink {
                        EventDetailView(event: event, color: style.color(for: event))
                    } label: {
                        EventRow(event: event, color: style.color(for: event))
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
    @ObservedObject var event: Event
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 1) {
                if event.isAllDay {
                    Text("All day")
                        .font(.caption.weight(.semibold))
                } else if let start = event.start, let end = event.end {
                    Text(start.formatted(date: .omitted, time: .shortened))
                        .font(.caption.weight(.semibold))
                    Text(end.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 52, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? "")
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                if let subtitle = event.location ?? event.calendar?.displayName {
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
