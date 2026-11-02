import CoreData
import SwiftUI
import YafoKit

/// Termin anlegen oder bearbeiten: Kalender wählen, dann Teilnehmer per Chips antippen.
/// Bei Serien fragt das Sichern, ob nur dieser, dieser und folgende oder alle Termine gemeint sind.
struct EventEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let event: Event?
    /// Ursprünglicher Beginn des bearbeiteten Vorkommens einer Serie.
    private let originalStart: Date?
    private let initialRule: String?
    private let initialCalendar: EventCalendar?
    private let initialParticipants: Set<Member>
    private let initialAllDay: Bool

    @State private var title: String
    @State private var isAllDay: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var location: String
    @State private var notes: String
    @State private var calendar: EventCalendar?
    @State private var participants: Set<Member>
    @State private var repeatSettings: RepeatSettings
    @State private var askingScope = false

    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt)])
    private var calendars: FetchedResults<EventCalendar>

    init(event: Event? = nil, occurrence: Occurrence? = nil, initialDay: Date = .now) {
        self.event = event
        originalStart = occurrence?.originalStart
        let cal = Calendar.current
        let defaultStart: Date = {
            // Neuer Termin: am gewählten Tag zur nächsten vollen Stunde.
            let hour = cal.component(.hour, from: .now) + 1
            return cal.date(bySettingHour: min(hour, 23), minute: 0, second: 0, of: initialDay) ?? initialDay
        }()
        let start = occurrence?.start ?? event?.start ?? defaultStart
        var end = occurrence?.end ?? event?.end ?? start.addingTimeInterval(3600)
        if event?.isAllDay == true {
            // Gespeichert ist das exklusive Ende, angezeigt wird der letzte Tag.
            end = cal.date(byAdding: .day, value: -1, to: end) ?? end
        }
        initialRule = event?.recurrenceRule
        initialCalendar = event?.calendar
        initialParticipants = event?.participants ?? []
        initialAllDay = event?.isAllDay ?? false

        _title = State(initialValue: occurrence?.title ?? event?.title ?? "")
        _isAllDay = State(initialValue: initialAllDay)
        _start = State(initialValue: start)
        _end = State(initialValue: end)
        _location = State(initialValue: occurrence?.location ?? event?.location ?? "")
        _notes = State(initialValue: occurrence?.notes ?? event?.notes ?? "")
        _calendar = State(initialValue: initialCalendar)
        _participants = State(initialValue: initialParticipants)
        _repeatSettings = State(initialValue: RepeatSettings(rule: event?.recurrenceRule, start: event?.start ?? start))
    }

    private var familyMembers: [Member] {
        calendar?.family.map(model.repository.activeMembers(of:)) ?? []
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && calendar != nil
    }

    /// Bezug für den Standard-Wochentag der Regel: der Serienbeginn, bei neuen Terminen der Beginn.
    private var ruleStart: Date { event?.start ?? start }

    private var ruleString: String? { repeatSettings.ruleString(start: ruleStart) }

    private var isEditingSeries: Bool { event?.isRecurring == true && originalStart != nil }

    /// Kalender, Teilnehmer, Ganztägig und Wiederholung gelten für die ganze Serie,
    /// nicht für ein einzelnes Vorkommen.
    private var changesSeriesStructure: Bool {
        calendar != initialCalendar || participants != initialParticipants || isAllDay != initialAllDay
            || ruleString != initialRule
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
                repeatSection
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
                    Button("Save", role: .confirm) {
                        if isEditingSeries { askingScope = true } else { save(scope: .allOccurrences) }
                    }
                    .disabled(!canSave)
                }
            }
            .confirmationDialog("This is a repeating event.", isPresented: $askingScope, titleVisibility: .visible) {
                if !changesSeriesStructure {
                    Button("Save for This Event Only") { save(scope: .thisOccurrence) }
                }
                Button("Save for Future Events") { save(scope: .thisAndFollowing) }
                Button("Save for All Events") { save(scope: .allOccurrences) }
                Button("Cancel", role: .cancel) {}
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
                // Neuer Termin: Wochentag der Wiederholung folgt dem Beginn.
                let cal = Calendar.current
                if event == nil, repeatSettings.weekdays == [cal.component(.weekday, from: oldValue)] {
                    repeatSettings.weekdays = [cal.component(.weekday, from: newValue)]
                }
            }
        }
    }

    @ViewBuilder
    private var repeatSection: some View {
        Section("Repeat") {
            Picker("Repeat", selection: $repeatSettings.frequency) {
                Text("Never").tag(RepeatSettings.Frequency.never)
                Text("Every Day").tag(RepeatSettings.Frequency.daily)
                Text("Every Week").tag(RepeatSettings.Frequency.weekly)
                Text("Every 2 Weeks").tag(RepeatSettings.Frequency.biweekly)
                Text("Every Month").tag(RepeatSettings.Frequency.monthly)
                Text("Every Year").tag(RepeatSettings.Frequency.yearly)
                if repeatSettings.isCustomAvailable {
                    Text("Custom").tag(RepeatSettings.Frequency.custom)
                }
            }
            if repeatSettings.frequency == .weekly || repeatSettings.frequency == .biweekly {
                WeekdayChips(selection: $repeatSettings.weekdays)
            }
            if repeatSettings.frequency != .never {
                Picker("End Repeat", selection: $repeatSettings.end) {
                    Text("Never").tag(RepeatSettings.End.never)
                    Text("On Date").tag(RepeatSettings.End.onDate)
                    Text("After").tag(RepeatSettings.End.afterCount)
                }
                switch repeatSettings.end {
                case .onDate:
                    DatePicker("End Date", selection: $repeatSettings.endDate, in: start..., displayedComponents: .date)
                case .afterCount:
                    Stepper("\(repeatSettings.count) times", value: $repeatSettings.count, in: 1...999)
                case .never:
                    EmptyView()
                }
            }
        }
    }

    private func calendarLabel(_ calendar: EventCalendar) -> String {
        if let family = calendar.family?.name {
            return "\(calendar.displayName) · \(family)"
        }
        return calendar.displayName
    }

    private func save(scope: SeriesScope) {
        guard let calendar else { return }
        let cal = Calendar.current
        var start = start
        var end = max(end, start)
        if isAllDay {
            start = cal.startOfDay(for: start)
            end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end))!
        }
        let draft = EventDraft(title: title.trimmingCharacters(in: .whitespaces), start: start, end: end,
                               isAllDay: isAllDay, location: location.isEmpty ? nil : location,
                               notes: notes.isEmpty ? nil : notes, calendar: calendar, participants: participants,
                               recurrenceRule: ruleString)
        if let event {
            model.repository.update(event, occurrence: originalStart, with: draft, scope: scope)
        } else {
            let created = model.repository.createEvent(title: draft.title, start: start, end: end, isAllDay: isAllDay,
                                                       in: calendar, participants: participants,
                                                       recurrenceRule: draft.recurrenceRule,
                                                       createdBy: model.creatorID(for: calendar))
            created.location = draft.location
            created.notes = draft.notes
        }
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

/// Wochentage für wöchentliche Serien, in der Reihenfolge des Kalenders.
struct WeekdayChips: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let calendar = Calendar.current
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        HStack(spacing: 6) {
            ForEach(order, id: \.self) { weekday in
                let isOn = selection.contains(weekday)
                Button {
                    // Mindestens ein Tag bleibt ausgewählt.
                    if isOn, selection.count > 1 { selection.remove(weekday) } else { selection.insert(weekday) }
                } label: {
                    Text(calendar.veryShortStandaloneWeekdaySymbols[weekday - 1])
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .background(Circle().fill(isOn ? Color.accentColor : Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(calendar.standaloneWeekdaySymbols[weekday - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
