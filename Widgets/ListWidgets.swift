import AppIntents
import SwiftUI
import UIKit
import WidgetKit
import YafoKit

// Einkaufsliste und Todos als Widgets. Wie bei den Termin-Widgets kommt alles aus dem
// Schnappschuss der App. Abhaken schreibt einen Auftrag ins Postfach der App Group; das Widget
// blendet den Eintrag sofort aus, die App erledigt ihn beim nächsten Öffnen und synchronisiert.

// MARK: - Liste wählen

struct ListEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "List" }
    static var defaultQuery: ListQuery { ListQuery() }

    let id: String
    let name: String

    init(_ list: WidgetSnapshot.ListEntry) {
        id = list.key
        name = list.name
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ListQuery: EntityQuery {
    func entities(for identifiers: [ListEntity.ID]) async throws -> [ListEntity] {
        WidgetSnapshot.load().lists.filter { identifiers.contains($0.key) }.map(ListEntity.init)
    }

    func suggestedEntities() async throws -> [ListEntity] {
        WidgetSnapshot.load().lists.map(ListEntity.init)
    }
}

struct SelectListIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Choose List" }
    static var description: IntentDescription { IntentDescription("Which family's list the widget shows.") }

    @Parameter(title: "List")
    var list: ListEntity?
}

// MARK: - Abhaken

struct CheckShoppingItemIntent: AppIntent {
    static var title: LocalizedStringResource { "Check Off Item" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Item")
    var itemID: String

    init() {}

    init(itemID: UUID) {
        self.itemID = itemID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: itemID) {
            try AppGroupInbox().append(.checkShoppingItem(id))
        }
        return .result()
    }
}

struct CompleteTodoIntent: AppIntent {
    static var title: LocalizedStringResource { "Complete To-do" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "To-do")
    var todoID: String

    init() {}

    init(todoID: UUID) {
        self.todoID = todoID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: todoID) {
            try AppGroupInbox().append(.completeTodo(id))
        }
        return .result()
    }
}

// MARK: - Daten

struct ListTimelineEntry: TimelineEntry {
    let date: Date
    let list: WidgetSnapshot.ListEntry?

    /// Ohne Einträge, die schon abgehakt im Postfach liegen.
    init(date: Date, list: WidgetSnapshot.ListEntry?, pending: Set<UUID> = []) {
        self.date = date
        guard var list else {
            self.list = nil
            return
        }
        let shopping = list.shopping.filter { !pending.contains($0.id) }
        let todos = list.todos.filter { !pending.contains($0.id) }
        list.shoppingCount -= list.shopping.count - shopping.count
        list.todoCount -= list.todos.count - todos.count
        list.shopping = shopping
        list.todos = todos
        self.list = list
    }
}

struct ListProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ListTimelineEntry {
        ListTimelineEntry(date: .now, list: ListSampleData.list)
    }

    func snapshot(for configuration: SelectListIntent, in context: Context) async -> ListTimelineEntry {
        let entry = makeEntry(for: configuration, at: .now)
        return context.isPreview && entry.list == nil ? placeholder(in: context) : entry
    }

    func timeline(for configuration: SelectListIntent, in context: Context) async -> Timeline<ListTimelineEntry> {
        // Um Mitternacht neu, damit „Heute“ und überfällige Todos stimmen; sonst lädt die App neu.
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))!
        return Timeline(entries: [makeEntry(for: configuration, at: .now)], policy: .after(midnight))
    }

    private func makeEntry(for configuration: SelectListIntent, at date: Date) -> ListTimelineEntry {
        let snapshot = WidgetSnapshot.load()
        return ListTimelineEntry(date: date, list: snapshot.list(for: configuration.list?.id),
                                 pending: AppGroupInbox().pendingItemIDs())
    }
}

// MARK: - Einkaufsliste

