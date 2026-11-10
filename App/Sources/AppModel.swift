import CloudKit
import CoreData
import Observation
import SwiftUI
import WidgetKit
import YafoKit

/// Zentraler Zustand der App: Stores, Repository, Sharing und die eigene CloudKit-User-ID.
@Observable
final class AppModel {
    static let shared = AppModel()

    let persistence: PersistenceController
    let repository: Repository
    let sharing: FamilySharing
    let external = ExternalCalendars()

    /// Record-Name des eigenen Apple Accounts, `nil` ohne iCloud.
    private(set) var userID: String?
    /// Familien, denen man beigetreten ist, ohne dort schon ein Profil zu haben.
    private(set) var familiesNeedingProfile: [Family] = []
    var errorMessage: String?
    /// Onboarding oder „Beitreten per Code“ fragen selbst nach dem Profil; `RootView` hält sich dann zurück.
    var joinHandledElsewhere = false
    /// Zuletzt per Einladung übernommenes Kinderprofil; der Beitritt per Code wartet darauf.
    private(set) var claimedProfile: Member?
    /// Gewählte Liste in Einkauf und Todos: `id` der Familie oder „personal“ für „Nur ich“.
    var listScopeKey: String = UserDefaults.standard.string(forKey: "listScope") ?? "" {
        didSet {
            UserDefaults.standard.set(listScopeKey, forKey: "listScope")
            // Nicht eingerichtete Listen-Widgets folgen der zuletzt gewählten Liste.
            refreshDerivedData()
        }
    }

    /// Gewählter Tab; wird gemerkt, damit „Zuletzt geöffnet“ auch nach einem Neustart greift.
    var selectedTab: AppTab = AppModel.initialTab {
        didSet { UserDefaults.standard.set(selectedTab.rawValue, forKey: "selectedTab") }
    }
    /// Zählt hoch, wenn der Kalender auf „heute“ zurückspringen soll (Tipp aufs Widget).
    private(set) var calendarResetRequest = 0
    private var backgroundSince: Date?
    private var lastDeepLink: Date?

    private static var initialTab: AppTab {
        LaunchTab.current.tab
            ?? UserDefaults.standard.string(forKey: "selectedTab").flatMap(AppTab.init(rawValue:))
            ?? .calendar
    }

