import CloudKit
import CoreData
import Foundation

/// Einladen und Beitreten über CloudKit-Sharing. Jede Familie ist ein eigener `CKShare`;
/// alles, was an der Familie hängt, wird mitgeteilt.
public final class FamilySharing {
    public enum SharingError: LocalizedError {
        case cloudUnavailable
        case notOwner
        case noInviteCode
        case ownFamily
        case alreadyMember

        public var errorDescription: String? {
            switch self {
            case .noInviteCode: "iCloud did not return an invitation code."
            case .ownFamily: "This is your own family."
            case .alreadyMember: "You are already a member of this family."
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
        let share = (try? await database.record(for: local.recordID)) as? CKShare ?? local

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
        try await persistence.container.persistUpdatedShare(savedShare, in: persistence.privateStore)
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
        try await accept(metadata)
    }

    /// Einladungslink angenommen: Familiendaten erscheinen im geteilten Store.
    public func accept(_ metadata: CKShare.Metadata) async throws {
        guard isAvailable else { throw SharingError.cloudUnavailable }
        _ = try await persistence.container.acceptShareInvitations(from: [metadata],
                                                                   into: persistence.sharedStore)
    }
}
