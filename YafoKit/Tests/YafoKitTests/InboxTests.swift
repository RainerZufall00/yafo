import CoreData
import Foundation
import Testing
@testable import YafoKit

@Suite struct InboxTests {
    let persistence: PersistenceController
    let repository: Repository
    let family: Family
    let inbox: AppGroupInbox

    init() throws {
        persistence = try PersistenceController.makeTemporary()
        repository = Repository(persistence: persistence)
        family = repository.createFamily(name: "Millers", ownerName: "Anna", ownerUserID: "anna", calendarName: "Family")
        inbox = AppGroupInbox(url: FileManager.default.temporaryDirectory
            .appending(path: "inbox-\(UUID().uuidString).json"))
    }

    @Test func appendAndDrain() throws {
        let id = UUID()
        try inbox.append(.checkShoppingItem(id))
        try inbox.append(.completeTodo(UUID()))
        #expect(inbox.pending().count == 2)
        #expect(inbox.pendingItemIDs().contains(id))

        let drained = try inbox.drain()
        #expect(drained.map(\.action).first == .checkShoppingItem(id))
        #expect(inbox.pending().isEmpty)
        #expect(try inbox.drain().isEmpty)
    }

    @Test func applyChecksItemsAndCompletesTodos() throws {
        let milk = repository.addShoppingItem("Milk", to: .family(family))
        let todo = repository.addTodo("Take out trash", to: .family(family), createdBy: nil)
        try repository.save()

        let result = repository.apply([
            .init(createdAt: .now, action: .checkShoppingItem(try #require(milk.id))),
            .init(createdAt: .now, action: .completeTodo(try #require(todo.id))),
            .init(createdAt: .now, action: .completeTodo(UUID())),
        ])
        #expect(result.checkedItems == 1 && result.completedTodos == 1 && result.skipped == 1)
        #expect(milk.isChecked)
        #expect(todo.isDone)
    }

    @Test func applyRollsRecurringTodosForward() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let todo = repository.addTodo("Water plants", dueDate: today, recurrenceRule: "FREQ=WEEKLY",
                                      to: .family(family), createdBy: nil)
        repository.apply([.init(createdAt: .now, action: .completeTodo(try #require(todo.id)))])
        #expect(!todo.isDone)
        #expect(todo.dueDate == calendar.date(byAdding: .day, value: 7, to: today))
    }

    @Test func snapshotCarriesListsAndCalendars() throws {
        repository.addShoppingItem("Milk", quantity: "2 l", to: .family(family))
        repository.addShoppingItem("Bread", to: .family(family))
        repository.addTodo("Call grandma", to: .personal, createdBy: nil)
        try repository.save()

        let snapshot = repository.widgetSnapshot(listKey: "personal")
        let familyList = try #require(snapshot.list(for: family.id?.uuidString))
        #expect(familyList.name == "Millers" && !familyList.isPersonal)
        #expect(familyList.shoppingCount == 2)
        // Laufreihenfolge: Backwaren vor Kühlregal.
        #expect(familyList.shopping.map(\.name) == ["Bread", "Milk"])
        #expect(familyList.shopping.last?.quantity == "2 l")
        #expect(snapshot.list(for: nil)?.key == "personal")
        #expect(snapshot.list(for: "personal")?.todos.map(\.title) == ["Call grandma"])
        #expect(snapshot.calendars.contains { $0.familyName == "Millers" })

        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
    }

    @Test func oldSnapshotsWithoutListsStillDecode() throws {
        let json = #"{"generatedAt": 0, "items": []}"#
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.lists.isEmpty && snapshot.calendars.isEmpty)
    }
}
