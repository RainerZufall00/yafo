import CoreData
import Foundation
import Testing
@testable import YafoKit

@Suite struct ShoppingListTests {
    let persistence: PersistenceController
    let repository: Repository
    let family: Family

    init() throws {
        persistence = try PersistenceController.makeTemporary()
        repository = Repository(persistence: persistence)
        family = repository.createFamily(name: "Millers", ownerName: "Anna", ownerUserID: "anna", calendarName: "Family")
    }

    @Test func itemsKeepTheirOrderAndScope() throws {
        repository.addShoppingItem("Milk", to: .family(family))
        repository.addShoppingItem("Bread", quantity: "2", to: .family(family))
        repository.addShoppingItem("Batteries", to: .personal)
        try repository.save()

        let familyItems = repository.openShoppingItems(in: .family(family))
        #expect(familyItems.map(\.name) == ["Milk", "Bread"])
        #expect(familyItems.last?.quantity == "2")
        #expect(familyItems.allSatisfy { $0.family == family })
        #expect(repository.openShoppingItems(in: .personal).map(\.name) == ["Batteries"])
        #expect(repository.openShoppingItems(in: .personal).first?.family == nil)
    }

    @Test func checkingMovesToRecentlyBought() {
        let milk = repository.addShoppingItem("Milk", to: .family(family))
        repository.addShoppingItem("Bread", to: .family(family))
        repository.setChecked(milk, true)

        #expect(milk.checkedAt != nil)
        #expect(repository.openShoppingItems(in: .family(family)).map(\.name) == ["Bread"])
        #expect(repository.recentlyBought(in: .family(family)).map(\.name) == ["Milk"])

        repository.setChecked(milk, false)
        #expect(milk.checkedAt == nil)
        #expect(repository.openShoppingItems(in: .family(family)).map(\.name) == ["Bread", "Milk"])
    }

    @Test func addingABoughtItemAgainReusesIt() {
        let milk = repository.addShoppingItem("Milk", to: .family(family))
        repository.setChecked(milk, true)

        let again = repository.addShoppingItem("milk ", quantity: "1 l", to: .family(family))
        #expect(again == milk)
        #expect(!again.isChecked && again.quantity == "1 l")
        #expect(repository.recentlyBought(in: .family(family)).isEmpty)
        #expect(repository.addShoppingItem("Milk", to: .family(family)) == milk)
        #expect(repository.openShoppingItems(in: .family(family)).count == 1)
    }

    @Test func suggestionsComeFromRecentlyBought() {
        for name in ["Milk", "Mint", "Mozzarella", "Bread"] {
            repository.setChecked(repository.addShoppingItem(name, to: .family(family)), true)
        }
        repository.addShoppingItem("Mozzarella", to: .family(family))
        #expect(Set(repository.shoppingSuggestions(for: "m", in: .family(family))) == ["Milk", "Mint"])
        #expect(repository.shoppingSuggestions(for: "", in: .family(family)).isEmpty)
        #expect(repository.shoppingSuggestions(for: "m", in: .personal).isEmpty)
    }

    @Test func reorderWritesSortKeys() {
        let a = repository.addShoppingItem("A", to: .personal)
        let b = repository.addShoppingItem("B", to: .personal)
        let c = repository.addShoppingItem("C", to: .personal)
        repository.reorder([c, a, b])
        #expect(repository.openShoppingItems(in: .personal).map(\.name) == ["C", "A", "B"])
    }
}

@Suite struct TodoTests {
    let persistence: PersistenceController
    let repository: Repository
    let family: Family
    let cal = Calendar.current

    init() throws {
        persistence = try PersistenceController.makeTemporary()
        repository = Repository(persistence: persistence)
        family = repository.createFamily(name: "Millers", ownerName: "Anna", ownerUserID: "anna", calendarName: "Family")
    }

