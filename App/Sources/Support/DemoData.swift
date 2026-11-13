#if DEBUG
import Foundation
import YafoKit

/// Beispieldaten für Simulator und Screenshots, per Startargument `-yafoDemoData` (oder `-screenshotDemo`).
/// Familie Sommer: Anna und Ben, dazu die Kinderprofile Mia (8) und Leo (5). Die Texte folgen der Sprache
/// der App (Deutsch, sonst Englisch), die Termine liegen rund um heute, damit der Monat voll aussieht.
enum DemoData {
    /// Termin mit Kommentaren, den `-demoScreen event` öffnet.
    private(set) static var featuredEvent: Event?

    static func seedIfNeeded(_ repository: Repository) {
        guard repository.families().isEmpty else { return }
        let german = Bundle.main.preferredLocalizations.first?.hasPrefix("de") ?? false
        func t(_ de: String, _ en: String) -> String { german ? de : en }

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = cal.date(byAdding: .day, value: dayOffset, to: today)!
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }

        let family = repository.createFamily(name: t("Familie Sommer", "The Summers"), ownerName: "Anna Sommer",
                                             ownerUserID: nil, calendarName: t("Familie", "Family"))
        let anna = family.members!.first!
        let ben = repository.addMember(name: "Ben Sommer", kind: .adult, userID: "demo-ben", to: family)
        let mia = repository.addChildProfile(name: "Mia", to: family)
        let leo = repository.addChildProfile(name: "Leo", to: family)
        let shared = family.calendars!.first!
        let sports = repository.addSharedCalendar(name: t("Sport", "Sports"), to: family)
        let school = repository.addSharedCalendar(name: t("Schule & Kita", "School"), to: family)
        let personal = repository.ensurePersonalCalendar(name: String(localized: "My Calendar"))
        let by = anna.id?.uuidString
        let byBen = ben.id?.uuidString
        // Feiertage gibt es nur für Deutschland, Österreich und die Schweiz.
        if german { repository.setHolidayRegion(.by, for: shared) }

        @discardableResult
        func event(_ de: String, _ en: String, _ start: Date, _ end: Date, allDay: Bool = false,
                   in calendar: EventCalendar, _ people: Set<Member> = [], rule: String? = nil,
                   location: String? = nil, by creator: String? = by) -> Event {
            let event = repository.createEvent(title: t(de, en), start: start, end: end, isAllDay: allDay,
                                               in: calendar, participants: people, recurrenceRule: rule,
                                               createdBy: calendar.kind == .personal ? nil : creator)
            if let location { event.location = location }
            return event
        }

        // Familie
        let zoo = event("Ausflug in den Zoo", "Trip to the zoo", at(1, 10), at(1, 16), in: shared,
                        [anna, ben, mia, leo], location: t("Tierpark Hellabrunn, München", "London Zoo, Regent's Park"))
        func comment(_ de: String, _ en: String, by author: Member, minutesAgo: Double) {
            let comment = repository.addComment(t(de, en), to: zoo, author: author)
            comment.createdAt = Date.now.addingTimeInterval(-60 * minutesAgo)
        }
        comment("Wer bringt Snacks mit?", "Who brings snacks?", by: ben, minutesAgo: 185)
        comment("Ich packe Brote und Äpfel ein 🍎", "I'll pack sandwiches and apples 🍎", by: anna, minutesAgo: 160)
        comment("Können wir zuerst zu den Pinguinen? 🐧", "Can we see the penguins first? 🐧", by: mia, minutesAgo: 42)
        featuredEvent = zoo
        event("Elternabend", "Parents' evening", at(3, 19), at(3, 21), in: shared, [anna], by: byBen)
        event("Oma zu Besuch", "Grandma visiting", at(5, 0), at(8, 0), allDay: true, in: shared)
        event("Papiertonne", "Recycling", at(-13, 0), at(-12, 0), allDay: true, in: shared,
              rule: "FREQ=WEEKLY;INTERVAL=2")
        event("Grillen bei Jansens", "BBQ at the Jansens'", at(-6, 17), at(-6, 21), in: shared, [anna, ben, mia, leo])
        event("Flohmarkt", "Flea market", at(-9, 9), at(-9, 13), in: shared, [ben, mia])
        event("Handwerker Küche", "Plumber (kitchen)", at(12, 8), at(12, 10), in: shared, [ben], by: byBen)
        repository.createBirthday(name: "Mia", day: at(6, 0), birthYear: cal.component(.year, from: .now) - 8,
                                  in: shared, createdBy: by)
        repository.createBirthday(name: t("Oma", "Grandma"), day: at(18, 0), birthYear: 1952, in: shared,
                                  createdBy: by)