    private var started = false
    private var reminderTask: Task<Void, Never>?

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
        // Legt alle Record-Typen und Felder in der Development-Umgebung von CloudKit an, auch
        // solche, die noch nie gespeichert wurden. Danach im CloudKit Console das Schema nach
        // Production übernehmen, sonst scheitert die Synchronisierung in TestFlight.
        if arguments.contains("-yafoInitCloudKitSchema"), persistence.cloudContainerIdentifier != nil {
            do {
                try persistence.container.initializeCloudKitSchema(options: [])
                print("CloudKit-Schema angelegt")
            } catch {
                print("CloudKit-Schema fehlgeschlagen: \(error)")
            }
        }
        #endif
    }

    func start() async {
        guard !started else { return }
        started = true
        userID = await sharing.currentUserID()
        // Die Share Extension braucht die ID für „Erstellt von“, kann CloudKit aber nicht fragen.
        UserDefaults(suiteName: PersistenceController.appGroupIdentifier)?.set(userID, forKey: "userID")
        await ReminderScheduler.requestAuthorization()
        refreshAfterSync()
        processInbox()
        Task { await refreshSubscriptions() }
        Task { await autoBackupIfDue() }

        // Änderungen aus iCloud (auch per Silent Push) kommen als Remote-Change-Notification.
        for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
            mergeShareExtensionChanges()
            refreshAfterSync()
        }
    }

    // MARK: - Navigation

    /// `yafo://calendar`, `yafo://shopping?list=<key>`, `yafo://todos?list=<key>` (Widgets).
    func open(_ url: URL) {
        guard let tab = DeepLink.tab(for: url) else { return }
        lastDeepLink = .now
        selectedTab = tab
        if tab == .calendar { calendarResetRequest += 1 }
        if let list = DeepLink.list(in: url) { listScopeKey = list }
    }

    func didEnterBackground() {
        backgroundSince = .now
    }

    /// Nach längerer Pause mit dem eingestellten Tab weitermachen, außer ein Link
    /// (z. B. vom Widget) hat gerade selbst einen Tab gewählt.
    func didBecomeActive() {
        mergeShareExtensionChanges()
        // Ohne User-ID erkennt die App das eigene Profil nicht und fragt nach dem Beitritt nicht
        // danach (z. B. iCloud beim Start noch nicht bereit). Dann bei jeder Rückkehr neu fragen.
        if started, userID == nil, sharing.isAvailable {
            Task {
                userID = await sharing.currentUserID()
                if userID != nil { refreshAfterSync() }
            }
        }
        defer { backgroundSince = nil }
        guard let backgroundSince, let tab = LaunchTab.current.tab,
              Date.now.timeIntervalSince(backgroundSince) >= LaunchTab.backgroundThreshold else { return }
        if let lastDeepLink, Date.now.timeIntervalSince(lastDeepLink) < 2 { return }
        selectedTab = tab
    }

    /// Termine, die die Share Extension angelegt hat, in die Ansichten holen und Erinnerungen
    /// sowie Widgets nachziehen.
    func mergeShareExtensionChanges() {
        if persistence.mergeExternalChanges() > 0 { refreshDerivedData() }
    }

    func refreshAfterSync() {
        repository.mergeDuplicatePersonalCalendars()
        if let userID {
            repository.claimOwnerProfiles(userID: userID)
            claimInvitedProfiles(userID: userID)
        }
        save()
        // Familien, deren Mitglieder noch nicht aus iCloud da sind, erst danach anbieten; sonst
        // fragt die App ein eingeladenes Kind nach einem Namen, bevor sein Profil angekommen ist.
        familiesNeedingProfile = repository.familiesNeedingProfile(userID: userID)
            .filter { !($0.members ?? []).isEmpty }
    }

    /// Wurde die Einladung für ein Kinderprofil ausgestellt, übernimmt man es ohne Nachfrage.
    private func claimInvitedProfiles(userID: String) {
        for family in repository.familiesNeedingProfile(userID: userID) {
            guard let profile = sharing.invitedProfile(in: family) else { continue }
            repository.join(family, userID: userID, name: "", linking: profile)
            profile.inviteParticipantID = nil
            claimedProfile = profile
        }
    }

    /// Erledigt, was Widgets (Abhaken) in der App Group abgelegt haben. Läuft beim Start und bei
    /// jeder Rückkehr in den Vordergrund.
    func processInbox() {
        let inbox = AppGroupInbox()
        guard !inbox.pending().isEmpty, let entries = try? inbox.drain() else { return }
        let result = repository.apply(entries)
        if result.changedSomething || result.skipped > 0 { save() }
    }

    func accept(_ metadata: CKShare.Metadata) async {
        do {
            try await sharing.accept(metadata)
            refreshAfterSync()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Beitritt per gescanntem QR-Code oder eingefügtem Link; Fehler zeigt die aufrufende Ansicht.
    func accept(inviteURL: URL) async throws {
        try await sharing.accept(inviteURL: inviteURL)
        refreshAfterSync()
    }

    /// Familie löschen (Owner) oder verlassen (Mitglied); Fehler zeigt die aufrufende Ansicht.
    func remove(_ family: Family) async throws {
        if family.id?.uuidString == listScopeKey { listScopeKey = "" }
        try await sharing.remove(family, me: me(in: family))
        refreshAfterSync()
    }

    /// Alle eigenen Daten löschen, auch in iCloud; Familien anderer Owner bleiben. Danach beginnt die
    /// App wieder mit dem Onboarding, statt leer dazustehen.
    func deleteAllOwnData() {
        listScopeKey = ""
        repository.deleteAllOwnData()
        save()
        refreshAfterSync()
        UserDefaults.standard.set(false, forKey: OnboardingView.doneKey)
    }

    func save() {
        do {
            try repository.save()
        } catch {
            errorMessage = error.localizedDescription
        }
        refreshDerivedData()
    }

    /// Plant Erinnerungen neu und aktualisiert die Widgets, gebündelt: mehrere Änderungen
    /// kurz hintereinander lösen das nur einmal aus.
    func refreshDerivedData() {
        reminderTask?.cancel()
        reminderTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            try? repository.widgetSnapshot(listKey: listScopeKey.isEmpty ? nil : listScopeKey).write()
            WidgetCenter.shared.reloadAllTimelines()
            let reminders = repository.plannedReminders(me: { self.me(in: $0) })
            await ReminderScheduler.replace(with: reminders)
        }
    }

    // MARK: - Abgeleitete Werte für die Oberfläche

    func me(in family: Family?) -> Member? {
        guard let family else { return nil }
        if let userID { return repository.me(in: family, userID: userID) }
        // Ohne iCloud (lokal, Demo): in eigenen Familien das älteste Erwachsenen-Profil.
        guard isOwner(of: family) else { return nil }
        return repository.activeMembers(of: family).first { $0.kind == .adult }
    }

    /// Wer angelegt hat: im Familienkalender die eigene Member-ID, sonst die User-ID.
    func creatorID(for calendar: EventCalendar) -> String? {
        me(in: calendar.family)?.id?.uuidString ?? userID
    }

    /// Liste für Einkauf und Todos; ohne gültige Wahl die erste Familie, sonst „Nur ich“.
    func listScope(families: some Collection<Family>) -> ListScope {
        if listScopeKey == "personal" { return .personal }
        if let family = families.first(where: { $0.id?.uuidString == listScopeKey }) ?? families.first {
            return .family(family)
        }
        return .personal
    }

    func isOwner(of family: Family) -> Bool {
        sharing.isOwner(of: family)
    }
}
