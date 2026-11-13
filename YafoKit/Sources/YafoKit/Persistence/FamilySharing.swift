import CloudKit
import CoreData
import Foundation
import os

/// Einladen und Beitreten über CloudKit-Sharing. Jede Familie ist ein eigener `CKShare`;
/// alles, was an der Familie hängt, wird mitgeteilt.
public final class FamilySharing {
    public enum SharingError: LocalizedError {
        case cloudUnavailable
        case notOwner
        case noInviteCode
        case ownFamily
        case alreadyMember
        case inviteWithdrawn
        case shareMissingInCloud
        /// Annehmen scheiterte; enthält den eigentlichen Grund aus CloudKit, den Core Data nur als
        /// „Failed to accept some shares“ meldet.
        case acceptFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noInviteCode: "iCloud did not return an invitation code."
            case .ownFamily: "This is your own family."
            case .alreadyMember: "You are already a member of this family."
            case .cloudUnavailable: "iCloud is not available."
            case .notOwner: "Only the owner can invite members."
            case .inviteWithdrawn: "This invitation was withdrawn. Ask for a new QR code."
            case .shareMissingInCloud:
                "This family is not in iCloud. Export a backup, reinstall yafo and restore the backup."
            case .acceptFailed(let reason): "The invitation could not be accepted. \(reason)"
            }
        }
    }

    public let persistence: PersistenceController

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    private var cloud: CloudCalls {
        CloudCalls(container: persistence.container, privateStore: persistence.privateStore,
                   sharedStore: persistence.sharedStore)
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
        if let share = try await cloud.existingShare(for: family.objectID) {
            return share
        }
        try persistence.save()
        let share = try await cloud.share(Unchecked(value: [family]))
        share[CKShare.SystemFieldKey.title] = family.name
        // Alle Erwachsenen bekommen Schreibrechte; eine Rechte-Auswahl gibt es in V1 nicht.
        share.publicPermission = .none
        try await cloud.persistUpdatedShare(share)
        return share
    }

    /// Vorname, mit dem man zur Familie eingeladen wurde (aus dem Apple Account), als Vorschlag
    /// für das eigene Profil.
    public func invitedName(in family: Family) -> String? {
        guard let share = try? existingShare(for: family),
              let name = share.currentUserParticipant?.userIdentity.nameComponents else { return nil }
        let given = name.givenName ?? name.nickname
        return given ?? PersonNameComponentsFormatter.localizedString(from: name, style: .short)
    }

    // MARK: - Einladung per Code (QR)

    /// Einmal-Link für genau eine Person, gedacht als QR-Code. Der Share bleibt privat
    /// (`publicPermission == .none`); wer den Code zuerst scannt, übernimmt den Platz mit Schreibrecht.
    /// - Parameters:
    ///   - child: Kinderprofil, für das die Einladung gilt (Kind mit eigenem Gerät). Der Link wird am
    ///     Profil vermerkt; wer damit beitritt, übernimmt es samt Terminen und Todos. `nil` lädt einen
    ///     Erwachsenen ein, der sein Profil selbst anlegt.
    ///   - fresh: `true` verwirft den noch nicht eingelösten Code und legt einen neuen an,
    ///     sonst wird ein offener Code wiederverwendet.
    public func inviteCode(for family: Family, child: Member? = nil, fresh: Bool = false) async throws -> URL {
        guard let ckContainer else { throw SharingError.cloudUnavailable }
        let local = try await share(for: family)
        let database = ckContainer.privateCloudDatabase
        // Der Stand in Core Data kann veraltet sein (jemand ist inzwischen beigetreten).
        let share: CKShare
        do {
            share = try await database.record(for: local.recordID) as? CKShare ?? local
        } catch let error as CKError where Self.missingOnServer.contains(error.code) {
            // Lokal geteilt, in iCloud aber unbekannt, z. B. Daten aus einem Xcode-Build
            // (Development) nach dem Wechsel auf TestFlight (Production). Ein Code daraus wäre
            // nie einlösbar („Share not found“).
            throw SharingError.shareMissingInCloud
        } catch {
            share = local
        }

        // Offene Codes gehören entweder zu einem Kinderprofil oder sind für Erwachsene.
        let reserved = Set((family.members ?? []).compactMap(\.inviteParticipantID))
        let open = share.participants.filter { participant in
            guard Self.isOpenCode(participant, in: share) else { return false }
            if let child { return participant.participantID == child.inviteParticipantID }
            return !reserved.contains(participant.participantID)
        }
        if !fresh, let participant = open.first, let url = share.oneTimeURL(for: participant.participantID) {
            return url
        }
        open.forEach(share.removeParticipant)
        let before = Set(share.participants.map(\.participantID))
        let participant = CKShare.Participant.oneTimeURLParticipant()
        participant.permission = .readWrite
        share.addParticipant(participant)

        let (saved, _) = try await database.modifyRecords(saving: [share], deleting: [])
        guard let savedShare = try saved[share.recordID]?.get() as? CKShare else {
            throw SharingError.noInviteCode
        }
        // Falls der Server dem neuen Platz eine andere ID gibt als die lokal erzeugte.
        let participantID = savedShare.oneTimeURL(for: participant.participantID) != nil
            ? participant.participantID
            : savedShare.participants.map(\.participantID).first { !before.contains($0) }
        guard let participantID, let url = savedShare.oneTimeURL(for: participantID) else {
            throw SharingError.noInviteCode
        }
        try await cloud.persistUpdatedShare(savedShare)
        if let child {
            child.inviteParticipantID = participantID
            try persistence.save()
        }
        return url
    }

    /// Kinderprofil, für das die eigene Einladung ausgestellt wurde (siehe `inviteCode(for:child:fresh:)`).
    public func invitedProfile(in family: Family) -> Member? {
        guard let share = try? existingShare(for: family),
              let participantID = share.currentUserParticipant?.participantID else { return nil }
        return family.members?.first {
            $0.inviteParticipantID == participantID && $0.leftAt == nil && $0.cloudKitUserID == nil
        }
    }

    private static let missingOnServer: Set<CKError.Code> = [.unknownItem, .zoneNotFound, .userDeletedZone]

    /// Noch nicht eingelöster Einmal-Link: wartend und ohne bekannte Person dahinter.
    private static func isOpenCode(_ participant: CKShare.Participant, in share: CKShare) -> Bool {
        participant.acceptanceStatus == .pending
            && participant.userIdentity.lookupInfo == nil
            && share.oneTimeURL(for: participant.participantID) != nil
    }

    /// Prüft, ob ein gescannter oder eingefügter Text ein iCloud-Einladungslink sein kann.
    /// Alles andere wird gar nicht erst an CloudKit gegeben.
    public static func inviteURL(from text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host()?.lowercased(),
              host == "icloud.com" || host.hasSuffix(".icloud.com"),
              url.path().hasPrefix("/share") else { return nil }
        return url
    }

    /// Beitritt aus der App heraus (QR-Code gescannt oder Link eingefügt).
    public func accept(inviteURL: URL) async throws {
        guard let ckContainer else { throw SharingError.cloudUnavailable }
        let metadata = try await ckContainer.shareMetadata(for: inviteURL)
        guard metadata.participantRole != .owner else { throw SharingError.ownFamily }
        guard metadata.participantStatus != .accepted else { throw SharingError.alreadyMember }
        guard metadata.participantStatus != .removed else { throw SharingError.inviteWithdrawn }
        try await accept(metadata)
    }

    // MARK: - Löschen und Verlassen

    /// Owner: Familie mit allen Daten löschen, auch aus iCloud und bei allen Mitgliedern.
    /// Mitglied: die Familie verlassen; das eigene Profil bleibt als „ehemalig“ erhalten, damit
    /// Termine und Kommentare der anderen lesbar bleiben.
    public func remove(_ family: Family, me: Member?) async throws {
        let repository = Repository(persistence: persistence)
        guard let share = try await cloud.existingShare(for: family.objectID) else {
            // Nie geteilt (oder ohne iCloud): nur lokal löschen, der Sync räumt den Rest ab.
            repository.deleteFamily(family)
            try persistence.save()
            return
        }
        if isOwner(of: family) {
            repository.deleteFamily(family)
            try persistence.save()
            // Die Löschung synchronisiert ohnehin (mit dem Familien-Record fällt auch der Share); die
            // Zone gleich mit abzuräumen ist nur Aufräumen und darf offline scheitern.
            try? await cloud.purgeZone(share.recordID.zoneID, shared: false)
        } else {
            if let me { repository.markLeft(me) }
            try persistence.save()
            // Im geteilten Store entfernt das den eigenen Platz im Share und die lokale Kopie.
            try await cloud.purgeZone(share.recordID.zoneID, shared: true)
        }
        persistence.viewContext.refreshAllObjects()
    }

    /// Einladungslink angenommen: Familiendaten erscheinen im geteilten Store.
    public func accept(_ metadata: CKShare.Metadata) async throws {
        guard isAvailable else { throw SharingError.cloudUnavailable }
        do {
            try await cloud.accept(metadata)
        } catch {
            Self.log.error("Einladung annehmen fehlgeschlagen: \(String(describing: error), privacy: .public)")
            throw SharingError.acceptFailed(Self.reason(for: error))
        }
    }

    private static let log = Logger(subsystem: "de.yafo.app", category: "sharing")

    /// Lesbarer Grund für einen gescheiterten Beitritt. Core Data verpackt die CloudKit-Fehler
    /// (oft als Teilfehler je Share), deshalb wird bis zum ersten `CKError` ausgepackt.
    static func reason(for error: Error) -> String {
        let leaves = leafErrors(of: error as NSError)
        guard let ck = leaves.first(where: { $0.domain == CKError.errorDomain }) else {
            let detail = leaves.first ?? error as NSError
            return "\(detail.localizedDescription) (\(detail.domain) \(detail.code))"
        }
        let hint: String = switch CKError.Code(rawValue: ck.code) {
        case .notAuthenticated: "Please sign in to iCloud in Settings."
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            "iCloud cannot be reached right now. Please try again in a moment."
        case .unknownItem, .zoneNotFound, .userDeletedZone:
            "The family no longer exists or the code has expired. Ask for a new QR code."
        case .permissionFailure, .participantMayNeedVerification:
            "The code has already been used or was withdrawn. Ask for a new QR code."
        case .quotaExceeded: "The iCloud storage of the family owner is full."
        case .incompatibleVersion: "Please update yafo on both devices."
        default: ck.localizedDescription
        }
        return "\(hint) (CKError \(ck.code))"
    }

    /// Alle innersten Fehler, auch aus Teilfehlern und Fehlerlisten.
    private static func leafErrors(of error: NSError, depth: Int = 0) -> [NSError] {
        guard depth < 6 else { return [error] }
        var children = error.underlyingErrors.map { $0 as NSError }
        if let details = error.userInfo["NSDetailedErrors"] as? [Error] {
            children += details.map { $0 as NSError }
        }
        if let partial = error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            children += partial.values.map { $0 as NSError }
        }
        guard !children.isEmpty else { return [error] }
        return children.flatMap { leafErrors(of: $0, depth: depth + 1) }
    }
}

