import CoreData
import Foundation
import Testing
@testable import YafoKit

@Suite struct ExportTests {
    let persistence: PersistenceController
    let repository: Repository
    let personal: EventCalendar
    let family: Family
    let shared: EventCalendar
    let cal = Calendar.current

    init() throws {
        persistence = try PersistenceController.makeTemporary()
        repository = Repository(persistence: persistence)
        personal = repository.ensurePersonalCalendar(name: "Me")
        family = repository.createFamily(name: "Millers", ownerName: "Anna", ownerUserID: nil, calendarName: "Family")
        shared = family.calendars!.first!
    }

    func local(_ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
    }

    /// Serie mit Absage und Verschiebung, ganztägiger Termin, Teilnehmer und Kommentar.
    @discardableResult
    func seed() throws -> Event {
        let anna = family.members!.first!
        let mia = repository.addChildProfile(name: "Mia", to: family)
        let swim = repository.createEvent(title: "Swimming, Pool; Lane 2", start: local(11, 2, 16), end: local(11, 2, 17),
                                          isAllDay: false, in: shared, participants: [mia],
                                          recurrenceRule: "FREQ=WEEKLY;COUNT=4", createdBy: nil)
        swim.timeZone = "Europe/Berlin"
        swim.notes = "Bring towel"
        repository.delete(swim, occurrence: local(11, 9, 16), scope: .thisOccurrence)
        repository.update(swim, occurrence: local(11, 16, 16),
                          with: EventDraft(title: "Swimming late", start: local(11, 16, 18), end: local(11, 16, 19),
                                           isAllDay: false, calendar: shared, participants: [mia],
                                           recurrenceRule: swim.recurrenceRule),
                          scope: .thisOccurrence)
        repository.addComment("Mia has a cold", to: swim, author: anna)
        repository.createEvent(title: "Trip", start: local(11, 20), end: local(11, 22), isAllDay: true, in: personal,
                               createdBy: nil)
        repository.addShoppingItem("Milch", quantity: "2", to: .family(family))
        repository.addShoppingItem("Kaffee", to: .personal)
        repository.addTodo("Call school", dueDate: local(11, 5), assignee: anna, to: .family(family), createdBy: nil)
        repository.setSchoolHolidayRegion(SchoolHolidayRegion.region(code: "DE-BY"), for: shared)
        repository.setAppearance(of: shared, color: "#123456")
        try repository.save()
        return swim
    }

    @Test func icsRoundTripKeepsSeriesExceptionsAndText() throws {
        try seed()
        let text = repository.icsDocument(for: [shared, personal])
        #expect(text.contains("\r\n"))
        #expect(text.split(separator: "\r\n").allSatisfy { $0.utf8.count <= 75 })
        #expect(text.contains("DTSTART;TZID=Europe/Berlin:"))
        #expect(text.contains("DTSTART;VALUE=DATE:20261120"))

        let parsed = ICSParser.parse(text)
        let master = try #require(parsed.first { $0.recurrenceRule != nil })
        #expect(master.summary == "Swimming, Pool; Lane 2")
        #expect(master.start == local(11, 2, 16))
        #expect(master.excludedDates == [local(11, 9, 16)])
        #expect(master.notes?.contains("Bring towel") == true)
        #expect(master.notes?.contains("Mia") == true)
        #expect(master.notes?.contains("Anna: Mia has a cold") == true)
        let override = try #require(parsed.first { $0.recurrenceID != nil })
        #expect(override.recurrenceID == local(11, 16, 16))
        #expect(override.start == local(11, 16, 18))
        #expect(override.uid == master.uid)
        let trip = try #require(parsed.first { $0.summary == "Trip" })
        #expect(trip.isAllDay && trip.end == local(11, 22))

        // Ein Import der eigenen Datei ergibt dieselben Vorkommen.
        let target = repository.addSharedCalendar(name: "Copy", to: family)
        repository.importICS(parsed.filter { $0.recurrenceRule != nil || $0.recurrenceID != nil }, into: target,
                             createdBy: nil)
        let month = DateInterval(start: local(11, 1), end: local(12, 1))
        let copies = (target.events ?? []).flatMap { $0.occurrences(overlapping: month) }.sorted { $0.start < $1.start }
        #expect(copies.map(\.start) == [local(11, 2, 16), local(11, 16, 18), local(11, 23, 16)])
    }

    @Test func allDayEndIsNeverBeforeNextDay() {
        let sameDay = ICSWriter.Item(uid: "a", title: "A", start: local(11, 11), end: local(11, 11), isAllDay: true)
        let lateEnd = ICSWriter.Item(uid: "b", title: "B", start: local(11, 11), end: local(11, 12).addingTimeInterval(-60),
                                     isAllDay: true)
        let text = ICSWriter.document(name: nil, items: [sameDay, lateEnd])
        #expect(text.components(separatedBy: "DTEND;VALUE=DATE:20261112").count == 3)
    }

    @Test func foldsLongLinesWithoutSplittingCharacters() {
        let line = "SUMMARY:" + String(repeating: "ü", count: 60)
        let folded = ICSWriter.fold(line)
        #expect(folded.split(separator: "\r\n").allSatisfy { $0.utf8.count <= 75 })
        #expect(ICSParser.unfold(folded) == [line])
    }

