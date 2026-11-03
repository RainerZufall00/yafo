import CoreData
import EventKit
import SwiftUI
import UniformTypeIdentifiers
import YafoKit

/// Einmalige Übernahme von Terminen: aus Gerätekalendern, einer ICS-Adresse (z. B. der geheimen
/// iCal-Adresse von Google) oder einer .ics-Datei. Vor dem Import zeigt die Vorschau, was
/// übernommen wird und was verloren geht.
struct ImportView: View {
    enum Source: Hashable {
        case device, address, file
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt)])
    private var calendars: FetchedResults<EventCalendar>

    @State private var source: Source = .device
    @State private var address = ""
    @State private var choosingFile = false
    @State private var deviceImport = DeviceCalendarImport()
    @State private var deviceCalendars: [EKCalendar] = []
    @State private var selectedDeviceCalendars: Set<String> = []
    @State private var deviceAccessDenied = false
    @State private var loading = false
    @State private var errorText: String?

    @State private var events: [ICSEvent]?
    @State private var target: EventCalendar?
    @State private var result: ICSImportResult?

    /// Datei, mit der die App geöffnet wurde.
    var initialFile: URL?

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    resultSection(result)
                } else if let events {
                    previewSections(events)
                } else {
                    sourceSections
                }
                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result == nil ? "Cancel" : "Done", role: .cancel) { dismiss() }
                }
            }
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: Self.icsTypes) { picked in
                if case .success(let url) = picked { load(file: url) }
            }
            .onAppear {
                if target == nil { target = calendars.first { $0.family == nil } ?? calendars.first }
                if let initialFile, events == nil { load(file: initialFile) }
            }
            .overlay {
                if loading { ProgressView() }
            }
        }
    }

    static let icsTypes: [UTType] = [UTType(filenameExtension: "ics"), .calendarEvent].compactMap { $0 }

    // MARK: Quelle

    @ViewBuilder
    private var sourceSections: some View {
        Section {
            Picker("Source", selection: $source) {
                Text("Device").tag(Source.device)
                Text("Address").tag(Source.address)
                Text("File").tag(Source.file)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        switch source {
        case .device:
            Section {
                if deviceAccessDenied {
                    Text("yafo has no access to your calendars. You can allow it in Settings.")
                        .foregroundStyle(.secondary)
                } else if deviceCalendars.isEmpty {
                    Button("Show Device Calendars", systemImage: "calendar") {
                        Task { await loadDeviceCalendars() }
                    }
                } else {
                    ForEach(deviceCalendars, id: \.calendarIdentifier) { calendar in
                        Toggle(isOn: Binding(
                            get: { selectedDeviceCalendars.contains(calendar.calendarIdentifier) },
                            set: { on in
                                if on { selectedDeviceCalendars.insert(calendar.calendarIdentifier) }
                                else { selectedDeviceCalendars.remove(calendar.calendarIdentifier) }
                            }
                        )) {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(calendar.title)
                                    Text(calendar.source.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(Color(cgColor: calendar.cgColor))
                            }
                        }
                    }
                    Button("Continue") { loadDeviceEvents() }
                        .disabled(selectedDeviceCalendars.isEmpty)
                }
            } footer: {
                Text("Imports from one year ago to two years ahead. For older events, set iOS to sync “All Events” for that account.")
            }
        case .address:
            Section {
                TextField("https://… or webcal://…", text: $address, axis: .vertical)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Load") { Task { await load(address: address) } }
                    .disabled(Self.url(from: address) == nil)
            } footer: {
                Text("For Google Calendar use the secret address in iCal format from the calendar settings. Reset it at Google after the import.")
            }
        case .file:
            Section {
                Button("Choose .ics File", systemImage: "doc") { choosingFile = true }
            } footer: {
                Text("Google exports a ZIP file. Unzip it in the Files app first.")
            }
        }
    }

    // MARK: Vorschau

    @ViewBuilder
    private func previewSections(_ events: [ICSEvent]) -> some View {
        let preview = ICSImportPreview(events)
        Section {
            LabeledContent("Events", value: "\(preview.eventCount)")
            LabeledContent("Of which repeating", value: "\(preview.seriesCount)")
        }
        if preview.losesSomething {
            Section {
                if preview.withAttendees > 0 {
                    Label("Guests of \(preview.withAttendees) events", systemImage: "person.2.slash")
                }
                if preview.withAttachments > 0 {
                    Label("Attachments of \(preview.withAttachments) events", systemImage: "paperclip")
                }
                if preview.withConferenceLinks > 0 {
                    Label("Video call links of \(preview.withConferenceLinks) events", systemImage: "video.slash")
                }
            } header: {
                Text("Not Imported")
            }
        }
        Section {
            Picker("Calendar", selection: $target) {
                ForEach(calendars) { calendar in
                    Text(calendar.family.map { "\(calendar.displayName) · \($0.name ?? "")" } ?? calendar.displayName)
                        .tag(EventCalendar?.some(calendar))
                }
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text("Import Into")
        } footer: {
            Text("Events that were already imported are skipped.")
        }
        Section {
            Button("Import \(preview.eventCount) Events") { runImport(events) }
                .disabled(target == nil || preview.eventCount == 0)
            Button("Back", role: .cancel) { self.events = nil }
        }
    }

    private func resultSection(_ result: ICSImportResult) -> some View {
        Section {
            Label("\(result.created) events imported", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            if result.skipped > 0 {
                Label("\(result.skipped) already there, skipped", systemImage: "arrow.uturn.forward")
            }
        }
    }

    // MARK: Laden

    private func loadDeviceCalendars() async {
        guard await deviceImport.requestAccess() else {
            deviceAccessDenied = true
            return
        }
        deviceCalendars = deviceImport.calendars
    }

    private func loadDeviceEvents() {
        let chosen = deviceCalendars.filter { selectedDeviceCalendars.contains($0.calendarIdentifier) }
        show(deviceImport.events(in: chosen))
    }

    static func url(from text: String) -> URL? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("webcal://") { text = "https://" + text.dropFirst("webcal://".count) }
        guard let url = URL(string: text), url.scheme == "https" || url.scheme == "http", url.host != nil else { return nil }
        return url
    }

    private func load(address: String) async {
        guard let url = Self.url(from: address) else { return }
        loading = true
        defer { loading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            show(ICSParser.parse(Self.text(from: data)))
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func load(file url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            show(ICSParser.parse(Self.text(from: try Data(contentsOf: url))))
        } catch {
            errorText = error.localizedDescription
        }
    }

    private static func text(from data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    private func show(_ parsed: [ICSEvent]) {
        errorText = parsed.isEmpty ? String(localized: "No events found.") : nil
        if !parsed.isEmpty { events = parsed }
    }

    private func runImport(_ events: [ICSEvent]) {
        guard let target else { return }
        result = model.repository.importICS(events, into: target, createdBy: model.creatorID(for: target))
        model.save()
    }
}
