import CoreData
import Foundation
import Testing
@testable import YafoKit

@Suite struct RepositoryTests {
    let persistence: PersistenceController
    let repository: Repository

    init() throws {
        persistence = try PersistenceController.makeTemporary()
        repository = Repository(persistence: persistence)
    }

    @Test func createFamilyPutsEverythingIntoPrivateStore() throws {
        let family = repository.createFamily(name: "Müller", ownerName: "Anna Müller",
                                             ownerUserID: "user-anna", calendarName: "Familie")
        try repository.save()

        #expect(persistence.store(of: family) == persistence.privateStore)
        let owner = try #require(family.members?.first)
        #expect(owner.kind == .adult)
        #expect(owner.initials == "AM")
        #expect(persistence.store(of: owner) == persistence.privateStore)

        let calendar = try #require(family.calendars?.first)
        #expect(calendar.kind == .shared)
        #expect(calendar.defaultColor == CalendarColors.sharedDefault)
        #expect(repository.me(in: family, userID: "user-anna") == owner)
    }

    @Test func newObjectsFollowTheirFamilyIntoTheSharedStore() throws {
        // Simuliert eine Familie, in die man eingeladen wurde.
        let family = repository.insert(Family.self, into: persistence.sharedStore)
        family.name = "Großeltern"
        let child = repository.addChildProfile(name: "Lena", to: family)
        let calendar = repository.addSharedCalendar(name: "Oma & Opa", to: family)
        let event = repository.createEvent(title: "Zoo", start: .now, end: .now.addingTimeInterval(3600),
                                           isAllDay: false, in: calendar, participants: [child],
                                           createdBy: nil)
        try repository.save()

        for object in [family, child, calendar, event] as [NSManagedObject] {
            #expect(persistence.store(of: object) == persistence.sharedStore)
        }
        #expect(child.kind == .child)
        #expect(child.hasAccount == false)
        #expect(event.participants == [child])
    }

    @Test func secondSharedCalendarGetsItsOwnColor() {
        let family = repository.createFamily(name: "Müller", ownerName: "Anna", ownerUserID: nil,
                                             calendarName: "Familie")
        let second = repository.addSharedCalendar(name: "Sport", to: family)
        #expect(second.defaultColor == CalendarColors.additionalShared[0])
    }

    @Test func participantsFromOtherFamiliesAreDropped() throws {
        let mine = repository.createFamily(name: "A", ownerName: "Anna", ownerUserID: nil, calendarName: "A")
        let other = repository.createFamily(name: "B", ownerName: "Ben", ownerUserID: nil, calendarName: "B")
        let stranger = try #require(other.members?.first)
        let calendar = try #require(mine.calendars?.first)
        let event = repository.createEvent(title: "Test", start: .now, end: .now, isAllDay: false,
                                           in: calendar, participants: [stranger], createdBy: nil)
        #expect(event.participants?.isEmpty == true)
    }

    @Test func personalCalendarExistsOnce() throws {
        let first = repository.ensurePersonalCalendar(name: "Mein Kalender")
        try repository.save()
        let second = repository.ensurePersonalCalendar(name: "Mein Kalender")
        #expect(first == second)
        #expect(first.defaultColor == CalendarColors.personalDefault)
        #expect(persistence.store(of: first) == persistence.privateStore)
    }

    @Test func duplicatePersonalCalendarsAreMerged() throws {
        let keeper = repository.ensurePersonalCalendar(name: "Ich")
        // Zweites Gerät hat vor dem Sync ebenfalls einen eigenen Kalender angelegt.
        let duplicate = repository.insert(EventCalendar.self, into: persistence.privateStore)
        duplicate.kindRaw = CalendarKind.personal.rawValue
        let event = repository.createEvent(title: "Arzt", start: .now, end: .now, isAllDay: false,
                                           in: duplicate, createdBy: nil)
        try repository.save()

        repository.mergeDuplicatePersonalCalendars()
        try repository.save()
        #expect(repository.calendars() == [keeper])
        #expect(event.calendar == keeper)
    }

    @Test func joiningCanLinkAnExistingChildProfile() throws {
        let family = repository.insert(Family.self, into: persistence.sharedStore)
        let teen = repository.addChildProfile(name: "Tom", to: family)
        #expect(repository.familiesNeedingProfile(userID: "user-tom") == [family])

        let me = repository.join(family, userID: "user-tom", name: "Tom", linking: teen)
        #expect(me == teen)
        #expect(me.kind == .child)
        #expect(repository.familiesNeedingProfile(userID: "user-tom").isEmpty)
    }

    @Test func appearanceOverridesColorPerUser() throws {
        let calendar = repository.ensurePersonalCalendar(name: "Ich")
        #expect(repository.color(of: calendar) == CalendarColors.personalDefault)
        repository.setAppearance(of: calendar, color: "#123456", isVisible: false)
        try repository.save()
        #expect(repository.color(of: calendar) == "#123456")
        #expect(repository.isVisible(calendar) == false)
        #expect(repository.eventStyle(of: calendar) == .outlined)

        repository.setAppearance(of: calendar, eventStyle: .hatched)
        try repository.save()
        #expect(repository.eventStyle(of: calendar) == .hatched)
        #expect(repository.color(of: calendar) == "#123456")
    }

    @Test func eventsOverlappingInterval() throws {
        let calendar = repository.ensurePersonalCalendar(name: "Ich")
        let day = Calendar.current.startOfDay(for: .now)
        let inside = repository.createEvent(title: "In", start: day.addingTimeInterval(3600),
                                            end: day.addingTimeInterval(7200), isAllDay: false,
                                            in: calendar, createdBy: nil)
        repository.createEvent(title: "Out", start: day.addingTimeInterval(-7200),
                               end: day.addingTimeInterval(-3600), isAllDay: false,
                               in: calendar, createdBy: nil)
        try repository.save()
        let found = repository.occurrences(overlapping: DateInterval(start: day, duration: 86_400))
        #expect(found.map(\.event) == [inside])
    }

    @Test func leftMembersAreHiddenButKept() throws {
        let family = repository.createFamily(name: "A", ownerName: "Anna", ownerUserID: nil, calendarName: "A")
        let kid = repository.addChildProfile(name: "Kim", to: family)
        repository.markLeft(kid)
        #expect(repository.activeMembers(of: family).map(\.displayName) == ["Anna"])
        #expect(family.members?.contains(kid) == true)
    }
}
