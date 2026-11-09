import CoreData
import Foundation

/// Was beim Abarbeiten des Postfachs passiert ist.
nonisolated public struct InboxResult: Equatable, Sendable {
    public var checkedItems = 0
    public var completedTodos = 0
    /// Aufträge, deren Objekt es nicht mehr gibt (z. B. auf einem anderen Gerät gelöscht).
    public var skipped = 0

    public init() {}

    public var changedSomething: Bool { checkedItems + completedTodos > 0 }
}

extension Repository {
    /// Führt Aufträge aus den Widgets aus.
    @discardableResult
    public func apply(_ entries: [AppGroupInbox.Entry]) -> InboxResult {
        var result = InboxResult()
        for entry in entries {
            switch entry.action {
            case .checkShoppingItem(let id):
                if let item = object(ShoppingItem.self, id: id) {
                    if !item.isChecked { setChecked(item, true) }
                    result.checkedItems += 1
                } else {
                    result.skipped += 1
                }
            case .completeTodo(let id):
                if let todo = object(TodoItem.self, id: id), !todo.isDone {
                    complete(todo, today: entry.createdAt)
                    result.completedTodos += 1
                } else {
                    result.skipped += 1
                }
            }
        }
        return result
    }
}
