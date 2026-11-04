import CoreData
import SwiftUI
import UIKit
import YafoKit

/// Vorschau „Termin aus Screenshot“: Bild lesen, erkannte Termine anzeigen und anpassen,
/// Kalender wählen, übernehmen. Läuft in der App und in der Share Extension; dort gibt es kein
/// `AppModel`, darum kommen Repository und Ersteller von außen.
struct ScreenshotImportView: View {
    let image: UIImage
    let repository: Repository
    let creatorID: (EventCalendar) -> String?
    /// Mit der Zahl der angelegten Termine; 0 bei „Abbrechen“.
    let onFinish: (Int) -> Void

    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt)])
    private var calendars: FetchedResults<EventCalendar>

    @State private var result: ScreenshotReader.Result?
    @State private var proposals: [EventProposal] = []
    @State private var skipped: Set<UUID> = []
    /// Gibt es schon (gleicher Titel, gleicher Beginn), z. B. weil der Screenshot zweimal geteilt wurde.
    @State private var existing: Set<UUID> = []
    /// Wiederholung je Vorschlag, wie im Editor einstellbar.
    @State private var repeats: [UUID: RepeatSettings] = [:]
    @State private var calendar: EventCalendar?
    @State private var errorText: String?

    private var selectedCount: Int { proposals.count - skipped.count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Screenshot")
                }
                if let result {
                    if proposals.isEmpty {
                        ContentUnavailableView("No Events Found", systemImage: "calendar.badge.exclamationmark",
                                               description: Text("There seems to be no date in this picture."))
                    } else {
                        ForEach($proposals) { $proposal in
                            proposalSection($proposal)
                        }
                        calendarSection(result.method)
                    }
                }
                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { onFinish(0) }
                }
                if !proposals.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(selectedCount > 1 ? "Add (\(selectedCount))" : "Add", role: .confirm, action: save)
                            .disabled(selectedCount == 0 || calendar == nil)
                    }
                }
            }
            .overlay {
                if result == nil {
                    ProgressView("Reading screenshot…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .task { await read() }
            .onAppear { if calendar == nil { calendar = calendars.first } }
        }
    }

    // MARK: Abschnitte

    private func proposalSection(_ proposal: Binding<EventProposal>) -> some View {
        let id = proposal.wrappedValue.id
        let included = Binding(
            get: { !skipped.contains(id) },
            set: { if $0 { skipped.remove(id) } else { skipped.insert(id) } }
        )
        return Section {
            if proposals.count > 1 || existing.contains(id) {
                Toggle("Add This Event", isOn: included)
            }
            if included.wrappedValue {
                TextField("Title", text: proposal.title)
                Toggle("All day", isOn: allDayBinding(proposal))
                DatePicker("Starts", selection: startBinding(proposal),
                           displayedComponents: proposal.wrappedValue.isAllDay ? .date : [.date, .hourAndMinute])
                DatePicker("Ends", selection: proposal.end, in: proposal.wrappedValue.start...,
                           displayedComponents: proposal.wrappedValue.isAllDay ? .date : [.date, .hourAndMinute])
                RepeatRows(settings: repeatBinding(id, start: proposal.wrappedValue.start),
                           start: proposal.wrappedValue.start)
                LocationField(location: Binding(
                    get: { proposal.wrappedValue.location ?? "" },
                    set: { proposal.wrappedValue.location = $0.isEmpty ? nil : $0 }
                ), geo: proposal.geo, suggestsInitially: true)
            } else {
                Text(proposal.wrappedValue.title.isEmpty ? String(localized: "New Event") : proposal.wrappedValue.title)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            if existing.contains(id) {
                Text("\(Image(systemName: "exclamationmark.circle")) Already in your calendar")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func calendarSection(_ method: ScreenshotReader.Method) -> some View {
        Section {
            Picker("Calendar", selection: $calendar) {
                ForEach(calendars) { calendar in
                    Text(calendarLabel(calendar)).tag(EventCalendar?.some(calendar))
                }
            }
        } footer: {
            switch method {
            case .imageModel, .textModel:
                Text("Recognized on this device with Apple Intelligence. Please check the details; the picture is not saved.")
            case .dataDetector:
                Text("Recognized on this device from the dates in the text. Please check the details; the picture is not saved.")
            }
        }
    }

    /// Wie im Termin-Editor: Familienname nur, wenn man in mehreren Familien ist.
    private func calendarLabel(_ calendar: EventCalendar) -> String {
        let familyCount = Set(calendars.compactMap(\.family)).count
        if familyCount > 1, let family = calendar.family?.name {
            return "\(calendar.displayName) · \(family)"
        }
        return calendar.displayName
    }

    // MARK: Bindungen

    private func repeatBinding(_ id: UUID, start: Date) -> Binding<RepeatSettings> {
        Binding(
            get: { repeats[id] ?? RepeatSettings(rule: nil, start: start) },
            set: { repeats[id] = $0 }
        )
    }

    /// Beginn verschieben nimmt das Ende mit, die Dauer bleibt. Wie im Editor wandert der
    /// Wochentag einer Serie mit, solange nur der des Beginns gewählt ist.
    private func startBinding(_ proposal: Binding<EventProposal>) -> Binding<Date> {
        Binding(
            get: { proposal.wrappedValue.start },
            set: { newStart in
                let cal = Calendar.current
                let id = proposal.wrappedValue.id
                let oldWeekday = cal.component(.weekday, from: proposal.wrappedValue.start)
                if repeats[id]?.weekdays == [oldWeekday] {
                    repeats[id]?.weekdays = [cal.component(.weekday, from: newStart)]
                }
                let duration = proposal.wrappedValue.end.timeIntervalSince(proposal.wrappedValue.start)
                proposal.wrappedValue.start = newStart
                proposal.wrappedValue.end = newStart.addingTimeInterval(max(duration, 0))
            }
        )
    }

    /// Von ganztägig auf Uhrzeit: 9 Uhr für eine Stunde statt Mitternacht.
    private func allDayBinding(_ proposal: Binding<EventProposal>) -> Binding<Bool> {
        Binding(
            get: { proposal.wrappedValue.isAllDay },
            set: { allDay in
                let cal = Calendar.current
                if allDay {
                    proposal.wrappedValue.start = cal.startOfDay(for: proposal.wrappedValue.start)
                    proposal.wrappedValue.end = cal.startOfDay(for: proposal.wrappedValue.end)
                } else {
                    let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: proposal.wrappedValue.start)
                        ?? proposal.wrappedValue.start
                    proposal.wrappedValue.start = start
                    proposal.wrappedValue.end = start.addingTimeInterval(3600)
                }
                proposal.wrappedValue.isAllDay = allDay
            }
        )
    }

    // MARK: Ablauf

    private func read() async {
        guard result == nil, let cgImage = image.normalizedCGImage else {
            if result == nil { result = ScreenshotReader.Result(proposals: [], method: .dataDetector) }
            return
        }
        let read = await ScreenshotReader.read(cgImage)
        proposals = read.proposals
        repeats = Dictionary(uniqueKeysWithValues: read.proposals.map {
            ($0.id, RepeatSettings(rule: $0.recurrenceRule, start: $0.start))
        })
        existing = Set(read.proposals.filter(alreadyExists).map(\.id))
        skipped = existing
        result = read
        await resolveAddresses()
    }

    /// Erkannte Adressen gleich in Apple Maps nachschlagen; Namen wie „Aula“ bekommen nur Vorschläge.
    private func resolveAddresses() async {
        for proposal in proposals where proposal.geo == nil {
            guard let location = proposal.location, let geo = await LocationField.resolveAddress(location),
                  let index = proposals.firstIndex(where: { $0.id == proposal.id }),
                  proposals[index].location == location, proposals[index].geo == nil else { continue }
            proposals[index].geo = geo
        }
    }

    private func alreadyExists(_ proposal: EventProposal) -> Bool {
        let times = proposal.draftTimes()
        let title = proposal.title.trimmingCharacters(in: .whitespaces)
        return repository.occurrences(overlapping: DateInterval(start: times.start, end: times.end.addingTimeInterval(1)))
            .contains { $0.start == times.start && $0.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    private func save() {
        guard let calendar else { return }
        var count = 0
        for proposal in proposals where !skipped.contains(proposal.id) {
            let times = proposal.draftTimes()
            let title = proposal.title.trimmingCharacters(in: .whitespaces)
            let rule = repeats[proposal.id]?.ruleString(start: times.start)
            let event = repository.createEvent(title: title.isEmpty ? String(localized: "New Event") : title,
                                               start: times.start, end: times.end, isAllDay: proposal.isAllDay,
                                               in: calendar, recurrenceRule: rule, createdBy: creatorID(calendar))
            event.location = proposal.location
            event.geo = proposal.location == nil ? nil : proposal.geo
            count += 1
        }
        do {
            try repository.save()
            onFinish(count)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

extension UIImage {
    /// `CGImage` in richtiger Ausrichtung; Fotos tragen die Drehung sonst nur als Metadaten.
    var normalizedCGImage: CGImage? {
        if imageOrientation == .up, let cgImage { return cgImage }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(at: .zero) }.cgImage
    }
}
