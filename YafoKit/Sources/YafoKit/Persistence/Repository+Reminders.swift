import CoreData
import Foundation

/// Eine geplante lokale Benachrichtigung. Den Text baut die App (lokalisiert).
public struct PlannedReminder: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case event(start: Date, isAllDay: Bool, location: String?)
        case birthday(age: Int?)
        case todo(due: Date)
    }

    /// Stabil je Vorkommen, damit ein Neuplanen dieselben Benachrichtigungen ersetzt.
    public let id: String
    public let fireDate: Date
    public let title: String
    public let kind: Kind
}

extension Repository {
    /// iOS hält höchstens 64 geplante lokale Benachrichtigungen.
    public static let reminderLimit = 64

    // MARK: Eigene Einstellung (AlertPreference)

    public func alertPreference(for itemID: UUID?) -> AlertPreference? {
        guard let itemID else { return nil }
        let request = NSFetchRequest<AlertPreference>(entityName: "AlertPreference")
        request.predicate = NSPredicate(format: "itemID == %@", itemID.uuidString)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// Eigene Erinnerung für einen Termin oder ein Todo: Offset, stumm oder `nil` für die Vorgabe.
    /// Liegt immer im privaten Store, andere sehen sie nicht.
    public func setAlert(_ setting: AlertSetting, for itemID: UUID?) {
        guard let itemID else { return }
        let existing = alertPreference(for: itemID)
        switch setting {
        case .standard:
            if let existing { delete(existing) }
        case .muted, .offset:
            let preference = existing ?? insert(AlertPreference.self, into: persistence.privateStore)
            preference.itemID = itemID.uuidString
            preference.isMuted = setting == .muted
            if case .offset(let offset) = setting { preference.alertOffset = offset }
        }
    }

    public func alertSetting(for itemID: UUID?) -> AlertSetting {
        guard let preference = alertPreference(for: itemID) else { return .standard }
        return preference.isMuted ? .muted : .offset(preference.alertOffset)
    }

    /// Wirksamer Offset in Sekunden vor dem Bezugszeitpunkt; `nil` = stumm.
    public func effectiveAlertOffset(itemID: UUID?, default offset: Double) -> Double? {
        switch alertSetting(for: itemID) {
        case .standard: offset
        case .muted: nil
        case .offset(let own): own
        }
    }

    // MARK: Planung

    /// Die nächsten Erinnerungen ab `now`, früheste zuerst, höchstens `limit`.
    /// `me` liefert das eigene Profil in einer Familie (für Teilnehmer und Zuständige).
    public func plannedReminders(now: Date = .now, days: Int = 60, limit: Int = reminderLimit,
                                 me: (Family) -> Member?) -> [PlannedReminder] {
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .day, value: days, to: now)!
        // Ab heute 0 Uhr (Ganztägiges erinnert auch am Tag selbst) bis eine Woche nach dem
        // Horizont, weil Erinnerungen vor dem Termin feuern.
        let window = DateInterval(start: calendar.startOfDay(for: now),
                                  end: calendar.date(byAdding: .day, value: 8, to: horizon)!)
        var reminders: [PlannedReminder] = []

        for occurrence in occurrences(overlapping: window) where occurrence.start >= window.start {
            let event = occurrence.event
            guard isRecipient(of: event, me: me),
                  let offset = effectiveAlertOffset(itemID: event.id, default: event.defaultAlertOffset)
            else { continue }
            let reference = occurrence.isAllDay ? calendar.startOfDay(for: occurrence.start) : occurrence.start
            let fireDate = reference.addingTimeInterval(-offset)
            guard fireDate > now, fireDate < horizon else { continue }
            let kind: PlannedReminder.Kind = event.isBirthday
                ? .birthday(age: occurrence.age)
                : .event(start: occurrence.start, isAllDay: occurrence.isAllDay, location: occurrence.location)
            reminders.append(PlannedReminder(id: "event-\(event.id?.uuidString ?? "")-\(Int(occurrence.originalStart.timeIntervalSince1970))",
                                             fireDate: fireDate, title: occurrence.title, kind: kind))
        }

        let request = NSFetchRequest<TodoItem>(entityName: "TodoItem")
        request.predicate = NSPredicate(format: "isDone == NO AND dueDate != nil")
        for todo in (try? context.fetch(request)) ?? [] {
            guard let due = todo.dueDate, isRecipient(of: todo, me: me),
                  let offset = effectiveAlertOffset(itemID: todo.id, default: todo.defaultAlertOffset)
            else { continue }
            let fireDate = calendar.startOfDay(for: due).addingTimeInterval(-offset)
            guard fireDate > now, fireDate < horizon else { continue }
            reminders.append(PlannedReminder(id: "todo-\(todo.id?.uuidString ?? "")-\(Int(due.timeIntervalSince1970))",
                                             fireDate: fireDate, title: todo.title ?? "", kind: .todo(due: due)))
        }

        return Array(reminders.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }.prefix(limit))
    }

    /// Erinnert werden erwachsene Teilnehmer und Teenager mit Account; ohne Teilnehmer
    /// oder nur mit Kinderprofilen alle Erwachsenen. Eigene Kalender immer.
    func isRecipient(of event: Event, me: (Family) -> Member?) -> Bool {
        guard let family = event.calendar?.family else { return true }
        guard let myself = me(family) else { return false }
        let withAccount = (event.participants ?? []).filter(\.hasAccount)
        if withAccount.isEmpty { return myself.kind == .adult || myself.hasAccount }
        return withAccount.contains(myself)
    }

    /// Todos: die zuständige Person mit Account, sonst alle Erwachsenen. Private immer.
    func isRecipient(of todo: TodoItem, me: (Family) -> Member?) -> Bool {
        guard let family = todo.family else { return true }
        guard let myself = me(family) else { return false }
        if let assignee = todo.assignee, assignee.hasAccount { return assignee == myself }
        return myself.kind == .adult || myself.hasAccount
    }
}

/// Eigene Erinnerungseinstellung zu einem Termin oder Todo.
public enum AlertSetting: Hashable, Sendable {
    /// Vorgabe am Termin bzw. Todo.
    case standard
    case muted
    /// Sekunden vor Beginn (ganztägig/Todos: vor 0 Uhr des Tages, negativ = danach).
    case offset(Double)
}
