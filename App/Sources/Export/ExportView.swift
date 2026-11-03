import CoreData
import EventKit
import SwiftUI
import UniformTypeIdentifiers
import YafoKit

/// Daten mitnehmen: Kalender als ICS, Listen und Termine als CSV, Kopie in einen Gerätekalender
/// und JSON-Backup samt Wiederherstellung. Alles für eine Familie, nur die eigenen Daten oder alles.
struct ExportView: View {
    /// Fertige Dateien zum Teilen, neu erzeugt bei jeder Änderung des Umfangs.
    private struct Files {
        var calendar: URL
        var events: URL
        var shopping: URL
        var todos: URL
        var backup: URL
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)])
    private var families: FetchedResults<Family>

    @AppStorage("autoBackup") private var autoBackup = true
    @State private var scope: ExportScope = .all
    @State private var files: Files?

    @State private var deviceExport = DeviceCalendarExport()
    @State private var deviceCalendars: [EKCalendar] = []
    @State private var deviceTarget: String?
    @State private var deviceAccessDenied = false
    @State private var deviceResult: DeviceCalendarExport.Result?

    @State private var choosingBackup = false
    @State private var pendingRestore: Backup?
    @State private var restoreResult: RestoreResult?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Export", selection: $scope) {
                        Text("Everything").tag(ExportScope.all)
                        Text("Just me").tag(ExportScope.personal)
                        ForEach(families) { family in
                            Text(family.name ?? "").tag(ExportScope.family(family))
                        }
                    }
                }

                filesSection
                deviceSection
                backupSection

                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Export & Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: scope) { files = makeFiles() }
            .fileImporter(isPresented: $choosingBackup, allowedContentTypes: [.json]) { result in
                readBackup(result)
            }
            .confirmationDialog("Restore Backup?", isPresented: Binding(get: { pendingRestore != nil },
                                                                        set: { if !$0 { pendingRestore = nil } }),
                                titleVisibility: .visible, presenting: pendingRestore) { backup in
                Button("Restore") { restore(backup) }
                Button("Cancel", role: .cancel) {}
            } message: { backup in
                Text("Backup from \(backup.createdAt.formatted(date: .abbreviated, time: .shortened)). Entries that still exist are kept; only missing ones are added again.")
            }
            .alert("Backup Restored", isPresented: Binding(get: { restoreResult != nil },
                                                           set: { if !$0 { restoreResult = nil } }),
                   presenting: restoreResult) { _ in
                Button("OK") {}
            } message: { result in
                Text(restoreMessage(result))
            }
        }
    }

    // MARK: Abschnitte

    @ViewBuilder private var filesSection: some View {
        Section {
            if let files {
                ShareLink(item: files.calendar) {
                    Label("Calendars (ICS)", systemImage: "calendar")
                }
                ShareLink(item: files.events) {
                    Label("Events (CSV)", systemImage: "tablecells")
                }
                ShareLink(item: files.shopping) {
                    Label("Shopping List (CSV)", systemImage: "cart")
                }
                ShareLink(item: files.todos) {
                    Label("To-dos (CSV)", systemImage: "checklist")
                }
            }
        } header: {
            Text("Files")
        } footer: {
            Text("ICS opens in every calendar app; series and exceptions are kept, participants and comments are in the notes. CSV opens in Numbers or Excel.")
        }
    }

    @ViewBuilder private var deviceSection: some View {
        Section {
            if deviceAccessDenied {
                Label("yafo has no access to your calendars. You can allow it in Settings.", systemImage: "lock")
                    .foregroundStyle(.secondary)
            } else if deviceCalendars.isEmpty {
                Button("Choose Device Calendar", systemImage: "iphone") {
                    Task { await loadDeviceCalendars() }
                }
            } else {
                Picker("Target Calendar", selection: $deviceTarget) {
                    ForEach(deviceCalendars, id: \.calendarIdentifier) { calendar in
                        Label {
                            Text(calendar.title)
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(Color(cgColor: calendar.cgColor))
                        }
                        .tag(String?.some(calendar.calendarIdentifier))
                    }
                }
                Button("Copy Events", systemImage: "square.and.arrow.up.on.square") { copyToDevice() }
                    .disabled(deviceTarget == nil)
                if let deviceResult {
                    Label(deviceResultText(deviceResult), systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
        } header: {
            Text("Copy to Device Calendar")
        } footer: {
            Text("Copies the events into a calendar on this iPhone, e.g. your work calendar. Copying again replaces the earlier copies. Later changes in yafo are not copied automatically.")
        }
    }

    @ViewBuilder private var backupSection: some View {
        Section {
            if let files {
                ShareLink(item: files.backup) {
                    Label("Save Backup", systemImage: "externaldrive.badge.plus")
                }
            }
            Button("Restore from Backup…", systemImage: "arrow.counterclockwise") { choosingBackup = true }
            Toggle("Weekly Backup", isOn: $autoBackup)
                .onChange(of: autoBackup) { _, enabled in
                    if enabled { Task { await model.autoBackupIfDue() } }
                }
        } header: {
            Text("Backup")
        } footer: {
            if let last = model.lastAutoBackup {
                Text("Saved weekly to the yafo folder in iCloud Drive, the last five are kept. Last backup: \(last.formatted(date: .abbreviated, time: .shortened)).")
            } else {
                Text("Saved weekly to the yafo folder in iCloud Drive, the last five are kept.")
            }
        }
    }

    // MARK: Dateien

    private func makeFiles() -> Files? {
        let repository = model.repository
        let folder = URL.temporaryDirectory.appending(path: "Export", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let label = scopeLabel
        let calendars = repository.calendars(in: scope)

        func write(_ text: String, _ name: String) throws -> URL {
            let url = folder.appending(path: name)
            try Data(text.utf8).write(to: url)
            return url
        }
        do {
            let backup = try repository.makeBackup(scope: scope).encoded()
            let backupURL = folder.appending(path: Backup.fileName())
            try backup.write(to: backupURL)
            return Files(
                calendar: try write(repository.icsDocument(for: calendars, name: "yafo – \(label)"), "yafo \(label).ics"),
                events: try write(repository.eventCSV(for: calendars), "yafo \(label) – \(String(localized: "Events")).csv"),
                shopping: try write(repository.shoppingCSV(repository.shoppingItems(in: scope)) { $0.title },
                                    "yafo \(label) – \(String(localized: "Shopping")).csv"),
                todos: try write(repository.todoCSV(repository.todoItems(in: scope)),
                                 "yafo \(label) – \(String(localized: "To-dos")).csv"),
                backup: backupURL)
        } catch {
            errorText = error.localizedDescription
            return nil
        }
    }

    private var scopeLabel: String {
        switch scope {
        case .all: String(localized: "Everything")
        case .personal: String(localized: "Just me")
        case .family(let family): family.name ?? "yafo"
        }
    }

    // MARK: Gerätekalender

    private func loadDeviceCalendars() async {
        guard await deviceExport.requestAccess() else {
            deviceAccessDenied = true
            return
        }
        deviceCalendars = deviceExport.writableCalendars
        deviceTarget = deviceExport.store.defaultCalendarForNewEvents?.calendarIdentifier
            ?? deviceCalendars.first?.calendarIdentifier
    }

    private func copyToDevice() {
        guard let id = deviceTarget, let target = deviceExport.calendar(withIdentifier: id) else { return }
        do {
            deviceResult = try deviceExport.export(model.repository.calendars(in: scope), to: target,
                                                   repository: model.repository)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func deviceResultText(_ result: DeviceCalendarExport.Result) -> String {
        result.replaced > 0
            ? String(localized: "\(result.copied + result.replaced) events copied, \(result.replaced) of them replaced.")
            : String(localized: "\(result.copied) events copied.")
    }

    // MARK: Wiederherstellen

    private func readBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            pendingRestore = try Backup.decode(Data(contentsOf: url))
            errorText = nil
        } catch let error as BackupError {
            errorText = error.localizedDescription
        } catch is DecodingError {
            errorText = BackupError.notABackup.localizedDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func restore(_ backup: Backup) {
        restoreResult = model.repository.restore(backup, personalCalendarName: String(localized: "My Calendar"))
        model.save()
        model.refreshAfterSync()
        files = makeFiles()
    }

    private func restoreMessage(_ result: RestoreResult) -> String {
        var text = String(localized: "\(result.created) entries added, \(result.skipped) already existed.")
        if !result.newFamilies.isEmpty {
            text += "\n" + String(localized: "Created again with you as owner: \(result.newFamilies.formatted(.list(type: .and))).")
        }
        return text
    }
}
