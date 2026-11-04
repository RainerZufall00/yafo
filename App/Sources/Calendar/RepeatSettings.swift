import Foundation
import SwiftUI
import YafoKit

/// Die Wiederholungs-Auswahl im Editor. Regeln, die sich damit nicht abbilden lassen
/// (z. B. aus einem Import), bleiben als „Benutzerdefiniert“ unverändert erhalten.
struct RepeatSettings: Equatable {
    enum Frequency: Hashable {
        case never, daily, weekly, biweekly, monthly, yearly, custom
    }

    enum End: Hashable {
        case never, onDate, afterCount
    }

    var frequency: Frequency = .never
    /// Wochentage wie bei `Calendar` (1 = Sonntag).
    var weekdays: Set<Int> = []
    var end: End = .never
    var endDate: Date
    var count = 10
    private var customRule: RecurrenceRule?

    init(rule string: String?, start: Date) {
        let calendar = Calendar.current
        endDate = calendar.date(byAdding: .month, value: 3, to: start) ?? start
        weekdays = [calendar.component(.weekday, from: start)]
        guard let rule = string.flatMap(RecurrenceRule.init(rrule:)) else { return }

        if let count = rule.count {
            end = .afterCount
            self.count = count
        } else if let until = rule.until {
            end = .onDate
            endDate = until
        }

        let plain = rule.byMonthDay.isEmpty && rule.byMonth.isEmpty && rule.otherParts.isEmpty
        let simpleWeekdays = rule.byDay.allSatisfy { $0.ordinal == nil }
        switch (rule.frequency, rule.interval) {
        case (.daily, 1) where plain && rule.byDay.isEmpty:
            frequency = .daily
        case (.weekly, 1) where plain && simpleWeekdays, (.weekly, 2) where plain && simpleWeekdays:
            frequency = rule.interval == 1 ? .weekly : .biweekly
            if !rule.byDay.isEmpty { weekdays = Set(rule.byDay.map(\.weekday)) }
        case (.monthly, 1) where plain && rule.byDay.isEmpty:
            frequency = .monthly
        case (.yearly, 1) where plain && rule.byDay.isEmpty:
            frequency = .yearly
        default:
            frequency = .custom
            customRule = rule
        }
    }

    var isCustomAvailable: Bool { customRule != nil }

    func ruleString(start: Date) -> String? {
        var rule: RecurrenceRule
        switch frequency {
        case .never: return nil
        case .daily: rule = RecurrenceRule(frequency: .daily)
        case .weekly, .biweekly:
            rule = RecurrenceRule(frequency: .weekly, interval: frequency == .weekly ? 1 : 2)
            let startWeekday = Calendar.current.component(.weekday, from: start)
            if weekdays != [startWeekday], !weekdays.isEmpty {
                rule.byDay = weekdays.sorted().map { RecurrenceRule.Weekday($0) }
            }
        case .monthly: rule = RecurrenceRule(frequency: .monthly)
        case .yearly: rule = RecurrenceRule(frequency: .yearly)
        case .custom:
            guard let customRule else { return nil }
            rule = customRule
        }
        rule.count = nil
        rule.until = nil
        switch end {
        case .never: break
        case .afterCount: rule.count = max(count, 1)
        case .onDate:
            // Der ganze letzte Tag zählt noch mit.
            let calendar = Calendar.current
            rule.until = calendar.date(byAdding: .second, value: 86_399, to: calendar.startOfDay(for: endDate))
        }
        return rule.rruleString
    }
}

/// Kurze Beschreibung einer Regel, z. B. „Wöchentlich am Mo, Mi“.
func repeatDescription(_ string: String?, start: Date) -> String? {
    guard let string, let rule = RecurrenceRule(rrule: string) else { return nil }
    let settings = RepeatSettings(rule: string, start: start)
    let symbols = Calendar.current.shortStandaloneWeekdaySymbols
    let days = rule.byDay.map { symbols[$0.weekday - 1] }.joined(separator: ", ")

    var text: String
    switch settings.frequency {
    case .daily: text = String(localized: "Every day")
    case .weekly: text = days.isEmpty ? String(localized: "Every week") : String(localized: "Every week on \(days)")
    case .biweekly: text = days.isEmpty ? String(localized: "Every 2 weeks") : String(localized: "Every 2 weeks on \(days)")
    case .monthly: text = String(localized: "Every month")
    case .yearly: text = String(localized: "Every year")
    case .never, .custom: text = String(localized: "Custom")
    }
    if let count = rule.count {
        text += ", " + String(localized: "\(count) times")
    } else if let until = rule.until {
        text += ", " + String(localized: "until \(until.formatted(date: .abbreviated, time: .omitted))")
    }
    return text
}

/// Wiederholung wählen: Rhythmus, Wochentage, Ende. Im Termin-Editor und in der Screenshot-Vorschau.
struct RepeatRows: View {
    @Binding var settings: RepeatSettings
    let start: Date

    var body: some View {
        Picker("Repeat", selection: $settings.frequency) {
            Text("Never").tag(RepeatSettings.Frequency.never)
            Text("Every Day").tag(RepeatSettings.Frequency.daily)
            Text("Every Week").tag(RepeatSettings.Frequency.weekly)
            Text("Every 2 Weeks").tag(RepeatSettings.Frequency.biweekly)
            Text("Every Month").tag(RepeatSettings.Frequency.monthly)
            Text("Every Year").tag(RepeatSettings.Frequency.yearly)
            if settings.isCustomAvailable {
                Text("Custom").tag(RepeatSettings.Frequency.custom)
            }
        }
        if settings.frequency == .weekly || settings.frequency == .biweekly {
            WeekdayChips(selection: $settings.weekdays)
        }
        if settings.frequency != .never {
            Picker("End Repeat", selection: $settings.end) {
                Text("Never").tag(RepeatSettings.End.never)
                Text("On Date").tag(RepeatSettings.End.onDate)
                Text("After").tag(RepeatSettings.End.afterCount)
            }
            switch settings.end {
            case .onDate:
                DatePicker("End Date", selection: $settings.endDate, in: start..., displayedComponents: .date)
            case .afterCount:
                Stepper("\(settings.count) times", value: $settings.count, in: 1...999)
            case .never:
                EmptyView()
            }
        }
    }
}

/// Wochentage für wöchentliche Serien, in der Reihenfolge des Kalenders.
struct WeekdayChips: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let calendar = Calendar.current
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        HStack(spacing: 6) {
            ForEach(order, id: \.self) { weekday in
                let isOn = selection.contains(weekday)
                Button {
                    // Mindestens ein Tag bleibt ausgewählt.
                    if isOn, selection.count > 1 { selection.remove(weekday) } else { selection.insert(weekday) }
                } label: {
                    Text(calendar.veryShortStandaloneWeekdaySymbols[weekday - 1])
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .background(Circle().fill(isOn ? Color.accentColor : Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(calendar.standaloneWeekdaySymbols[weekday - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
