import SwiftUI
import YafoKit

/// Termin-Detail. Kommentare als Chat-Verlauf folgen in Phase 2.
struct EventDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var event: Event
    let color: Color

    @State private var editing = false
    @State private var confirmingDelete = false

    private var creator: Member? {
        guard let id = event.createdBy else { return nil }
        return event.calendar?.family?.members?.first { $0.id?.uuidString == id }
    }

    private var isForeign: Bool {
        guard let creator else { return false }
        return creator != model.me(in: event.calendar?.family)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title ?? "")
                        .font(.title2.weight(.semibold))
                    if let start = event.start {
                        Text(start.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                    }
                    Text(event.timeText)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                if let location = event.location {
                    Label(location, systemImage: "mappin.and.ellipse")
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
            if let notes = event.notes {
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
            EventEditorView(event: event)
        }
        .confirmationDialog("Delete this event?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Event", role: .destructive) {
                model.repository.delete(event)
                model.save()
                dismiss()
            }
        } message: {
            if isForeign, let creator {
                Text("\(creator.displayLabel) created this event. It will be deleted for everyone.")
            }
        }
    }
}
