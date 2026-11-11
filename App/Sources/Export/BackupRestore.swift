import SwiftUI
import UniformTypeIdentifiers
import YafoKit

/// Backup einspielen: Datei wählen, nachfragen, wiederherstellen, Ergebnis zeigen. Als Modifier,
/// damit Onboarding, „Familie“ und „Export & Backup“ denselben Ablauf nutzen.
private struct BackupRestore: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    /// Nach dem Bestätigen der Erfolgsmeldung.
    let onRestored: (RestoreResult) -> Void

    @State private var pending: Backup?
    @State private var result: RestoreResult?
    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.json]) { read($0) }
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
    /// Zeigt bei `isPresented` die Dateiauswahl für ein yafo-Backup und spielt es nach Rückfrage ein.
    func backupRestore(isPresented: Binding<Bool>, onRestored: @escaping (RestoreResult) -> Void = { _ in }) -> some View {
        modifier(BackupRestore(isPresented: isPresented, onRestored: onRestored))
    }
}