    @Test func csvQuotesAndScopes() throws {
        try seed()
        #expect(CSVWriter.field("plain") == "plain")
        #expect(CSVWriter.field("a, \"b\"") == "\"a, \"\"b\"\"\"")
        #expect(CSVWriter.field("line\r\nbreak") == "\"line\r\nbreak\"")

        let shopping = repository.shoppingCSV(repository.shoppingItems(in: .family(family)))
        #expect(shopping.hasPrefix("\u{FEFF}"))
        #expect(shopping.contains("Milch,2,dairy,,Millers"))
        #expect(!shopping.contains("Kaffee"))
        #expect(repository.shoppingItems(in: .personal).map(\.name) == ["Kaffee"])
        #expect(repository.shoppingItems(in: .all).count == 2)

        let todos = repository.todoCSV(repository.todoItems(in: .all))
        #expect(todos.contains("Call school,2026-11-05,,Anna,,Millers"))

        let events = repository.eventCSV(for: repository.calendars(in: .all))
        #expect(events.contains("\"Swimming, Pool; Lane 2\",2026-11-02 16:00,2026-11-02 17:00,,Family,,Mia,\"FREQ=WEEKLY;COUNT=4\",Bring towel"))
        #expect(events.contains("Trip,2026-11-20,2026-11-21,1,Me"))
    }

    @Test func backupRoundTripIntoEmptyStore() throws {
        let swim = try seed()
        let backup = repository.makeBackup()
        let data = try backup.encoded()
        let decoded = try Backup.decode(data)
        // Millisekunden genau: nochmal kodiert ergibt dieselbe Datei.
        let reencoded = try decoded.encoded()
        #expect(reencoded == data)
        #expect(decoded.families.count == 1 && decoded.members.count == 2 && decoded.calendars.count == 2)
        #expect(decoded.events.count == 2 && decoded.comments.count == 1)
        #expect(decoded.events.first { $0.id == swim.id }?.exceptions.count == 2)

        // Neues Gerät, Familie nicht mehr erreichbar: alles entsteht neu, man wird Owner.
        let other = try PersistenceController.makeTemporary()
        let otherRepository = Repository(persistence: other)
        let ownCalendar = otherRepository.ensurePersonalCalendar(name: "Mein Kalender")
        let result = otherRepository.restore(decoded, personalCalendarName: "Mein Kalender")
        try otherRepository.save()
        #expect(result.newFamilies == ["Millers"])
        #expect(result.skipped == 0)

        let restoredFamily = try #require(otherRepository.families().first)
        #expect(other.store(of: restoredFamily) == other.privateStore)
        #expect(otherRepository.activeMembers(of: restoredFamily).map(\.displayName) == ["Anna", "Mia"])
        // Der eigene Kalender wird nicht verdoppelt.
        #expect(otherRepository.calendars().count == 2)
        #expect(ownCalendar.events?.map(\.title) == ["Trip"])

        let month = DateInterval(start: local(11, 1), end: local(12, 1))
        let restored = otherRepository.occurrences(overlapping: month).filter { $0.event.calendar?.family != nil }
        #expect(restored.map(\.title) == ["Swimming, Pool; Lane 2", "Swimming late", "Swimming, Pool; Lane 2"])
        let restoredSwim = try #require(restored.first?.event)
        #expect(restoredSwim.participants?.map(\.displayName) == ["Mia"])
        #expect(restoredSwim.comments?.first?.author?.displayName == "Anna")
        #expect(otherRepository.schoolHolidayRegion(of: restoredSwim.calendar!)?.code == "DE-BY")
        #expect(otherRepository.color(of: restoredSwim.calendar!) == "#123456")
        #expect(otherRepository.todoItems(in: .all).first?.assignee?.displayName == "Anna")
        #expect(Set(otherRepository.shoppingItems(in: .all).compactMap(\.name)) == ["Milch", "Kaffee"])

        // Ein zweites Mal wiederherstellen legt nichts doppelt an.
        let again = otherRepository.restore(decoded, personalCalendarName: "Mein Kalender")
        #expect(again.created == 0)
        try otherRepository.save()
        #expect(otherRepository.families().count == 1)
        #expect(otherRepository.shoppingItems(in: .all).count == 2)
    }

    @Test func backupPerScopeAndInvalidFiles() throws {
        try seed()
        let familyOnly = repository.makeBackup(scope: .family(family))
        #expect(familyOnly.calendars.map(\.name) == ["Family"])
        #expect(familyOnly.shoppingItems.map(\.name) == ["Milch"])
        let personalOnly = repository.makeBackup(scope: .personal)
        #expect(personalOnly.families.isEmpty && personalOnly.calendars.map(\.name) == ["Me"])

        #expect(throws: BackupError.self) { try Backup.decode(Data(#"{"format":"other","version":1,"createdAt":"2026-11-03T08:00:00Z","families":[],"members":[],"calendars":[],"events":[],"comments":[],"shoppingItems":[],"todos":[],"subscriptions":[],"appearances":[],"alertPreferences":[]}"#.utf8)) }
        #expect(throws: (any Error).self) { try Backup.decode(Data("nonsense".utf8)) }
        #expect(Backup.fileName(at: local(11, 3, 8)) == "yafo-Backup 2026-11-03 0800.json")
    }
}
