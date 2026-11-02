import Foundation
import Testing
@testable import YafoKit

@Suite struct CommentTests {
    let persistence: PersistenceController
    let repository: Repository

    init() throws {
        persistence = try PersistenceController.makeTemporary()
        repository = Repository(persistence: persistence)
    }

    @Test func commentsBelongToTheEventStoreAndKeepOrder() throws {
        let family = repository.insert(Family.self, into: persistence.sharedStore)
        let me = repository.addMember(name: "Ben", kind: .adult, userID: "ben", to: family)
        let calendar = repository.addSharedCalendar(name: "F", to: family)
        let event = repository.createEvent(title: "Zoo", start: .now, end: .now, isAllDay: false,
                                           in: calendar, createdBy: nil)
        let first = repository.addComment("Wer bringt Snacks?", to: event, author: me)
        let second = repository.addComment("Ich!", to: event, author: me)
        try repository.save()

        #expect(repository.comments(of: event) == [first, second])
        #expect(persistence.store(of: first) == persistence.sharedStore)
        #expect(first.author == me)
    }

    @Test func editingSetsEditedAt() {
        let calendar = repository.ensurePersonalCalendar(name: "Ich")
        let event = repository.createEvent(title: "A", start: .now, end: .now, isAllDay: false, in: calendar, createdBy: nil)
        let comment = repository.addComment("Hallo", to: event, author: nil)
        repository.edit(comment, text: "Hallo")
        #expect(comment.editedAt == nil)
        repository.edit(comment, text: "Hallo zusammen")
        #expect(comment.editedAt != nil)
    }

    @Test func ownerProfileIsClaimedOnceUserIDIsKnown() throws {
        let family = repository.createFamily(name: "F", ownerName: "Anna", ownerUserID: nil, calendarName: "F")
        repository.addChildProfile(name: "Mia", to: family)
        repository.claimOwnerProfiles(userID: "anna")
        #expect(repository.me(in: family, userID: "anna")?.displayName == "Anna")
        // Familien, in die man eingeladen wurde, bleiben unberührt.
        let shared = repository.insert(Family.self, into: persistence.sharedStore)
        repository.addMember(name: "Owner", kind: .adult, userID: nil, to: shared)
        repository.claimOwnerProfiles(userID: "anna")
        #expect(repository.me(in: shared, userID: "anna") == nil)
    }
}
