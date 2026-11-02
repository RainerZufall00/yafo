import SwiftUI
import YafoKit

/// Termin-Detail eines Vorkommens. Kommentare als Chat-Verlauf folgen noch.
struct EventDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var event: Event
    /// Ursprünglicher Beginn des Vorkommens; bei normalen Terminen der Beginn.
    let originalStart: Date
    let color: Color

    @State private var editing = false
    @State private var confirmingDelete = false

    private var occurrence: Occurrence { event.occurrence(originalStart: originalStart) }

    private var creator: Member? {
        guard let id = event.createdBy else { return nil }
        return event.calendar?.family?.members?.first { $0.id?.uuidString == id }
    }

    private var isForeign: Bool {
        guard let creator else { return false }
        return creator != model.me(in: event.calendar?.family)
    }

    var body: some View {
        // Nach dem Löschen ist das Objekt ohne Kontext; dann nichts mehr anzeigen.
        if event.managedObjectContext == nil || event.isDeleted {
            Color.clear
        } else {
            content
        }
    }

    private var content: some View {
        let occurrence = occurrence
        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(occurrence.title)
                        .font(.title2.weight(.semibold))
                    Text(occurrence.start.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                    Text(occurrence.timeText)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                if let location = occurrence.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                }
                if let repeatText = repeatDescription(event.recurrenceRule, start: event.start ?? occurrence.start) {
                    Label(repeatText, systemImage: "repeat")
                }
            }
            Section("Calendar") {
                Label {
                    Text(event.calendar?.displayName ?? "")
                } icon: {
                    Image(systemName: "circle.fill").foregroundStyle(color)
                }
            }
            if event.calendar?.family != nil {
                Section("Who's coming?") {
                    if event.sortedParticipants.isEmpty {
                        Text("Whole family")
                    }
                    ForEach(event.sortedParticipants) { member in
                        HStack {
                            MemberAvatar(member: member)
                            Text(member.displayLabel)
                        }
                    }
                }
            }
            if let notes = occurrence.notes {
                Section("Notes") {
                    Text(notes)
                }
            }
            Section {
                if let creator {
                    Text("Created by \(creator.displayLabel)")
                        .foregroundStyle(.secondary)
                }
                Button("Delete Event", systemImage: "trash", role: .destructive) {
                    confirmingDelete = true
                }
            }
        }
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { editing = true }
        }
        .sheet(isPresented: $editing) {
            EventEditorView(event: event, occurrence: occurrence)
        }
        .confirmationDialog(occurrence.isRecurring ? "This is a repeating event." : "Delete this event?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            if occurrence.isRecurring {
                Button("Delete This Event Only", role: .destructive) { delete(.thisOccurrence) }
                Button("Delete All Future Events", role: .destructive) { delete(.thisAndFollowing) }
                Button("Delete All Events", role: .destructive) { delete(.allOccurrences) }
            } else {
                Button("Delete Event", role: .destructive) { delete(.allOccurrences) }
            }
        } message: {
            if isForeign, let creator {
                Text("\(creator.displayLabel) created this event. It will be deleted for everyone.")
            }
        }
    }

    private func delete(_ scope: SeriesScope) {
        model.repository.delete(event, occurrence: originalStart, scope: scope)
        model.save()
        dismiss()
    }
}
