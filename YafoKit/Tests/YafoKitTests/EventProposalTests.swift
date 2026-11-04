import Foundation
import Testing
@testable import YafoKit

@Suite struct EventProposalTests {
    let cal = Calendar.current
    let now: Date

    init() {
        now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!
    }

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - Felder des Sprachmodells

    @Test func timedProposalFromModelFields() throws {
        let proposal = try #require(EventProposal(title: " Elternabend ", date: "2026-11-12", startTime: "19:30",
                                                  endDate: nil, endTime: "21:00", location: "Aula", calendar: cal))
        #expect(proposal.title == "Elternabend")
        #expect(!proposal.isAllDay)
        #expect(proposal.start == date(2026, 11, 12, 19, 30))
        #expect(proposal.end == date(2026, 11, 12, 21))
        #expect(proposal.location == "Aula")
    }

    @Test func missingOrBrokenEndIsOneHour() throws {
        let noEnd = try #require(EventProposal(title: "Zahnarzt", date: "2026-12-03", startTime: "10:15",
                                               endDate: nil, endTime: nil, location: "", calendar: cal))
        #expect(noEnd.end == date(2026, 12, 3, 11, 15))
        #expect(noEnd.location == nil)
        let endBeforeStart = try #require(EventProposal(title: "X", date: "2026-12-03", startTime: "10:00",
                                                        endDate: nil, endTime: "09:00", location: nil, calendar: cal))
        #expect(endBeforeStart.end == date(2026, 12, 3, 11))
    }

    @Test func withoutTimeIsAllDayOverSeveralDays() throws {
        let trip = try #require(EventProposal(title: "Klassenfahrt", date: "2026-11-11", startTime: nil,
                                              endDate: "2026-11-15", endTime: nil, location: nil, calendar: cal))
        #expect(trip.isAllDay)
        #expect(trip.start == date(2026, 11, 11))
        #expect(trip.end == date(2026, 11, 15))
        let times = trip.draftTimes(calendar: cal)
        #expect(times.start == date(2026, 11, 11))
        #expect(times.end == date(2026, 11, 16))
    }

    @Test func invalidDateIsRejected() {
        #expect(EventProposal(title: "X", date: "2026-02-30", startTime: nil, endDate: nil, endTime: nil,
                              location: nil, calendar: cal) == nil)
        #expect(EventProposal(title: "X", date: "morgen", startTime: nil, endDate: nil, endTime: nil,
                              location: nil, calendar: cal) == nil)
    }

    // MARK: - Fallback ohne Sprachmodell

    @Test func extractorFindsDateTitleAndAddress() throws {
        let lines = ["11:58", "Liebe Eltern,",
                     "Elternabend am Donnerstag, 12.11.2026 um 19:30 Uhr",
                     "Schillerstraße 12, 10625 Berlin"]
        let proposals = TextEventExtractor.proposals(in: lines, now: now, calendar: cal)
        #expect(proposals.count == 1)
        let first = try #require(proposals.first)
        #expect(first.title == "Elternabend")
        #expect(first.start == date(2026, 11, 12, 19, 30))
        #expect(first.end == date(2026, 11, 12, 20, 30))
        #expect(!first.isAllDay)
        #expect(first.location == "Schillerstraße 12, 10625 Berlin")
    }

    @Test func extractorUsesRangeAndLineAbove() throws {
        let lines = ["Kindergeburtstag von Mia", "Samstag 21. November 2026 15-18 Uhr"]
        let first = try #require(TextEventExtractor.proposals(in: lines, now: now, calendar: cal).first)
        #expect(first.title == "Kindergeburtstag von Mia")
        #expect(first.start == date(2026, 11, 21, 15))
        #expect(first.end == date(2026, 11, 21, 18))
    }

    @Test func extractorReadsLettersBrokenIntoLines() throws {
        // So liefert die Texterkennung den Elternbrief: Sätze über mehrere Zeilen.
        let lines = ["9:41", "Grundschule am", "Park", "Liebe Eltern,",
                     "der Elternabend der Klasse 2b findet", "am Donnerstag, 12.11.2026 um 19:30",
                     "Uhr in der Aula statt.", "Das Sommerfest feiern wir am", "27.06.2027.",
                     "Viele Grüße", "Frau Berger", "Gestern 18:02"]
        let proposals = TextEventExtractor.proposals(in: lines, now: now, calendar: cal)
        #expect(proposals.map(\.title) == ["Elternabend", "Sommerfest"])
        #expect(proposals.first?.start == date(2026, 11, 12, 19, 30))
        #expect(proposals.first?.location == "Aula")
        #expect(proposals.last?.isAllDay == true)
        #expect(proposals.last?.location == nil)
    }

    @Test func extractorTakesLabelAfterDateAndEnglishNouns() {
        let lines = ["Fr, 20.11.2026, 16:00–17:30 Fußballtraining", "The parent meeting is on December 3, 2026 at 2pm"]
        let proposals = TextEventExtractor.proposals(in: lines, now: now, calendar: cal)
        #expect(proposals.map(\.title) == ["Fußballtraining", "Parent meeting"])
        #expect(proposals.first?.end == date(2026, 11, 20, 17, 30))
    }

    @Test func extractorDateWithoutTimeIsAllDayAndSkipsThePast() {
        let lines = ["Sommerfest 27.06.2027", "Gesendet am 01.10.2026"]
        let proposals = TextEventExtractor.proposals(in: lines, now: now, calendar: cal)
        #expect(proposals.count == 1)
        #expect(proposals.first?.title == "Sommerfest")
        #expect(proposals.first?.isAllDay == true)
        #expect(proposals.first?.start == date(2027, 6, 27))
    }

    // MARK: - Speichern aus der Share Extension

    @Test func appPicksUpEventsSavedByTheShareExtension() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "yafo-\(UUID().uuidString)", directoryHint: .isDirectory)
        let app = try PersistenceController(mode: .local(directory: directory))
        let appRepository = Repository(persistence: app)
        let calendar = appRepository.ensurePersonalCalendar(name: "Ich")
        try appRepository.save()
        #expect(app.mergeExternalChanges() == 0)

        let share = try PersistenceController(mode: .local(directory: directory))
        share.viewContext.transactionAuthor = PersistenceController.shareExtensionAuthor
        let shareRepository = Repository(persistence: share)
        let shareCalendar = try #require(share.viewContext.object(with: calendar.objectID) as? EventCalendar)
        shareRepository.createEvent(title: "Elternabend", start: now, end: now.addingTimeInterval(3600),
                                    isAllDay: false, in: shareCalendar, createdBy: nil)
        try shareRepository.save()

        #expect(app.mergeExternalChanges() == 1)
        #expect(app.mergeExternalChanges() == 0)
        // Eigene Änderungen der App zählen nicht mit.
        appRepository.createEvent(title: "Eigener", start: now, end: now, isAllDay: false, in: calendar, createdBy: nil)
        try appRepository.save()
        #expect(app.mergeExternalChanges() == 0)
    }
}
