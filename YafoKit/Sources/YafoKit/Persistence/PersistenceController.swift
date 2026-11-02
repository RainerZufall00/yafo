import CloudKit
import CoreData
import Foundation

/// Core Data mit drei Stores:
/// - `privateStore`: private CloudKit-Datenbank. Eigener Kalender, private Listen, eigene
///   Einstellungen und alle Familien, deren Owner man ist.
/// - `sharedStore`: geteilte CloudKit-Datenbank. Familien, in die man eingeladen wurde.
/// - `localStore`: Abo-Cache, nie synchronisiert.
///
/// Welcher Store ein Objekt enthält, entscheidet, wer es sieht.
public final class PersistenceController {
    public enum Mode: Sendable {
        /// Synchronisiert mit iCloud über den angegebenen Container.
        case cloudKit(containerIdentifier: String, directory: URL)
        /// Nur lokal, z. B. ohne iCloud-Account, in Previews und Tests.
        case local(directory: URL)
    }

    public static let containerIdentifier = "iCloud.de.yafo.app"
    public static let appGroupIdentifier = "group.de.yafo.app"

    public let container: NSPersistentCloudKitContainer
    public let mode: Mode
    public private(set) var privateStore: NSPersistentStore!
    public private(set) var sharedStore: NSPersistentStore!
    public private(set) var localStore: NSPersistentStore!

    public var viewContext: NSManagedObjectContext { container.viewContext }

    public var cloudContainerIdentifier: String? {
        if case .cloudKit(let identifier, _) = mode { identifier } else { nil }
    }

    public init(mode: Mode) throws {
        self.mode = mode
        container = NSPersistentCloudKitContainer(name: "yafo", managedObjectModel: YafoModel.shared)

        let directory: URL
        switch mode {
        case .cloudKit(_, let dir), .local(let dir): directory = dir
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let descriptions = [
            Self.description(directory, "private", YafoModel.cloudConfiguration, mode, .private),
            Self.description(directory, "shared", YafoModel.cloudConfiguration, mode, .shared),
            Self.description(directory, "local", YafoModel.localConfiguration, mode, nil)
        ]
        container.persistentStoreDescriptions = descriptions

        var loadError: Error?
        container.loadPersistentStores { _, error in
            if let error { loadError = error }
        }
        if let loadError { throw loadError }

        let coordinator = container.persistentStoreCoordinator
        privateStore = coordinator.persistentStore(for: descriptions[0].url!)
        sharedStore = coordinator.persistentStore(for: descriptions[1].url!)
        localStore = coordinator.persistentStore(for: descriptions[2].url!)

        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        viewContext.transactionAuthor = "app"
    }

    /// Standard für die App: iCloud, sofern ein Account angemeldet ist, Daten in der App Group,
    /// damit Widget und Share Extension sie lesen können.
    public static func makeDefault(forceLocal: Bool = false) throws -> PersistenceController {
        let directory = defaultDirectory()
        if !forceLocal, FileManager.default.ubiquityIdentityToken != nil {
            return try PersistenceController(mode: .cloudKit(containerIdentifier: containerIdentifier,
                                                              directory: directory))
        }
        return try PersistenceController(mode: .local(directory: directory))
    }

    /// Leerer Controller in einem temporären Ordner, für Tests und Previews.
    public static func makeTemporary() throws -> PersistenceController {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "yafo-\(UUID().uuidString)", directoryHint: .isDirectory)
        return try PersistenceController(mode: .local(directory: directory))
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
            ?? URL.applicationSupportDirectory
        return base.appending(path: "Stores", directoryHint: .isDirectory)
    }

    private static func description(_ directory: URL, _ name: String, _ configuration: String,
                                    _ mode: Mode, _ scope: CKDatabase.Scope?) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: directory.appending(path: "\(name).sqlite"))
        description.configuration = configuration
        description.shouldAddStoreAsynchronously = false
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        if let scope, case .cloudKit(let identifier, _) = mode {
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: identifier)
            options.databaseScope = scope
            description.cloudKitContainerOptions = options
        }
        return description
    }

    // MARK: - Stores

    /// Der Store, in dem ein Objekt liegt. Neue Objekte bekommen ihn über `assign`.
    public func store(of object: NSManagedObject) -> NSPersistentStore {
        object.objectID.persistentStore ?? privateStore
    }

    /// `true`, wenn das Objekt in einer Familie liegt, in die man eingeladen wurde.
    public func isInSharedStore(_ object: NSManagedObject) -> Bool {
        object.objectID.persistentStore == sharedStore
    }

    public func save() throws {
        if viewContext.hasChanges {
            try viewContext.save()
        }
    }
}
