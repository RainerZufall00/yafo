import SwiftUI
import UserNotifications
import YafoKit

/// Plant die nächsten 64 lokalen Benachrichtigungen neu (nach Speichern und Sync).
enum ReminderScheduler {
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func replace(with reminders: [PlannedReminder]) async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        center.removeAllPendingNotificationRequests()
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = title(of: reminder)
            content.body = body(of: reminder)
            content.sound = .default
            content.threadIdentifier = reminder.id.hasPrefix("todo") ? "todos" : "events"
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }

    private static func title(of reminder: PlannedReminder) -> String {
        if case .birthday = reminder.kind {
            return String(localized: "🎂 \(reminder.title)'s birthday")
        }
        return reminder.title
    }

    private static func body(of reminder: PlannedReminder) -> String {
        switch reminder.kind {
        case let .event(start, isAllDay, location):
            let day = dayText(start)
            let when = isAllDay ? day : "\(day), \(start.formatted(date: .omitted, time: .shortened))"
            return [when, location].compactMap { $0 }.joined(separator: " · ")
        case let .birthday(age):
            if let age { return String(localized: "Turns \(age)") }
            return String(localized: "Birthday")
        case let .todo(due):
            return String(localized: "Due \(dayText(due))")
        }
    }

    private static func dayText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInTomorrow(date) { return String(localized: "Tomorrow") }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// Auswahl der eigenen Erinnerung für einen Termin oder ein Todo.
/// „Standard“ folgt der Vorgabe am Eintrag, alles andere gilt nur für mich.
struct AlertPicker: View {
    @Environment(AppModel.self) private var model
    let itemID: UUID?
    /// Ganztägig und Todos: Offsets relativ zu 0 Uhr des Tages.
    let isDayBased: Bool
    let defaultOffset: Double

    /// Ganztägig: am Tag 9 Uhr, Vortag 18 Uhr, 2 Tage vorher 18 Uhr, eine Woche vorher 9 Uhr.
    private static let dayOptions: [Double] = [-32_400, 21_600, 108_000, 572_400]
    /// Mit Uhrzeit: zur Zeit, 5, 15, 30 Minuten, 1, 2 Stunden, 1 Tag vorher.
    private static let timeOptions: [Double] = [0, 300, 900, 1_800, 3_600, 7_200, 86_400]

    private var options: [Double] { isDayBased ? Self.dayOptions : Self.timeOptions }

    var body: some View {
        Picker("Reminder", systemImage: "bell", selection: Binding(
            get: { model.repository.alertSetting(for: itemID) },
            set: { setting in
                model.repository.setAlert(setting, for: itemID)
                model.save()
            }
        )) {
            Text("Default (\(Self.describe(defaultOffset, isDayBased: isDayBased)))").tag(AlertSetting.standard)
            Text("None").tag(AlertSetting.muted)
            ForEach(options, id: \.self) { offset in
                Text(Self.describe(offset, isDayBased: isDayBased)).tag(AlertSetting.offset(offset))
            }
            if case .offset(let own) = model.repository.alertSetting(for: itemID), !options.contains(own) {
                Text(Self.describe(own, isDayBased: isDayBased)).tag(AlertSetting.offset(own))
            }
        }
    }

    static func describe(_ offset: Double, isDayBased: Bool) -> String {
        if isDayBased {
            // Offset vor 0 Uhr: Tage davor und Uhrzeit an jenem Tag.
            let daysBefore = Int((offset / 86400).rounded(.up))
            let secondsIntoDay = Double(daysBefore) * 86400 - offset
            let time = Calendar.current.startOfDay(for: .now).addingTimeInterval(secondsIntoDay)
                .formatted(date: .omitted, time: .shortened)
            switch daysBefore {
            case ...0: return String(localized: "On the day at \(time)")
            case 1: return String(localized: "The day before at \(time)")
            case 7: return String(localized: "1 week before at \(time)")
            default: return String(localized: "\(daysBefore) days before at \(time)")
            }
        }
        switch offset {
        case 0: return String(localized: "At time of event")
        case 3600: return String(localized: "1 hour before")
        case 86400: return String(localized: "1 day before")
        case ..<3600: return String(localized: "\(Int(offset / 60)) minutes before")
        case ..<86400: return String(localized: "\(Int(offset / 3600)) hours before")
        default: return String(localized: "\(Int(offset / 86400)) days before")
        }
    }
}
