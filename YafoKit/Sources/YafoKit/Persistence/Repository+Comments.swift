import CoreData
import Foundation

extension Repository {
    /// Kommentare eines Termins, älteste zuerst.
    public func comments(of event: Event) -> [Comment] {
        (event.comments ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// Neuer Kommentar; liegt immer im Store des Termins.
    @discardableResult
    public func addComment(_ text: String, to event: Event, author: Member?) -> Comment {
        let comment = insert(Comment.self, near: event)
        comment.text = text
        comment.event = event
        comment.author = author.flatMap { persistence.store(of: $0) == persistence.store(of: event) ? $0 : nil }
        return comment
    }

    public func edit(_ comment: Comment, text: String) {
        guard comment.text != text else { return }
        comment.text = text
        comment.editedAt = .now
    }

    /// Hat die App die User-ID erst nach dem Anlegen einer Familie bekommen, fehlt sie am
    /// Owner-Profil. Dann gehört das älteste Erwachsenen-Profil ohne Account in eigenen Familien
    /// zum angemeldeten Nutzer.
    public func claimOwnerProfiles(userID: String) {
        for family in families() where !persistence.isInSharedStore(family) && me(in: family, userID: userID) == nil {
            let candidate = activeMembers(of: family).first { $0.kind == .adult && $0.cloudKitUserID == nil }
            candidate?.cloudKitUserID = userID
        }
    }
}
