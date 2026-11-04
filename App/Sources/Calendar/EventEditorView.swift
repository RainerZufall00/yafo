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
    @State private var geo: String?
    @State private var notes: String
    @State private var calendar: EventCalendar?
    @State private var participants: Set<Member>
    @State private var repeatSettings: RepeatSettings
    @State private var askingScope = false
    @State private var kind: EventKind
    /// Bei Geburtstagen: Jahr im Datum ist das Geburtsjahr.
    @State private var birthYearKnown: Bool

    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt)])
    private var calendars: FetchedResults<EventCalendar>

    init(event: Event? = nil, occurrence: Occurrence? = nil, initialDay: Date = .now, kind: EventKind = .event) {
        self.event = event
        originalStart = occurrence?.originalStart
        let cal = Calendar.current
        let defaultStart: Date = {
            // Neuer Termin: am gewählten Tag zur nächsten vollen Stunde.
            let hour = cal.component(.hour, from: .now) + 1
            return cal.date(bySettingHour: min(hour, 23), minute: 0, second: 0, of: initialDay) ?? initialDay
        }()
        var start = occurrence?.start ?? event?.start ?? defaultStart
        if let event, event.isBirthday, event.birthYear > 0, let born = event.start {
            // Geburtstag mit Jahr: das Geburtsdatum bearbeiten.
            start = born
        }
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
        let location = occurrence?.location ?? event?.location ?? ""
        _location = State(initialValue: location)
        // Koordinaten gehören zum Ort der Serie; ein abweichender Ort eines Vorkommens hat keine.
        _geo = State(initialValue: location == event?.location ? event?.geo : nil)
        _notes = State(initialValue: occurrence?.notes ?? event?.notes ?? "")
        _calendar = State(initialValue: initialCalendar)
        _participants = State(initialValue: initialParticipants)
        _kind = State(initialValue: event?.kind ?? kind)
        _birthYearKnown = State(initialValue: event.map { $0.birthYear > 0 } ?? true)
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

    private var isEditingSeries: Bool { kind == .event && event?.isRecurring == true && originalStart != nil }

    /// Kalender, Teilnehmer, Ganztägig und Wiederholung gelten für die ganze Serie,
    /// nicht für ein einzelnes Vorkommen.
    private var changesSeriesStructure: Bool {
        calendar != initialCalendar || participants != initialParticipants || isAllDay != initialAllDay
            || ruleString != initialRule
    }

    var body: some View {
        NavigationStack {
            Form {
                if event == nil {
                    Picker("Type", selection: $kind) {
                        Label("Event", systemImage: "calendar").tag(EventKind.event)
                        Label("Birthday", systemImage: "birthday.cake").tag(EventKind.birthday)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if kind == .birthday {
                    birthdaySection
                } else {
                    Section {
                        TextField("Title", text: $title)
                        LocationField(location: $location, geo: $geo)
                    }
                    Section {
                        Toggle("All day", isOn: $isAllDay)
                        DatePicker("Starts", selection: $start,
                                   displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
                        DatePicker("Ends", selection: $end, in: start...,
                                   displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
                    }
                    repeatSection
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
                if !familyMembers.isEmpty && kind == .event {
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
            .navigationTitle(navigationTitle)
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

    private var navigationTitle: LocalizedStringKey {
        switch (kind, event == nil) {
        case (.birthday, true): "New Birthday"
        case (.birthday, false): "Edit Birthday"
        case (.event, true): "New Event"
        case (.event, false): "Edit Event"
        }
    }

    private var birthdaySection: some View {
        Section {
            TextField("Name", text: $title)
                .textContentType(.name)
            DatePicker(birthYearKnown ? "Date of Birth" : "Birthday", selection: $start,
                       in: ...(birthYearKnown ? Date.now : Date.distantFuture), displayedComponents: .date)
            Toggle("Year of Birth Known", isOn: Binding(
                get: { birthYearKnown },
                set: { known in
                    // Ohne Jahr liegt der Tag oft in der Zukunft; das Geburtsdatum darf das nicht.
                    // Tag und Monat bleiben, das Jahr wird das des letzten Geburtstags.
                    if known, start > .now { start = Birthday.latestPast(sameDayAs: start) }
                    birthYearKnown = known
                }
            ))
            if birthYearKnown {
                // Alternativ zum Jahr: Alter eingeben, Tag und Monat bleiben.
                LabeledContent("Age") {
                    HStack(spacing: 12) {
                        TextField("Age", value: age, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 56)
                        Stepper("Age", value: age, in: 0...130)
                            .labelsHidden()
                    }
                }
            }
        } footer: {
            Text(birthYearKnown
                 ? "Enter the date of birth or just the age. The age is shown and counts up every year."
                 : "Only day and month are used.")
        }
    }

    /// Alter heute; ändern setzt das Geburtsjahr passend.
    private var age: Binding<Int> {
        Binding(
            get: { Birthday.age(birthDate: start) },
            set: { start = Birthday.birthDate(sameDayAs: start, age: min(max($0, 0), 130)) }
        )
    }

    private var repeatSection: some View {
        Section("Repeat") {
            RepeatRows(settings: $repeatSettings, start: start)
        }
    }

    /// Den Familiennamen nur anhängen, wenn man in mehreren Familien ist.
    private func calendarLabel(_ calendar: EventCalendar) -> String {
        let familyCount = Set(calendars.compactMap(\.family)).count
        if familyCount > 1, let family = calendar.family?.name {
            return "\(calendar.displayName) · \(family)"
        }
        return calendar.displayName
    }

    private func save(scope: SeriesScope) {
        guard let calendar else { return }
        if kind == .birthday {
            saveBirthday(in: calendar)
            return
        }
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
                               recurrenceRule: ruleString, geo: geo)
        if let event {
            model.repository.update(event, occurrence: originalStart, with: draft, scope: scope)
        } else {
            let created = model.repository.createEvent(title: draft.title, start: start, end: end, isAllDay: isAllDay,
                                                       in: calendar, participants: participants,
                                                       recurrenceRule: draft.recurrenceRule,
                                                       createdBy: model.creatorID(for: calendar))
            created.location = draft.location
            created.geo = draft.location == nil ? nil : geo
            created.notes = draft.notes
        }
        model.save()
        dismiss()
    }
}

extension EventEditorView {
    private func saveBirthday(in calendar: EventCalendar) {
        let name = title.trimmingCharacters(in: .whitespaces)
        let year = birthYearKnown ? Calendar.current.component(.year, from: start) : nil
        let notes = notes.isEmpty ? nil : notes
        if let event {
            model.repository.updateBirthday(event, name: name, day: start, birthYear: year,
                                            calendar: calendar, notes: notes)
        } else {
            model.repository.createBirthday(name: name, day: start, birthYear: year, in: calendar,
                                            notes: notes, createdBy: model.creatorID(for: calendar))
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
