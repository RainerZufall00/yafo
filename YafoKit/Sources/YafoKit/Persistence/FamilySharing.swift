import CloudKit
import CoreData
import Foundation

/// Einladen und Beitreten über CloudKit-Sharing. Jede Familie ist ein eigener `CKShare`;
/// alles, was an der Familie hängt, wird mitgeteilt.
public final class FamilySharing {
    public enum SharingError: LocalizedError {
        case cloudUnavailable
        case notOwner

        public var errorDescription: String? {
            switch self {
            case .cloudUnavailable: "iCloud is not available."
            case .notOwner: "Only the owner can invite members."
            }
        }
    }

    public let persistence: PersistenceController

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    public var isAvailable: Bool { persistence.cloudContainerIdentifier != nil }

    public var ckContainer: CKContainer? {
        persistence.cloudContainerIdentifier.map(CKContainer.init(identifier:))
    }

    /// Owner ist, wessen privater Store die Familie enthält.
    public func isOwner(of family: Family) -> Bool {
        !persistence.isInSharedStore(family)
    }

    /// Record-Name des angemeldeten Apple Accounts, Grundlage für `Member.cloudKitUserID`.
    public func currentUserID() async -> String? {
        guard let ckContainer else { return nil }
        return try? await ckContainer.userRecordID().recordName
    }

    public func existingShare(for family: Family) throws -> CKShare? {
        guard isAvailable else { return nil }
        return try persistence.container.fetchShares(matching: [family.objectID])[family.objectID]
    }

    /// Vorhandenen Share liefern oder neu anlegen. Nur der Owner lädt ein.
    public func share(for family: Family) async throws -> CKShare {
        guard isAvailable else { throw SharingError.cloudUnavailable }
        guard isOwner(of: family) else { throw SharingError.notOwner }
        if let share = try existingShare(for: family) {
            return share
        }
        try persistence.save()
        let (_, share, _) = try await persistence.container.share([family], to: nil)
        share[CKShare.SystemFieldKey.title] = family.name
        // Alle Erwachsenen bekommen Schreibrechte; eine Rechte-Auswahl gibt es in V1 nicht.
        share.publicPermission = .none
        try await persistence.container.persistUpdatedShare(share, in: persistence.privateStore)
        return share
    }

    /// Einladungslink angenommen: Familiendaten erscheinen im geteilten Store.
    public func accept(_ metadata: CKShare.Metadata) async throws {
        guard isAvailable else { throw SharingError.cloudUnavailable }
        _ = try await persistence.container.acceptShareInvitations(from: [metadata],
                                                                   into: persistence.sharedStore)
    }
}