    func date(_ month: Int, _ day: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    @Test func openTodosAreSortedByDueDate() {
        repository.addTodo("Someday", to: .family(family), createdBy: nil)
        repository.addTodo("Later", dueDate: date(11, 20), to: .family(family), createdBy: nil)
        repository.addTodo("Soon", dueDate: date(11, 3), to: .family(family), createdBy: nil)
        repository.addTodo("Private", to: .personal, createdBy: nil)
        #expect(repository.openTodos(in: .family(family)).map(\.title) == ["Soon", "Later", "Someday"])
        #expect(repository.openTodos(in: .personal).map(\.title) == ["Private"])
    }

    @Test func assigneeMustBelongToTheFamily() {
        let mia = repository.addChildProfile(name: "Mia", to: family)
        let other = repository.createFamily(name: "Others", ownerName: "Olga", ownerUserID: nil, calendarName: "X")
        let todo = repository.addTodo("Tidy room", assignee: mia, to: .family(family), createdBy: nil)
        #expect(todo.assignee == mia)
        let foreign = repository.addTodo("Mow", assignee: mia, to: .family(other), createdBy: nil)
        #expect(foreign.assignee == nil)
        let personal = repository.addTodo("Mine", assignee: mia, to: .personal, createdBy: nil)
        #expect(personal.assignee == nil)
    }

    @Test func completingAndReopening() {
        let todo = repository.addTodo("Call grandma", dueDate: date(11, 3), to: .personal, createdBy: nil)
        #expect(repository.complete(todo, today: date(11, 2)) == nil)
        #expect(todo.isDone && todo.doneAt != nil)
        #expect(repository.doneTodos(in: .personal) == [todo])
        repository.reopen(todo)
        #expect(!todo.isDone && todo.doneAt == nil)
    }

    @Test func seriesRollsToTheNextDueDate() {
        let bins = repository.addTodo("Bins out", dueDate: date(11, 2), recurrenceRule: "FREQ=WEEKLY",
                                      to: .family(family), createdBy: nil)
        #expect(repository.complete(bins, today: date(11, 2)) == date(11, 9))
        #expect(!bins.isDone && bins.dueDate == date(11, 9))
    }

    @Test func overdueSeriesRollsToTodayOrLater() {
        let plants = repository.addTodo("Water plants", dueDate: date(10, 1), recurrenceRule: "FREQ=WEEKLY",
                                        to: .personal, createdBy: nil)
        // 1.10. ist ein Donnerstag; nächster Donnerstag ab dem 2.11. ist der 5.11.
        #expect(repository.complete(plants, today: date(11, 2)) == date(11, 5))
    }

    @Test func seriesNeedsADueDate() {
        let todo = repository.addTodo("No date", recurrenceRule: "FREQ=DAILY", to: .personal, createdBy: nil)
        #expect(todo.recurrenceRule == nil)
        #expect(repository.complete(todo) == nil)
        #expect(todo.isDone)
    }

    @Test func seriesEndsWithUntil() {
        let todo = repository.addTodo("Course", dueDate: date(11, 2),
                                      recurrenceRule: "FREQ=WEEKLY;UNTIL=20261105T000000Z",
                                      to: .personal, createdBy: nil)
        #expect(repository.complete(todo, today: date(11, 2)) == nil)
        #expect(todo.isDone)
    }
}

@Suite struct ShoppingCatalogTests {
    @Test func knownArticlesInBothLanguages() {
        #expect(ShoppingCatalog.article(for: "Milch")?.emoji == "🥛")
        #expect(ShoppingCatalog.article(for: "milk")?.category == .dairy)
        #expect(ShoppingCatalog.category(for: "Äpfel") == .produce)
        #expect(ShoppingCatalog.category(for: "aepfel") == .other)
        #expect(ShoppingCatalog.category(for: "Klopapier") == .household)
    }

    @Test func compoundsUseTheirLastWord() {
        #expect(ShoppingCatalog.article(for: "Vollkornbrot")?.emoji == "🍞")
        #expect(ShoppingCatalog.category(for: "Vollmilch") == .dairy)
        #expect(ShoppingCatalog.category(for: "Milchreis") == .pantry)
        #expect(ShoppingCatalog.category(for: "Pfefferminztee") == .breakfast)
        #expect(ShoppingCatalog.category(for: "Organic milk") == .dairy)
        #expect(ShoppingCatalog.category(for: "Flux capacitor") == .other)
    }

