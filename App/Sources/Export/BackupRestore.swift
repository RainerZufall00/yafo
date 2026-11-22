import SwiftUI
import UniformTypeIdentifiers
import YafoKit

/// Backup einspielen: automatisches Backup aus der Liste oder Datei wählen, nachfragen,
/// wiederherstellen, Ergebnis zeigen. Als Modifier, damit Onboarding, „Familie“ und
/// „Export & Backup“ denselben Ablauf nutzen. Ohne automatische Backups geht es direkt zur
/// Dateiauswahl.
private struct BackupRestore: ViewModifier {
    /// Was nach dem Schließen der Liste kommt.
    private enum Next {
        case chooseFile
        case confirm(Backup)
    }

    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    /// Nach dem Bestätigen der Erfolgsmeldung.
    let onRestored: (RestoreResult) -> Void

    @State private var autoBackups: [AppModel.AutoBackupFile] = []
    @State private var showingList = false
    @State private var importing = false
    @State private var next: Next?
    @State private var pending: Backup?
    @State private var result: RestoreResult?
    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, presented in
                if presented { Task { await start() } }
            }
            .sheet(isPresented: $showingList, onDismiss: continueAfterList) {
                AutoBackupList(backups: autoBackups,
                               chooseFile: { next = .chooseFile; showingList = false },
                               picked: { next = .confirm($0); showingList = false })
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { read($0) }
            .confirmationDialog("Restore Backup?", isPresented: Binding(get: { pending != nil },
                                                                        set: { if !$0 { pending = nil } }),
                                titleVisibility: .visible, presenting: pending) { backup in
                Button("Restore") { restore(backup) }
                Button("Cancel", role: .cancel) {}
            } message: { backup in
                Text("Backup from \(backup.createdAt.formatted(date: .abbreviated, time: .shortened)). Entries that still exist are kept; only missing ones are added again.")
            }
            .alert("Backup Restored", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } }),
                   presenting: result) { result in
                Button("OK") { onRestored(result) }
            } message: { result in
                Text(message(result))
            }
            .alert("Couldn't Read Backup", isPresented: Binding(get: { failure != nil },
                                                               set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
    }

    private func start() async {
        // Gleich herunterladen lassen, was nur als iCloud-Platzhalter da ist.
        let backups = await Task.detached(priority: .userInitiated) { AppModel.downloadAutoBackups() }.value
        isPresented = false
        autoBackups = backups
        if backups.isEmpty { importing = true } else { showingList = true }
    }

    private func continueAfterList() {
        switch next {
        case .chooseFile: importing = true
        case .confirm(let backup): pending = backup
        case nil: break
        }
        next = nil
    }

    private func read(_ picked: Result<URL, Error>) {
        do {
            let url = try picked.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            pending = try Backup.decode(Data(contentsOf: url))
        } catch let error as BackupError {
            failure = error.localizedDescription
        } catch is DecodingError {
            failure = BackupError.notABackup.localizedDescription
        } catch let error as CocoaError where error.code == .userCancelled {
            // Auswahl abgebrochen.
        } catch {
            failure = error.localizedDescription
        }
    }

    private func restore(_ backup: Backup) {
        result = model.repository.restore(backup, personalCalendarName: String(localized: "My Calendar"))
        model.save()
        model.refreshAfterSync()
    }

    private func message(_ result: RestoreResult) -> String {
        var text = String(localized: "\(result.created) entries added, \(result.skipped) already existed.")
        if !result.newFamilies.isEmpty {
            text += "\n" + String(localized: "Created again with you as owner: \(result.newFamilies.formatted(.list(type: .and))).")
        }
        return text
    }
}

extension View {
    /// Zeigt bei `isPresented` die automatischen Backups bzw. die Dateiauswahl und spielt das
    /// gewählte Backup nach Rückfrage ein.
    func backupRestore(isPresented: Binding<Bool>, onRestored: @escaping (RestoreResult) -> Void = { _ in }) -> some View {
        modifier(BackupRestore(isPresented: isPresented, onRestored: onRestored))
    }
}

/// Die automatischen Backups, neuestes zuerst; jedes lässt sich auch als Datei teilen.
private struct AutoBackupList: View {
    let backups: [AppModel.AutoBackupFile]
    let chooseFile: () -> Void
    let picked: (Backup) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var loading: AppModel.AutoBackupFile?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(backups) { backup in
                        row(backup)
                    }
                } header: {
                    Text("Automatic Backups")
                } footer: {
                    Text("Saved weekly, the last five are kept. They are stored with yafo in iCloud and don't appear in the Files app. To keep one as a file, share it.")
                }

                if let failure {
                    Section {
                        Label(failure, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Choose File…", systemImage: "doc", action: chooseFile)
                }
            }
            .navigationTitle("Restore Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .disabled(loading != nil)
        }
    }

    private func row(_ backup: AppModel.AutoBackupFile) -> some View {
        HStack {
            Button {
                Task { await load(backup) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(backup.date.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.primary)
                    Text(backup.date, format: .relative(presentation: .named))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.borderless)

            if loading == backup {
                ProgressView()
            } else {
                ShareLink(item: backup.url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func load(_ backup: AppModel.AutoBackupFile) async {
        loading = backup
        failure = nil
        defer { loading = nil }
        do {
            let read = try await Task.detached(priority: .userInitiated) { try AppModel.readAutoBackup(backup) }.value
            picked(read)
        } catch let error as BackupError {
            failure = error.localizedDescription
        } catch is DecodingError {
            failure = BackupError.notABackup.localizedDescription
        } catch {
            failure = error.localizedDescription
        }
    }
}
