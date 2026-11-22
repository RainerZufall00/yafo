import Foundation
import YafoKit

/// Wöchentliches JSON-Backup, unsichtbar für die Dateien-App: im iCloud-Container außerhalb von
/// `Documents` (synchronisiert, aber nicht in iCloud Drive zu sehen), ohne iCloud in Application
/// Support. Die letzten fünf bleiben liegen; wiederhergestellt wird über die Liste beim
/// Wiederherstellen (`BackupRestore`).
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
    /// Backups aus den früheren, sichtbaren Ordnern werden dabei immer zuerst umgezogen.
    func autoBackupIfDue(now: Date = .now) async {
        let due = autoBackupEnabled
            && (lastAutoBackup.map { now.timeIntervalSince($0) >= Self.backupInterval } ?? true)
        let data: Data? = if due { try? repository.makeBackup(now: now).encoded() } else { nil }
        let name = Backup.fileName(at: now)
        let written = await Task.detached(priority: .background) {
            Self.moveVisibleBackups()
            guard let data else { return false }
            return Self.writeBackup(data, named: name)
        }.value
        if written { lastAutoBackup = now }
    }

    // MARK: Ordner

    /// Ordner der automatischen Backups. Nicht vom Main Thread aus aufrufen: die erste Abfrage
    /// des iCloud-Containers kann dauern.
    nonisolated static func backupFolder() -> URL {
        let base = FileManager.default.url(forUbiquityContainerIdentifier: nil) ?? URL.applicationSupportDirectory
        return base.appending(path: "Backups", directoryHint: .isDirectory)
    }

    /// Frühere Ablageorte, die in der Dateien-App zu sehen waren (bis 1.0.1), und – sobald iCloud
    /// verfügbar ist – der lokale Ordner aus der Zeit ohne iCloud.
    nonisolated private static func formerFolders() -> [URL] {
        var folders = [URL.documentsDirectory.appending(path: "Backups", directoryHint: .isDirectory)]
        if let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            folders.append(container.appending(path: "Documents/Backups", directoryHint: .isDirectory))
            folders.append(URL.applicationSupportDirectory.appending(path: "Backups", directoryHint: .isDirectory))
        }
        return folders
    }

    // MARK: Liste

    /// Ein automatisches Backup. `url` ist der eigentliche Name; liegt die Datei nur als
    /// iCloud-Platzhalter vor (`.Name.icloud`), zeigt `fileURL` auf den Platzhalter.
    nonisolated struct AutoBackupFile: Identifiable, Hashable, Sendable {
        var url: URL
        var fileURL: URL
        var date: Date
        var id: URL { url }
    }

    /// Automatische Backups im Ordner, neuestes zuerst.
    nonisolated static func autoBackups(in folder: URL = backupFolder()) -> [AutoBackupFile] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var byName: [String: AutoBackupFile] = [:]
        for file in files {
            var name = file.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                name = String(name.dropFirst().dropLast(".icloud".count))
            }
            guard let date = Backup.date(fromFileName: name) else { continue }
            let url = folder.appending(path: name)
            // Ist die Datei schon da, gewinnt sie gegenüber einem übrig gebliebenen Platzhalter.
            if byName[name] == nil || file.lastPathComponent == name {
                byName[name] = AutoBackupFile(url: url, fileURL: file, date: date)
            }
        }
        return byName.values.sorted { $0.date > $1.date }
    }

    /// Lädt die Backups aus iCloud herunter, damit Teilen und Wiederherstellen sofort gehen.
    nonisolated static func downloadAutoBackups() -> [AutoBackupFile] {
        let backups = autoBackups()
        for backup in backups where backup.fileURL != backup.url {
            try? FileManager.default.startDownloadingUbiquitousItem(at: backup.url)
        }
        return backups
    }

    /// Liest ein Backup. Der koordinierte Zugriff wartet, bis iCloud die Datei geladen hat.
    nonisolated static func readAutoBackup(_ backup: AutoBackupFile) throws -> Backup {
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: backup.url, options: [], error: &coordinationError) { url in
            result = Result { try Data(contentsOf: url) }
        }
        if let coordinationError { throw coordinationError }
        return try Backup.decode(result.get())
    }

    // MARK: Schreiben, Aufräumen, Umziehen

    nonisolated private static func writeBackup(_ data: Data, named name: String) -> Bool {
        let folder = backupFolder()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try coordinatedWrite(data, to: folder.appending(path: name))
            for old in autoBackups(in: folder).dropFirst(keptBackups) {
                coordinatedDelete(old)
            }
            return true
        } catch {
            return false
        }
    }

    /// Zieht Backups aus den früheren Ordnern in den unsichtbaren um und löscht die leeren Ordner.
    /// Danach bleiben wie gewohnt nur die neuesten fünf.
    nonisolated private static func moveVisibleBackups() {
        let manager = FileManager.default
        let target = backupFolder()
        var moved = false
        for folder in formerFolders() where folder != target && manager.fileExists(atPath: folder.path) {
            for old in autoBackups(in: folder) {
                let destination = target.appending(path: old.url.lastPathComponent)
                do {
                    if !manager.fileExists(atPath: destination.path) {
                        var coordinationError: NSError?
                        var data: Data?
                        NSFileCoordinator().coordinate(readingItemAt: old.url, options: [],
                                                       error: &coordinationError) { data = try? Data(contentsOf: $0) }
                        guard let data else { continue }
                        try manager.createDirectory(at: target, withIntermediateDirectories: true)
                        try coordinatedWrite(data, to: destination)
                    }
                    coordinatedDelete(old)
                    moved = true
                } catch {
                    continue
                }
            }
            if (try? manager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
                try? manager.removeItem(at: folder)
            }
        }
        if moved {
            for old in autoBackups(in: target).dropFirst(keptBackups) {
                coordinatedDelete(old)
            }
        }
    }

    nonisolated private static func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
            do { try data.write(to: url, options: .atomic) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    nonisolated private static func coordinatedDelete(_ backup: AutoBackupFile) {
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: backup.fileURL, options: .forDeleting,
                                       error: &coordinationError) { url in
            try? FileManager.default.removeItem(at: url)
        }
    }
}
