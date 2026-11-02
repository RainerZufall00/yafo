import CloudKit
import CoreData
import Observation
import SwiftUI
import YafoKit

/// Zentraler Zustand der App: Stores, Repository, Sharing und die eigene CloudKit-User-ID.
@Observable
final class AppModel {
    static let shared = AppModel()

    let persistence: PersistenceController
    let repository: Repository
    let sharing: FamilySharing

    /// Record-Name des eigenen Apple Accounts, `nil` ohne iCloud.
    private(set) var userID: String?
    /// Familien, denen man beigetreten ist, ohne dort schon ein Profil zu haben.
    private(set) var familiesNeedingProfile: [Family] = []
    var errorMessage: String?

    private var started = false

    private init() {
        let arguments = ProcessInfo.processInfo.arguments
        do {
            persistence = arguments.contains("-yafoInMemory")
                ? try PersistenceController.makeTemporary()
                : try PersistenceController.makeDefault(forceLocal: arguments.contains("-yafoLocalOnly"))
        } catch {
            fatalError("Stores konnten nicht geladen werden: \(error)")
        }
        repository = Repository(persistence: persistence)
        sharing = FamilySharing(persistence: persistence)
        repository.ensurePersonalCalendar(name: String(localized: "My Calendar"))
        try? repository.save()
        #if DEBUG
        if arguments.contains("-yafoDemoData") {
            DemoData.seedIfNeeded(repository)
        }
        #endif
    }

    func start() async {
        guard !started else { return }
        started = true
        userID = await sharing.currentUserID()
        refreshAfterSync()

        // Änderungen aus iCloud (auch per Silent Push) kommen als Remote-Change-Notification.
        for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
            refreshAfterSync()
        }
    }

    func refreshAfterSync() {
        repository.mergeDuplicatePersonalCalendars()
        save()
        familiesNeedingProfile = repository.familiesNeedingProfile(userID: userID)
    }

    func accept(_ metadata: CKShare.Metadata) async {
        do {
            try await sharing.accept(metadata)
            refreshAfterSync()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() {
        do {
            try repository.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Abgeleitete Werte für die Oberfläche

    func me(in family: Family?) -> Member? {
        family.flatMap { repository.me(in: $0, userID: userID) }
    }

    /// Wer angelegt hat: im Familienkalender die eigene Member-ID, sonst die User-ID.
    func creatorID(for calendar: EventCalendar) -> String? {
        me(in: calendar.family)?.id?.uuidString ?? userID
    }

    func isOwner(of family: Family) -> Bool {
        sharing.isOwner(of: family)
    }
}