        // Sport
        event("Schwimmen", "Swimming", at(-14, 16), at(-14, 17), in: sports, [mia], rule: "FREQ=WEEKLY")
        event("Fußball", "Football", at(-12, 15), at(-12, 16, 30), in: sports, [leo], rule: "FREQ=WEEKLY",
              by: byBen)
        event("Laufgruppe", "Running club", at(-10, 19), at(-10, 20), in: sports, [ben], rule: "FREQ=WEEKLY",
              by: byBen)

        // Schule & Kita
        let piano = event("Klavier", "Piano", at(-10, 15), at(-10, 16), in: school, [mia],
                          rule: "FREQ=WEEKLY;COUNT=8")
        repository.delete(piano, occurrence: at(11, 15), scope: .thisOccurrence) // Eine Stunde fällt aus.
        event("Mathe-Probe", "Math test", at(2, 8), at(2, 9), in: school, [mia])
        event("Kita-Fotograf", "Nursery photos", at(-4, 9), at(-4, 10), in: school, [leo])
        event("Klassenfahrt", "School trip", at(9, 0), at(14, 0), allDay: true, in: school, [mia])
        event("Laternenbasteln", "Lantern crafts", at(-2, 15), at(-2, 17), in: school, [leo, anna])

        // Mein Kalender
        event("Zahnarzt", "Dentist", at(0, 8, 30), at(0, 9), in: personal)
        event("Mittagessen mit dem Team", "Team lunch", at(0, 12), at(0, 13), in: personal)
        event("Buchclub", "Book club", at(0, 20), at(0, 22), in: personal)
        event("Yoga", "Yoga", at(-11, 19), at(-11, 20), in: personal, rule: "FREQ=WEEKLY")
        event("Auto in die Werkstatt", "Car service", at(11, 9), at(11, 10), in: personal)
        event("Friseur", "Hairdresser", at(-7, 11), at(-7, 12), in: personal)

        // Einkauf
        let list = ListScope.family(family)
        let open = german
            ? ["Bananen", "Tomaten", "Gurke", "Paprika", "Karotten", "Brot", "Brezeln", "Vollmilch", "Eier", "Joghurt",
               "Käse", "Müsli", "Kaffee", "Klopapier", "Spülmittel"]
            : ["Bananas", "Tomatoes", "Cucumber", "Peppers", "Carrots", "Bread", "Pretzels", "Milk", "Eggs", "Yogurt",
               "Cheese", "Muesli", "Coffee", "Toilet paper", "Dish soap"]
        for name in open { repository.addShoppingItem(name, to: list) }
        repository.addShoppingItem(t("Äpfel", "Apples"), quantity: "1 kg", to: list)
        for name in german ? ["Butter", "Nudeln", "Waschmittel", "Gummibärchen"]
                           : ["Butter", "Pasta", "Laundry detergent", "Gummy bears"] {
            repository.setChecked(repository.addShoppingItem(name, to: list), true)
        }
        repository.addShoppingItem(t("Batterien", "Batteries"), to: .personal)

        // Todos
        repository.addTodo(t("Ferienwohnung buchen", "Book holiday flat"), dueDate: at(-2, 0), assignee: ben,
                           to: list, createdBy: by)
        repository.addTodo(t("Zimmer aufräumen", "Tidy room"), dueDate: at(0, 0), assignee: mia, to: list,
                           createdBy: by)
        repository.addTodo(t("Blumen gießen", "Water the plants"), dueDate: at(0, 0), assignee: leo,
                           recurrenceRule: "FREQ=DAILY;INTERVAL=3", to: list, createdBy: by)
        repository.addTodo(t("Mülltonnen rausstellen", "Take out the bins"), dueDate: at(1, 0), assignee: ben,
                           recurrenceRule: "FREQ=WEEKLY", to: list, createdBy: by)
        repository.addTodo(t("Schwimmkurs anmelden", "Sign up for swim lessons"), dueDate: at(4, 0),
                           assignee: anna, to: list, createdBy: by)
        repository.addTodo(t("Geschenk für Oma", "Present for Grandma"), dueDate: at(10, 0), assignee: anna,
                           to: list, createdBy: by)
        repository.addTodo(t("Fahrradlicht reparieren", "Fix bike light"), to: list, createdBy: by)
        _ = repository.complete(repository.addTodo(t("Turnbeutel waschen", "Wash PE kit"), to: list,
                                                   createdBy: by))
        repository.addTodo(t("Reisepass verlängern", "Renew passport"), dueDate: at(20, 0), to: .personal,
                           createdBy: nil)
        try? repository.save()
    }
}
#endif
