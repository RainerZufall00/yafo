#if DEBUG
import SwiftUI
import UIKit
import YafoKit

/// Screenshots für den App Store, per Startargument `-screenshotDemo` (nur Debug):
/// leere Stores im Speicher, Beispielfamilie aus `DemoData`, keine Nachfrage nach Mitteilungen.
/// `-demoScreen <name>` öffnet direkt eine Ansicht, die sich sonst nur per Tippen erreichen ließe:
///
/// | Name | Ansicht |
/// | --- | --- |
/// | `day` | Tagesseite von heute (iPhone; auf dem iPad steht die Tagesliste ohnehin neben dem Monat) |
/// | `event` | Ausflug mit Teilnehmern und Kommentaren |
/// | `family` | Familie mit Mitgliedern und Kalendern |
/// | `screenshot` | „Termin aus Screenshot“ mit einem gezeichneten Elternbrief |
///
/// Tab, Kalenderansicht und Bedienung kommen als normale Startargumente für die UserDefaults dazu,
/// z. B. `-launchTab shopping`, `-calendarMode week`, `-interfaceStyle swipe`, `-yafoOnboarding`.
/// Aufnahmen: `AppStore/Tools/capture-screenshots.sh`.
enum ScreenshotDemo {
    static let isActive = ProcessInfo.processInfo.arguments.contains("-screenshotDemo")

    static var screen: String? {
        isActive ? UserDefaults.standard.string(forKey: "demoScreen") : nil
    }

    private static var shown: Set<String> = []

    /// `true` genau einmal, wenn `-demoScreen` diese Ansicht verlangt.
    static func take(_ name: String) -> Bool {
        guard screen == name, !shown.contains(name) else { return false }
        shown.insert(name)
        return true
    }

    private static var german: Bool { Bundle.main.preferredLocalizations.first?.hasPrefix("de") ?? false }

    /// Tage der beiden Termine im Elternbrief: Freitag nächster Woche, Dienstag übernächster Woche.
    private static var letterDays: (festival: Date, meeting: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func next(_ weekday: Int, weeksAhead: Int) -> Date {
            let base = cal.date(byAdding: .weekOfYear, value: weeksAhead, to: today)!
            return cal.nextDate(after: base, matching: DateComponents(weekday: weekday), matchingPolicy: .nextTime)!
        }
        return (next(6, weeksAhead: 1), next(3, weeksAhead: 2))
    }

    /// Was die Erkennung mit Apple Intelligence aus dem Elternbrief liest. Im Simulator gibt es kein
    /// Sprachmodell; ohne diese Vorgabe zeigte die Aufnahme nur die schwächere Erkennung per Datumssuche.
    static var letterReading: ScreenshotReader.Result? {
        guard screen == "screenshot" else { return nil }
        let (festival, meeting) = letterDays
        func at(_ day: Date, _ hour: Int, _ minute: Int = 0) -> Date {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        var first = EventProposal(title: german ? "Lichterfest" : "Lantern festival", start: at(festival, 15),
                                  end: at(festival, 18), isAllDay: false,
                                  location: german ? "Kita Sonnenschein, Garten" : "Sunshine Nursery, garden")
        var second = EventProposal(title: german ? "Elternabend Igelgruppe" : "Parents' evening (Hedgehogs)",
                                   start: at(meeting, 19, 30), end: at(meeting, 21), isAllDay: false,
                                   location: german ? "Kita Sonnenschein, Turnraum" : "Sunshine Nursery, gym")
        // Erfundener Ort mit Koordinaten, damit keine echten Adressvorschläge erscheinen.
        first.geo = "48.137,11.575"
        second.geo = "48.137,11.575"
        return ScreenshotReader.Result(proposals: [first, second], method: .imageModel)
    }

    /// Elternbrief als Bild für „Termin aus Screenshot“. Die Termine liegen in den nächsten Wochen.
    @MainActor
    static func letter() -> UIImage {
        let locale = Locale(identifier: german ? "de_DE" : "en_US")
        func day(_ date: Date) -> String {
            date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
        }
        let (festival, meeting) = letterDays
        let view = LetterView(
            school: german ? "Kita Sonnenschein" : "Sunshine Nursery",
            heading: german ? "Liebe Eltern," : "Dear parents,",
            lines: german
                ? ["unser Lichterfest feiern wir am \(day(festival)) von 15:00 bis 18:00 Uhr im Garten der Kita.",
                   "Der Elternabend der Igelgruppe ist am \(day(meeting)) um 19:30 Uhr im Turnraum.",
                   "Wir freuen uns auf euch!"]
                : ["Our lantern festival takes place on \(day(festival)) from 3:00 to 6:00 PM in the nursery garden.",
                   "The parents' evening for the Hedgehog group is on \(day(meeting)) at 7:30 PM in the gym.",
                   "We look forward to seeing you!"],
            signature: german ? "Euer Kita-Team" : "Your nursery team")
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage ?? UIImage()
    }
}

/// Gezeichneter Elternbrief – frei erfunden, ohne fremde Marken.
private struct LetterView: View {
    let school: String
    let heading: String
    let lines: [String]
    let signature: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.orange)
                Text(school)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
            }
            Text(heading).font(.system(size: 18, weight: .semibold))
            ForEach(lines, id: \.self) { line in
                Text(line).font(.system(size: 18))
            }
            Text(signature).font(.system(size: 18, weight: .medium)).italic()
        }
        .foregroundStyle(Color(white: 0.15))
        .padding(28)
        .frame(width: 520, alignment: .leading)
        .background(Color(red: 1, green: 0.98, blue: 0.93))
    }
}
#endif
