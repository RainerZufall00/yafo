import CoreData
import Foundation

/// Was exportiert wird: alles, nur die eigenen Daten oder eine Familie.
public enum ExportScope: Hashable {
    case all
    case personal
    case family(Family)

    func includes(_ family: Family?) -> Bool {
        switch self {
        case .all: true
        case .personal: family == nil
        case .family(let chosen): family == chosen
        }
    }
}

extension Repository {
    // MARK: Auswahl

    public func calendars(in scope: ExportScope) -> [EventCalendar] {
        calendars().filter { scope.includes($0.family) }
    }

    public func shoppingItems(in scope: ExportScope) -> [ShoppingItem] {
        let request = NSFetchRequest<ShoppingItem>(entityName: "ShoppingItem")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ShoppingItem.sortKey, ascending: true)]
        return ((try? context.fetch(request)) ?? []).filter { scope.includes($0.family) }
    }

    public func todoItems(in scope: ExportScope) -> [TodoItem] {
        let request = NSFetchRequest<TodoItem>(entityName: "TodoItem")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TodoItem.createdAt, ascending: true)]
        return ((try? context.fetch(request)) ?? []).filter { scope.includes($0.family) }
    }

    // MARK: ICS

    /// Termine der Kalender als eine ICS-Datei. ICS kennt keine Teilnehmer aus Kinderprofilen
    /// und keine Kommentare, beides steht deshalb als Text in der Beschreibung.
    public func icsDocument(for calendars: [EventCalendar], name: String? = nil) -> String {
        let events = calendars.flatMap { ($0.events ?? []).sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) } }
        let items = events.compactMap { event -> ICSWriter.Item? in
            guard let start = event.start, let end = event.end else { return nil }
            let overrides = (event.exceptions ?? []).compactMap { exception -> ICSWriter.Item.Override? in
                guard let original = exception.originalDate else { return nil }
                return ICSWriter.Item.Override(originalStart: original, isCancelled: exception.isCancelled,
                                               title: exception.title, start: exception.start, end: exception.end,
                                               location: exception.location, notes: exception.notes)
            }.sorted { $0.originalStart < $1.originalStart }
            return ICSWriter.Item(uid: event.importUID ?? "\(event.id?.uuidString ?? UUID().uuidString)@yafo",
                                  title: event.title ?? "", start: start, end: end, isAllDay: event.isAllDay,
                                  timeZone: event.timeZone, location: event.location,
                                  description: exportDescription(of: event), recurrenceRule: event.recurrenceRule,
                                  overrides: overrides)
        }
        return ICSWriter.document(name: name ?? (calendars.count == 1 ? calendars[0].name : "yafo"), items: items)
    }

    /// Notizen, Teilnehmer und Kommentare als lesbarer Text.
    public func exportDescription(of event: Event) -> String? {
        var parts: [String] = []
        if let notes = event.notes, !notes.isEmpty { parts.append(notes) }
        if event.isBirthday, event.birthYear > 0 {
            parts.append(String(localized: "Birthday (born \(String(event.birthYear)))"))
        }
        let names = (event.participants ?? []).compactMap(\.displayName).sorted()
        if !names.isEmpty {
            parts.append(String(localized: "Participants: \(names.joined(separator: ", "))"))
        }
        let comments = (event.comments ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        if !comments.isEmpty {
            let lines = comments.map { comment in
                "\(comment.author?.displayName ?? "?"): \(comment.text ?? "")"
            }
            parts.append(String(localized: "Comments:") + "\n" + lines.joined(separator: "\n"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    // MARK: CSV

    /// `aisleName` kommt aus der App, die die Abteilungen übersetzt.
    public func shoppingCSV(_ items: [ShoppingItem], aisleName: (ShoppingCategory) -> String = \.rawValue) -> String {
        CSVWriter.table(
            header: [String(localized: "Item"), String(localized: "Quantity"), String(localized: "Aisle"),
                     String(localized: "Bought"), String(localized: "List")],
            rows: items.map { item in
                [item.name ?? "", item.quantity ?? "", aisleName(item.category),
                 item.isChecked ? Self.csvDate(item.checkedAt) : "", item.family?.name ?? String(localized: "Just me")]
            })
    }

    public func todoCSV(_ items: [TodoItem]) -> String {
        CSVWriter.table(
            header: [String(localized: "To-do"), String(localized: "Due"), String(localized: "Repeats"),
                     String(localized: "Assigned to"), String(localized: "Done"), String(localized: "List")],
            rows: items.map { item in
                [item.title ?? "", Self.csvDate(item.dueDate, time: false), item.recurrenceRule ?? "",
                 item.assignee?.displayName ?? "", item.isDone ? Self.csvDate(item.doneAt) : "",
                 item.family?.name ?? String(localized: "Just me")]
            })
    }

    /// Ein Termin pro Zeile; Serien mit ihrer Regel statt aufgelöst.
    public func eventCSV(for calendars: [EventCalendar]) -> String {
        let events = calendars.flatMap { $0.events ?? [] }.sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
        return CSVWriter.table(
            header: [String(localized: "Title"), String(localized: "Start"), String(localized: "End"),
                     String(localized: "All day"), String(localized: "Calendar"), String(localized: "Location"),
                     String(localized: "Participants"), String(localized: "Repeats"), String(localized: "Notes")],
            rows: events.map { event in
                let lastDay = event.isAllDay ? event.end.map { $0.addingTimeInterval(-1) } : event.end
                return [event.title ?? "", Self.csvDate(event.start, time: !event.isAllDay),
                        Self.csvDate(lastDay, time: !event.isAllDay), event.isAllDay ? "1" : "",
                        event.calendar?.name ?? "", event.location ?? "",
                        (event.participants ?? []).compactMap(\.displayName).sorted().joined(separator: ", "),
                        event.recurrenceRule ?? "", event.notes ?? ""]
            })
    }

    /// ISO-ähnlich und sortierbar: `2026-11-03 18:30` bzw. `2026-11-03`.
    static func csvDate(_ date: Date?, time: Bool = true) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = time ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
