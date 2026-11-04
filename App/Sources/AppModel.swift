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
    /// Gewählte Liste in Einkauf und Todos: `id` der Familie oder „personal“ für „Nur ich“.
    var listScopeKey: String = UserDefaults.standard.string(forKey: "listScope") ?? "" {
        didSet { UserDefaults.standard.set(listScopeKey, forKey: "listScope") }
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
        Task { await refreshSubscriptions() }
        Task { await autoBackupIfDue() }

        // Änderungen aus iCloud (auch per Silent Push) kommen als Remote-Change-Notification.
        for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
            mergeShareExtensionChanges()
            refreshAfterSync()
        }
    }

    // MARK: - Navigation

    func open(_ url: URL) {
        guard let tab = DeepLink.tab(for: url) else { return }
        lastDeepLink = .now
        selectedTab = tab
        if tab == .calendar { calendarResetRequest += 1 }
    }

    func didEnterBackground() {
        backgroundSince = .now
    }

    /// Nach längerer Pause mit dem eingestellten Tab weitermachen, außer ein Link
    /// (z. B. vom Widget) hat gerade selbst einen Tab gewählt.
    func didBecomeActive() {
        mergeShareExtensionChanges()
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
        if let userID { repository.claimOwnerProfiles(userID: userID) }
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
        refreshDerivedData()
    }

    /// Plant Erinnerungen neu und aktualisiert die Widgets, gebündelt: mehrere Änderungen
    /// kurz hintereinander lösen das nur einmal aus.
    func refreshDerivedData() {
        reminderTask?.cancel()
        reminderTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            try? repository.widgetSnapshot().write()
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