struct ShoppingListWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "de.yafo.shopping", intent: SelectListIntent.self, provider: ListProvider()) { entry in
            ShoppingListView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Shopping List")
        .description("What's still missing. Tap an item to check it off.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ShoppingListView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ListTimelineEntry

    private var columns: Int { family == .systemSmall ? 1 : 2 }
    private var rows: Int {
        // Eine Zeile ist mit Menge etwa 26 pt hoch; Kopfzeile und „+ n weitere“ brauchen auch Platz.
        switch family {
        case .systemLarge: 9
        default: 3
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ListHeader(list: entry.list, systemImage: "cart", count: entry.list?.shoppingCount ?? 0)
            if let items = entry.list?.shopping, !items.isEmpty {
                let capacity = columns * rows
                let shown = Array(items.prefix(capacity))
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
                    ForEach(0..<((shown.count + columns - 1) / columns), id: \.self) { row in
                        GridRow {
                            ForEach(0..<columns, id: \.self) { column in
                                let index = row * columns + column
                                if index < shown.count {
                                    ShoppingRow(item: shown[index])
                                } else {
                                    Color.clear.frame(height: 1)
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                let more = (entry.list?.shoppingCount ?? 0) - shown.count
                if more > 0 {
                    Text("+ \(more) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                EmptyListView(systemImage: "cart", text: String(localized: "Nothing to buy"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "yafo://shopping?list=\(entry.list?.key ?? "")"))
    }
}

struct ShoppingRow: View {
    let item: WidgetSnapshot.ShoppingEntry

    var body: some View {
        Button(intent: CheckShoppingItemIntent(itemID: item.id)) {
            HStack(spacing: 6) {
                WidgetItemIcon(icon: item.icon, emoji: item.emoji)
                    .foregroundStyle(.white)
                    .padding(3)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: item.colorHex)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if let quantity = item.quantity {
                        Text(quantity)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .invalidatableContent()
        .accessibilityLabel(Text("Check off \(item.name)"))
    }
}

/// Wie `ItemIcon` in der App: gezeichnete Grafik, sonst das Emoji.
struct WidgetItemIcon: View {
    let icon: String
    let emoji: String

    var body: some View {
        let name = "item-\(icon)"
        if UIImage(named: name) != nil {
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
        } else {
            Text(emoji)
                .font(.system(size: 13))
                .minimumScaleFactor(0.5)
        }
    }
}

// MARK: - Todos

struct TodoListWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "de.yafo.todos", intent: SelectListIntent.self, provider: ListProvider()) { entry in
            TodoListView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("To-dos")
        .description("Open to-dos, due ones first. Tap the circle to complete one.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct TodoListView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ListTimelineEntry

    private var capacity: Int {
        switch family {
        case .systemLarge: 9
        default: 3
        }
    }

    var body: some View {
        if family == .accessoryRectangular {
            accessory
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ListHeader(list: entry.list, systemImage: "checklist", count: entry.list?.todoCount ?? 0)
                if let todos = entry.list?.todos, !todos.isEmpty {
                    let shown = Array(todos.prefix(capacity))
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(shown) { todo in
                            TodoRow(todo: todo, today: entry.date, compact: family == .systemSmall)
                        }
                    }
                    Spacer(minLength: 0)
                    let more = (entry.list?.todoCount ?? 0) - shown.count
                    if more > 0 {
                        Text("+ \(more) more")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    EmptyListView(systemImage: "checkmark.circle", text: String(localized: "All done"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(URL(string: "yafo://todos?list=\(entry.list?.key ?? "")"))
        }
    }

    /// Sperrbildschirm: die nächsten drei Todos als Text.
    private var accessory: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(entry.list?.name ?? String(localized: "To-dos"), systemImage: "checklist")
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            if let todos = entry.list?.todos, !todos.isEmpty {
                ForEach(todos.prefix(capacity)) { todo in
                    Text(todo.title)
                        .font(.caption)
                        .lineLimit(1)
                }
            } else {
                Text("All done")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "yafo://todos?list=\(entry.list?.key ?? "")"))
    }
}

struct TodoRow: View {
    let todo: WidgetSnapshot.TodoEntry
    let today: Date
    let compact: Bool

    var body: some View {
        HStack(spacing: 7) {
            Button(intent: CompleteTodoIntent(todoID: todo.id)) {
                Image(systemName: "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isOverdue ? Color.red : Color.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .invalidatableContent()
            .accessibilityLabel(Text("Complete \(todo.title)"))

            VStack(alignment: .leading, spacing: 0) {
                Text(todo.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let due = dueText {
                    HStack(spacing: 3) {
                        Text(due)
                        if todo.isRecurring {
                            Image(systemName: "repeat")
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(isOverdue ? Color.red : Color.secondary)
                    .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if !compact, let initials = todo.assigneeInitials {
                Text(initials)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
        }
    }

    private var isOverdue: Bool {
        guard let due = todo.dueDate else { return false }
        return due < Calendar.current.startOfDay(for: today)
    }

    private var dueText: String? {
        guard let due = todo.dueDate else { return nil }
        let calendar = Calendar.current
        if calendar.isDate(due, inSameDayAs: today) { return String(localized: "Today") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), calendar.isDate(due, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow")
        }
        return due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

// MARK: - Gemeinsame Teile

struct ListHeader: View {
    let list: WidgetSnapshot.ListEntry?
    let systemImage: String
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
            if list?.isPersonal == true {
                Image(systemName: "lock.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
            }
            Text(list?.name ?? "yafo")
                .lineLimit(1)
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.semibold))
    }
}

struct EmptyListView: View {
    let systemImage: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum ListSampleData {
    static var list: WidgetSnapshot.ListEntry {
        let shopping: [WidgetSnapshot.ShoppingEntry] = [
            .init(id: UUID(), name: String(localized: "Apples"), quantity: "1 kg", emoji: "🍎", icon: "apple",
                  colorHex: ShoppingCategory.produce.colorHex),
            .init(id: UUID(), name: String(localized: "Bread"), quantity: nil, emoji: "🍞", icon: "bread",
                  colorHex: ShoppingCategory.bakery.colorHex),
            .init(id: UUID(), name: String(localized: "Milk"), quantity: "2", emoji: "🥛", icon: "milk",
                  colorHex: ShoppingCategory.dairy.colorHex),
        ]
        let todos: [WidgetSnapshot.TodoEntry] = [
            .init(id: UUID(), title: String(localized: "Take out the trash"), dueDate: .now, assigneeInitials: "M",
                  isRecurring: true),
            .init(id: UUID(), title: String(localized: "Sign permission slip"), dueDate: nil, assigneeInitials: nil,
                  isRecurring: false),
        ]
        return WidgetSnapshot.ListEntry(key: "sample", name: String(localized: "Family"), isPersonal: false,
                                        shoppingCount: shopping.count, shopping: shopping,
                                        todoCount: todos.count, todos: todos)
    }
}
