import CoreData
import SwiftUI
import YafoKit

/// Termin anlegen oder bearbeiten: Kalender wählen, dann Teilnehmer per Chips antippen.
struct EventEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let event: Event?

    @State private var title: String
    @State private var isAllDay: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var location: String
    @State private var notes: String
    @State private var calendar: EventCalendar?
    @State private var participants: Set<Member>

    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt)])
    private var calendars: FetchedResults<EventCalendar>

    init(event: Event? = nil, initialDay: Date = .now) {
        self.event = event
        let cal = Calendar.current
        let defaultStart: Date = {
            // Neuer Termin: am gewählten Tag zur nächsten vollen Stunde.
            let hour = cal.component(.hour, from: .now) + 1
            return cal.date(bySettingHour: min(hour, 23), minute: 0, second: 0, of: initialDay) ?? initialDay
        }()
        let start = event?.start ?? defaultStart
        var end = event?.end ?? start.addingTimeInterval(3600)
        if event?.isAllDay == true {
            // Gespeichert ist das exklusive Ende, angezeigt wird der letzte Tag.
            end = cal.date(byAdding: .day, value: -1, to: end) ?? end
        }
        _title = State(initialValue: event?.title ?? "")
        _isAllDay = State(initialValue: event?.isAllDay ?? false)
        _start = State(initialValue: start)
        _end = State(initialValue: end)
        _location = State(initialValue: event?.location ?? "")
        _notes = State(initialValue: event?.notes ?? "")
        _calendar = State(initialValue: event?.calendar)
        _participants = State(initialValue: event?.participants ?? [])
    }

    private var familyMembers: [Member] {
        calendar?.family.map(model.repository.activeMembers(of:)) ?? []
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && calendar != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Location", text: $location)
                }
                Section {
                    Toggle("All day", isOn: $isAllDay)
                    DatePicker("Starts", selection: $start,
                               displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
                    DatePicker("Ends", selection: $end, in: start...,
                               displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
                }
                Section("Calendar") {
                    Picker("Calendar", selection: $calendar) {
                        ForEach(calendars) { calendar in
                            Label {
                                Text(calendarLabel(calendar))
                            } icon: {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(Color(hex: model.repository.color(of: calendar)))
                            }
                            .tag(EventCalendar?.some(calendar))
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                if !familyMembers.isEmpty {
                    Section {
                        ParticipantChips(members: familyMembers, selection: $participants)
                    } header: {
                        Text("Who's coming?")
                    } footer: {
                        Text("No one selected means the whole family.")
                    }
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(event == nil ? "New Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm) { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if calendar == nil { calendar = calendars.first }
            }
            .onChange(of: calendar) {
                participants = participants.filter { $0.family != nil && $0.family == calendar?.family }
            }
            .onChange(of: start) { oldValue, newValue in
                // Dauer beibehalten, wenn der Beginn verschoben wird.
                end = end.addingTimeInterval(newValue.timeIntervalSince(oldValue))
            }
        }
    }

    private func calendarLabel(_ calendar: EventCalendar) -> String {
        if let family = calendar.family?.name {
            return "\(calendar.displayName) · \(family)"
        }
        return calendar.displayName
    }

    private func save() {
        guard let calendar else { return }
        let cal = Calendar.current
        var start = start
        var end = max(end, start)
        if isAllDay {
            start = cal.startOfDay(for: start)
            end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end))!
        }
        let title = title.trimmingCharacters(in: .whitespaces)

        let target: Event
        if let event, event.calendar?.objectID.persistentStore == calendar.objectID.persistentStore {
            target = event
            target.calendar = calendar
            target.title = title
            target.start = start
            target.end = end
            target.isAllDay = isAllDay
            target.participants = participants
            target.updatedAt = .now
        } else {
            // Neu, oder Umzug in einen Kalender in einem anderen Store: Beziehungen
            // über Stores hinweg sind nicht erlaubt, also neu anlegen.
            target = model.repository.createEvent(title: title, start: start, end: end, isAllDay: isAllDay,
                                                  in: calendar, participants: participants,
                                                  createdBy: event?.createdBy ?? model.creatorID(for: calendar))
            if let event { model.repository.delete(event) }
        }
        target.location = location.isEmpty ? nil : location
        target.notes = notes.isEmpty ? nil : notes
        model.save()
        dismiss()
    }
}

/// Chips für Erwachsene und Kinderprofile der Familie.
struct ParticipantChips: View {
    let members: [Member]
    @Binding var selection: Set<Member>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(members) { member in
                    let isOn = selection.contains(member)
                    Button {
                        if isOn { selection.remove(member) } else { selection.insert(member) }
                    } label: {
                        HStack(spacing: 6) {
                            MemberAvatar(member: member, size: 22)
                            Text(member.displayLabel)
                        }
                        .padding(.leading, 4)
                        .padding(.trailing, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1)))
                        .overlay(Capsule().strokeBorder(isOn ? Color.accentColor : .clear))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }
}
