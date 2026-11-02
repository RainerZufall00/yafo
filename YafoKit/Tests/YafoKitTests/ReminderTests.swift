import CoreData
import Foundation
import Testing
@testable import YafoKit

@Suite struct ReminderTests {
    let persistence: PersistenceController
    let repository: Repository
    let family: Family
    let anna: Member
    let ben: Member
    let mia: Member
    let shared: EventCalendar
    let personal: EventCalendar
    let cal = Calendar.current
    /// Montag, 2.11.2026, 8 Uhr.
    let now: Date

    init() throws {
        persistence = try PersistenceController.makeTemporary()
        repository = Repository(persistence: persistence)
        family = repository.createFamily(name: "Millers", ownerName: "Anna", ownerUserID: "anna", calendarName: "Family")
        anna = family.members!.first!
        ben = repository.addMember(name: "Ben", kind: .adult, userID: "ben", to: family)
        mia = repository.addChildProfile(name: "Mia", to: family)
        shared = family.calendars!.first!
        personal = repository.ensurePersonalCalendar(name: "Me")
        now = cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 8))!
    }

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func plan(as member: Member?) -> [PlannedReminder] {
        repository.plannedReminders(now: now, me: { _ in member })
    }

    @Test func defaultOffsets() {
        repository.createEvent(title: "Dentist", start: at(3, 10), end: at(3, 11), isAllDay: false,
                               in: personal, createdBy: nil)
        repository.createEvent(title: "Trip", start: at(5, 0), end: at(6, 0), isAllDay: true,
                               in: personal, createdBy: nil)
        repository.addTodo("Bins", dueDate: at(4, 0), to: .personal, createdBy: nil)
        repository.createBirthday(name: "Grandma", day: at(2, 0), birthYear: 1952, in: personal, createdBy: nil)

        let planned = plan(as: nil)
        #expect(planned.map(\.title) == ["Grandma", "Dentist", "Bins", "Trip"])
        #expect(planned.map(\.fireDate) == [at(2, 9), at(3, 9, 30), at(4, 9), at(4, 18)])
        #expect(planned.first?.kind == .birthday(age: 74))
    }

    @Test func pastRemindersAreSkipped() {
        repository.createEvent(title: "Soon", start: at(2, 8, 15), end: at(2, 9), isAllDay: false,
                               in: personal, createdBy: nil)
        #expect(plan(as: nil).isEmpty)
    }

    @Test func participantsWithAccountGetReminded() {
        repository.createEvent(title: "Parents' evening", start: at(4, 19), end: at(4, 21), isAllDay: false,
                               in: shared, participants: [ben, mia], createdBy: nil)
        #expect(plan(as: ben).map(\.title) == ["Parents' evening"])
        #expect(plan(as: anna).isEmpty)
    }

    @Test func onlyChildrenOrNobodyMeansAllAdults() {
        repository.createEvent(title: "Swimming", start: at(4, 16), end: at(4, 17), isAllDay: false,
                               in: shared, participants: [mia], createdBy: nil)
        repository.createEvent(title: "Zoo", start: at(5, 10), end: at(5, 16), isAllDay: false,
                               in: shared, createdBy: nil)
        #expect(plan(as: anna).map(\.title) == ["Swimming", "Zoo"])
        #expect(plan(as: ben).count == 2)
        #expect(plan(as: mia).isEmpty)
        #expect(plan(as: nil).isEmpty)
    }

    @Test func todosGoToTheAssignee() {
        repository.addTodo("Book flat", dueDate: at(4, 0), assignee: ben, to: .family(family), createdBy: nil)
        repository.addTodo("Tidy room", dueDate: at(4, 0), assignee: mia, to: .family(family), createdBy: nil)
        #expect(plan(as: ben).map(\.title).sorted() == ["Book flat", "Tidy room"])
        #expect(plan(as: anna).map(\.title) == ["Tidy room"])
    }

    @Test func ownSettingOverridesAndMutes() {
        let event = repository.createEvent(title: "Dentist", start: at(3, 10), end: at(3, 11), isAllDay: false,
                                           in: personal, createdBy: nil)
        repository.setAlert(.offset(24 * 3600), for: event.id)
        #expect(plan(as: nil).first?.fireDate == at(2, 10))
        #expect(repository.alertSetting(for: event.id) == .offset(24 * 3600))

        repository.setAlert(.muted, for: event.id)
        #expect(plan(as: nil).isEmpty)

        repository.setAlert(.standard, for: event.id)
        #expect(repository.alertPreference(for: event.id) == nil)
        #expect(plan(as: nil).first?.fireDate == at(3, 9, 30))
    }

    @Test func seriesProduceOneReminderPerOccurrenceUpToTheLimit() {
        repository.createEvent(title: "Daily", start: at(3, 7), end: at(3, 8), isAllDay: false,
                               in: personal, recurrenceRule: "FREQ=DAILY", createdBy: nil)
        #expect(plan(as: nil).count == 60)
        let planned = repository.plannedReminders(now: now, days: 120, me: { _ in nil })
        #expect(planned.count == Repository.reminderLimit)
        #expect(Set(planned.map(\.id)).count == planned.count)
        #expect(planned.first?.fireDate == at(3, 6, 30))
    }
}
