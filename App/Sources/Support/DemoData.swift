#if DEBUG
import Foundation
import YafoKit

/// Beispieldaten für Simulator und Screenshots, per Startargument `-yafoDemoData`.
enum DemoData {
    static func seedIfNeeded(_ repository: Repository) {
        guard repository.families().isEmpty else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = cal.date(byAdding: .day, value: dayOffset, to: today)!
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }

        let family = repository.createFamily(name: "Millers", ownerName: "Anna Miller",
                                             ownerUserID: nil, calendarName: "Family")
        let anna = family.members!.first!
        let ben = repository.addMember(name: "Ben Miller", kind: .adult, userID: "demo-ben", to: family)
        let mia = repository.addChildProfile(name: "Mia", to: family)
        let shared = family.calendars!.first!
        let sports = repository.addSharedCalendar(name: "Sports", to: family)
        let school = repository.addSharedCalendar(name: "School", to: family)
        let personal = repository.ensurePersonalCalendar(name: "My Calendar")
        let by = anna.id?.uuidString

        let zoo = repository.createEvent(title: "Zoo", start: at(1, 10), end: at(1, 16), isAllDay: false,
                                         in: shared, participants: [anna, ben, mia], createdBy: by)
        repository.addComment("Who brings snacks?", to: zoo, author: ben)
        repository.addComment("I'll pack sandwiches and apples.", to: zoo, author: anna)
        repository.createEvent(title: "Swimming", start: at(0, 16), end: at(0, 17), isAllDay: false,
                               in: sports, participants: [mia], recurrenceRule: "FREQ=WEEKLY", createdBy: by)
        repository.createEvent(title: "Parents' evening", start: at(3, 19), end: at(3, 21), isAllDay: false,
                               in: shared, participants: [anna], createdBy: ben.id?.uuidString)
        repository.createBirthday(name: "Mia", day: at(6, 0), birthYear: cal.component(.year, from: .now) - 8,
                                  in: shared, createdBy: by)
        repository.createBirthday(name: "Grandma", day: at(18, 0), birthYear: 1952, in: shared, createdBy: by)
        repository.createEvent(title: "Grandma visiting", start: at(5, 0), end: at(8, 0), isAllDay: true,
                               in: shared, createdBy: by)
        repository.createEvent(title: "Dentist", start: at(0, 8, 30), end: at(0, 9), isAllDay: false,
                               in: personal, createdBy: nil)
        repository.createEvent(title: "Team lunch", start: at(0, 12), end: at(0, 13), isAllDay: false,
                               in: personal, createdBy: nil)
        repository.createEvent(title: "Book club", start: at(0, 20), end: at(0, 22), isAllDay: false,
                               in: personal, createdBy: nil)
        repository.createEvent(title: "School trip", start: at(9, 0), end: at(14, 0), isAllDay: true,
                               in: school, participants: [mia], createdBy: by)
        repository.createEvent(title: "Math test", start: at(2, 8), end: at(2, 9), isAllDay: false,
                               in: school, participants: [mia], createdBy: by)
        repository.createEvent(title: "Football", start: at(2, 15), end: at(2, 16, 30), isAllDay: false,
                               in: sports, participants: [ben], createdBy: by)
        let piano = repository.createEvent(title: "Piano", start: at(4, 15), end: at(4, 16), isAllDay: false,
                                           in: school, participants: [mia], recurrenceRule: "FREQ=WEEKLY;COUNT=8",
                                           createdBy: by)
        // Eine Stunde fällt aus.
        repository.delete(piano, occurrence: at(11, 15), scope: .thisOccurrence)
        repository.createEvent(title: "Recycling", start: at(1, 0), end: at(2, 0), isAllDay: true,
                               in: shared, recurrenceRule: "FREQ=WEEKLY;INTERVAL=2", createdBy: by)
        repository.createEvent(title: "Car service", start: at(11, 9), end: at(11, 10), isAllDay: false,
                               in: personal, createdBy: nil)
        try? repository.save()
    }
}
#endif
