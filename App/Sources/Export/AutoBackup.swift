import Foundation
import YafoKit

/// Wöchentliches JSON-Backup in den yafo-Ordner in iCloud Drive (ohne iCloud in die lokalen
/// App-Dokumente). Die letzten fünf bleiben liegen.
extension AppModel {
    static let backupInterval: TimeInterval = 7 * 24 * 60 * 60
    nonisolated static let keptBackups = 5

    var autoBackupEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "autoBackup") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoBackup") }
    }

    var lastAutoBackup: Date? {
        get { UserDefaults.standard.object(forKey: "lastAutoBackup") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastAutoBackup") }
    }

    /// Beim Start und beim Wechsel in den Vordergrund; schreibt nur, wenn eine Woche um ist.
    func autoBackupIfDue(now: Date = .now) async {
        guard autoBackupEnabled else { return }
        if let last = lastAutoBackup, now.timeIntervalSince(last) < Self.backupInterval { return }
        guard let data = try? repository.makeBackup(now: now).encoded() else { return }
        let name = Backup.fileName(at: now)
        let written = await Task.detached(priority: .background) {
            Self.writeBackup(data, named: name)
        }.value
        if written { lastAutoBackup = now }
    }

    /// Ordner der automatischen Backups.
    nonisolated static func backupFolder() -> URL {
        let base = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appending(path: "Documents")
            ?? URL.documentsDirectory
        return base.appending(path: "Backups", directoryHint: .isDirectory)
    }

    nonisolated private static func writeBackup(_ data: Data, named name: String) -> Bool {
        let folder = backupFolder()
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appending(path: name), options: .atomic)
            // Älteste löschen; die Namen enthalten das Datum und sortieren sich deshalb richtig.
            let backups = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("yafo-Backup") && $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for old in backups.dropFirst(keptBackups) {
                try? manager.removeItem(at: old)
            }
            return true
        } catch {
            return false
        }
    }
}