/// Wert, der ohne Prüfung des Compilers über Threads gereicht wird. Nur für Objekte, die der
/// Empfänger nicht anfasst, sondern an Core Data weitergibt.
nonisolated struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
}

/// Die CloudKit-Aufrufe von `NSPersistentCloudKitContainer` warten intern synchron, bis der Sync
/// sie annimmt (`_PFRequestExecutor wait`). Auf dem Main Thread friert das die App ein, solange ein
/// Import oder Export läuft, bis der Watchdog sie beendet (0x8BADF00D beim Tippen auf
/// „Mit QR-Code einladen“). Deshalb laufen sie hier immer im Hintergrund.
nonisolated private struct CloudCalls: @unchecked Sendable {
    let container: NSPersistentCloudKitContainer
    let privateStore: NSPersistentStore
    let sharedStore: NSPersistentStore

    @concurrent func existingShare(for id: NSManagedObjectID) async throws -> CKShare? {
        try container.fetchShares(matching: [id])[id]
    }

    @concurrent func share(_ objects: Unchecked<[NSManagedObject]>) async throws -> CKShare {
        try await container.share(objects.value, to: nil).1
    }

    @concurrent func persistUpdatedShare(_ share: CKShare) async throws {
        try await container.persistUpdatedShare(share, in: privateStore)
    }

    @concurrent func purgeZone(_ zoneID: CKRecordZone.ID, shared: Bool) async throws {
        _ = try await container.purgeObjectsAndRecordsInZone(with: zoneID, in: shared ? sharedStore : privateStore)
    }

    @concurrent func accept(_ metadata: CKShare.Metadata) async throws {
        _ = try await container.acceptShareInvitations(from: [metadata], into: sharedStore)
    }
}