    @Test func suggestionsByPrefix() {
        let german = ShoppingCatalog.suggestions(for: "mil", languageCode: "de")
        #expect(german.contains("Milch"))
        #expect(ShoppingCatalog.suggestions(for: "mil", languageCode: "en").contains("Milk"))
        #expect(ShoppingCatalog.suggestions(for: " ", languageCode: "de").isEmpty)
        // Der passende Name, nicht der erste seiner Gruppe.
        #expect(ShoppingCatalog.suggestions(for: "majo", languageCode: "de").contains("Majoran"))
        #expect(ShoppingCatalog.suggestions(for: "cinna", languageCode: "de") == ["Zimt"])
    }

    @Test func spicesAndBabyItems() {
        #expect(ShoppingCatalog.category(for: "Zimt") == .pantry)
        #expect(ShoppingCatalog.category(for: "Oregano") == .pantry)
        #expect(ShoppingCatalog.category(for: "Paprikapulver") == .pantry)
        #expect(ShoppingCatalog.category(for: "Paprika") == .produce)
        #expect(ShoppingCatalog.article(for: "Windeln")?.emoji == "🧷")
        #expect(ShoppingCatalog.article(for: "Feuchttücher")?.category == .baby)
        #expect(ShoppingCatalog.article(for: "Feuchttücher")?.emoji != ShoppingCatalog.article(for: "Klopapier")?.emoji)
    }

    @Test func listIsSortedByAisle() throws {
        let persistence = try PersistenceController.makeTemporary()
        let repository = Repository(persistence: persistence)
        for name in ["Shampoo", "Milch", "Bananen", "Brot", "Gizmo"] {
            repository.addShoppingItem(name, to: .personal)
        }
        let groups = repository.openShoppingItemsByAisle(in: .personal)
        #expect(groups.map(\.category) == [.produce, .bakery, .dairy, .hygiene, .other])

        let gizmo = groups.last!.items[0]
        repository.setCategory(.household, of: gizmo)
        #expect(gizmo.category == .household && gizmo.emoji == ShoppingCategory.household.emoji)
        #expect(repository.openShoppingItemsByAisle(in: .personal).map(\.category).last == .hygiene)
    }

    @Test func completionsPreferRecentlyBought() throws {
        let persistence = try PersistenceController.makeTemporary()
        let repository = Repository(persistence: persistence)
        repository.setChecked(repository.addShoppingItem("Mandelmus", to: .personal), true)
        let completions = repository.shoppingCompletions(for: "man", in: .personal)
        #expect(completions.first == "Mandelmus")
    }
}

@Suite struct ShoppingDetailsTests {
    @Test func amountsReplaceEachOtherAndComeFirst() {
        var text = ShoppingDetails.toggle("AA (Mignon)", in: "")
        text = ShoppingDetails.toggle("4", in: text)
        #expect(text == "4, AA (Mignon)")
        text = ShoppingDetails.toggle("10", in: text)
        #expect(text == "10, AA (Mignon)")
        #expect(ShoppingDetails.contains("aa (mignon)", in: text))
    }

    @Test func togglingTwiceRemovesAndKeepsFreeText() {
        let text = ShoppingDetails.toggle("Bio", in: "500 g")
        #expect(text == "500 g, Bio")
        #expect(ShoppingDetails.toggle("Bio", in: text) == "500 g")
    }

    @Test func variantsComeFromTheArticleGroup() {
        #expect(ShoppingDetails.variants(for: "Batterien", languageCode: "de").contains("AA (Mignon)"))
        #expect(ShoppingDetails.variants(for: "batteries", languageCode: "en").contains("AA"))
        #expect(ShoppingDetails.variants(for: "Vollmilch", languageCode: "de").contains("laktosefrei"))
        #expect(ShoppingDetails.variants(for: "Flux capacitor").isEmpty)
    }
}

@Suite struct ShoppingIconTests {
    /// Jede Grafik, die Katalog und Abteilungen nennen, liegt als Imageset in der App.
    @Test func everyIconHasAnAsset() throws {
        let items = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "App/Resources/Assets.xcassets/Items")
        let existing = try FileManager.default.contentsOfDirectory(atPath: items.path(percentEncoded: false))
        let missing = ShoppingCatalog.allIcons.filter { !existing.contains("item-\($0).imageset") }
        #expect(missing.isEmpty, "Fehlende Icons: \(missing.sorted())")
    }
}
