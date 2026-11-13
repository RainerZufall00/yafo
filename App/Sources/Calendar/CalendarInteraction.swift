import SwiftUI
import UniformTypeIdentifiers
import YafoKit

/// Was Wochen- und Monatsansicht beim Bedienen auslösen: lange auf einen Tag drücken legt einen Termin an,
/// ein Termin oder Todo lässt sich auf einen anderen Tag ziehen, ein Todo antippen öffnet es.
struct CalendarActions {
    var createEvent: (Date) -> Void = { _ in }
    var move: (CalendarEntry, Date) -> Void = { _, _ in }
    var openTodo: (TodoItem) -> Void = { _ in }
}

extension EnvironmentValues {
    @Entry var calendarActions = CalendarActions()
}

/// Einstellungen der Kalenderansicht, nur auf dem Gerät.
enum CalendarDisplay {
    static let showsTodosKey = "calendarShowsTodos"
    static let dismissedBirthdaysKey = "dismissedBirthdaySuggestions"
}

/// Der gerade gezogene Eintrag. Ziehen und Ablegen passieren in derselben App, daher reicht die ID hier;
/// das Ablegeziel muss so nichts asynchron aus dem `NSItemProvider` laden.
enum CalendarDrag {
    static var entryID: String?
}

extension View {
    /// Eigene Termine und Todos lassen sich mit langem Drücken anheben und auf einen anderen Tag ziehen.
    @ViewBuilder
    func calendarDraggable(_ entry: CalendarEntry) -> some View {
        if entry.isMovable {
            onDrag {
                CalendarDrag.entryID = entry.id
                return NSItemProvider(object: entry.title as NSString)
            }
        } else {
            self
        }
    }
}

/// Ablegen auf einem Tag; `day` rechnet die Position in den Tag um (im Monat je Spalte).
struct CalendarDropDelegate: DropDelegate {
    let day: (CGPoint) -> Date?
    @Binding var hovered: Date?
    let onDrop: (String, Date) -> Void

    func validateDrop(info: DropInfo) -> Bool { CalendarDrag.entryID != nil }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        hovered = day(info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { hovered = nil }

    func performDrop(info: DropInfo) -> Bool {
        hovered = nil
        guard let id = CalendarDrag.entryID, let target = day(info.location) else { return false }
        CalendarDrag.entryID = nil
        onDrop(id, target)
        return true
    }
}

extension View {
    /// Nimmt gezogene Einträge an; `entries` sind die der Seite, auf der abgelegt wird.
    func calendarDrop(entries: [CalendarEntry], hovered: Binding<Date?>, day: @escaping (CGPoint) -> Date?)
        -> some View {
        modifier(CalendarDropModifier(entries: entries, hovered: hovered, day: day))
    }
}

private struct CalendarDropModifier: ViewModifier {
    @Environment(\.calendarActions) private var actions
    let entries: [CalendarEntry]
    @Binding var hovered: Date?
    let day: (CGPoint) -> Date?

    func body(content: Content) -> some View {
        content.onDrop(of: [.plainText], delegate: CalendarDropDelegate(day: day, hovered: $hovered) { id, target in
            if let entry = entries.first(where: { $0.id == id }) { actions.move(entry, target) }
        })
    }
}

/// Stellt `CalendarActions` bereit und zeigt, was dazu gehört: Editor für neue Termine,
/// Rückfrage beim Verschieben einer Serie, Todo-Editor.
struct CalendarEditing: ViewModifier {
    @Environment(AppModel.self) private var model

    private struct NewEvent: Identifiable {
        let id = UUID()
        let day: Date
    }

    private struct PendingMove {
        let occurrence: Occurrence
        let day: Date
    }

    @State private var newEvent: NewEvent?
    @State private var pendingMove: PendingMove?
    @State private var editingTodo: TodoItem?
    @State private var feedback = 0

    func body(content: Content) -> some View {
        content
            .environment(\.calendarActions, CalendarActions(
                createEvent: { day in
                    feedback += 1
                    newEvent = NewEvent(day: day)
                },
                move: move,
                openTodo: { editingTodo = $0 }
            ))
            .sensoryFeedback(.impact(weight: .medium), trigger: feedback)
            .sheet(item: $newEvent) { new in
                EventEditorView(initialDay: new.day)
            }
            .sheet(item: $editingTodo) { todo in
                TodoEditorView(todo: todo, scope: todo.family.map(ListScope.family) ?? .personal)
            }
            .confirmationDialog("This is a repeating event.",
                                isPresented: Binding(get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } }),
                                titleVisibility: .visible, presenting: pendingMove) { pending in
                Button("Move This Event Only") { perform(pending, scope: .thisOccurrence) }
                Button("Move Future Events") { perform(pending, scope: .thisAndFollowing) }
                Button("Move All Events") { perform(pending, scope: .allOccurrences) }
                Button("Cancel", role: .cancel) {}
            }
    }

    private func move(_ entry: CalendarEntry, to day: Date) {
        if let todo = entry.todo {
            guard todo.dueDate.map({ !Calendar.current.isDate($0, inSameDayAs: day) }) ?? true else { return }
            withAnimation(.snappy) {
                model.repository.move(todo, toDay: day)
                model.save()
            }
            feedback += 1
            return
        }
        guard let occurrence = entry.occurrence,
              !Calendar.current.isDate(occurrence.start, inSameDayAs: day) else { return }
        if occurrence.isRecurring && !occurrence.event.isBirthday {
            pendingMove = PendingMove(occurrence: occurrence, day: day)
        } else {
            perform(PendingMove(occurrence: occurrence, day: day), scope: .allOccurrences)
        }
    }

    private func perform(_ pending: PendingMove, scope: SeriesScope) {
        withAnimation(.snappy) {
            model.repository.move(pending.occurrence.event, occurrence: pending.occurrence.originalStart,
                                  toDay: pending.day, scope: scope)
            model.save()
        }
        feedback += 1
        pendingMove = nil
    }
}
