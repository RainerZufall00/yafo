import CoreData
import SwiftUI
import YafoKit

/// Todos einer Familie oder privat: fällige zuerst, mit zuständiger Person und Wiederholung.
/// Abhaken einer Serie rollt sie auf das nächste Fälligkeitsdatum weiter.
struct TodoView: View {
    @Environment(AppModel.self) private var model
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)])
    private var families: FetchedResults<Family>

    var body: some View {
        let scope = model.listScope(families: families)
        NavigationStack {
            TodoListContent(scope: scope)
                .id(scope)
                .safeAreaInset(edge: .top, spacing: 0) {
                    PersonalListBanner(families: families)
                }
                .navigationTitle("To-dos")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        ListScopeMenu(families: families)
                    }
                }
        }
    }
}

private struct TodoListContent: View {
    @Environment(AppModel.self) private var model
    let scope: ListScope

    @FetchRequest private var todos: FetchedResults<TodoItem>
    @State private var draft = ""
    @State private var editing: TodoItem?
    @State private var creating = false
    @State private var assigneeFilter: Member?
    @State private var showingDone = false
    @State private var completedCount = 0

    init(scope: ListScope) {
        self.scope = scope
        _todos = FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt)], predicate: scope.predicate)
    }

    private var members: [Member] {
        scope.family.map(model.repository.activeMembers(of:)) ?? []
    }

    var body: some View {
        let filtered = todos.filter { assigneeFilter == nil || $0.assignee == assigneeFilter }
        let open = filtered.filter { !$0.isDone }.sorted(by: Self.dueOrder)
        let done = filtered.filter(\.isDone).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }

        List {
            Section {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.tint)
                        .font(.title3)
                    TextField("New To-do", text: $draft)
                        .submitLabel(.done)
                        .onSubmit(addDraft)
                }
                if open.isEmpty {
                    Text("Nothing to do")
                        .foregroundStyle(.secondary)
                }
                ForEach(open) { todo in
                    row(todo)
                }
            }
            if !done.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showingDone) {
                        ForEach(done.prefix(30)) { todo in
                            row(todo)
                        }
                        Button("Delete Completed", role: .destructive) {
                            withAnimation {
                                done.forEach(model.repository.delete)
                                model.save()
                            }
                        }
                    } label: {
                        Text("Completed (\(done.count))")
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: completedCount)
        // Vor der eigenen Leiste angewandt, damit „Familie“ ganz rechts steht.
        .familyButton()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !members.isEmpty {
                    filterMenu
                }
                Button("New To-do", systemImage: "plus") { creating = true }
            }
        }
        .sheet(item: $editing) { todo in
            TodoEditorView(todo: todo, scope: scope)
        }
        .sheet(isPresented: $creating) {
            TodoEditorView(todo: nil, scope: scope, initialTitle: draft, initialAssignee: assigneeFilter)
        }
    }

    private func row(_ todo: TodoItem) -> some View {
        TodoRow(todo: todo) {
            withAnimation(.snappy) {
                if todo.isDone {
                    model.repository.reopen(todo)
                } else {
                    model.repository.complete(todo)
                    completedCount += 1
                }
                model.save()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = todo }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) {
                withAnimation {
                    model.repository.delete(todo)
                    model.save()
                }
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Assigned To", selection: $assigneeFilter) {
                Text("Everyone").tag(Member?.none)
                ForEach(members) { member in
                    Text(member.displayLabel).tag(Member?.some(member))
                }
            }
        } label: {
            Label("Filter", systemImage: assigneeFilter == nil
                  ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }

    private func addDraft() {
        let title = draft.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        withAnimation {
            model.repository.addTodo(title, assignee: assigneeFilter, to: scope,
                                     createdBy: creatorID)
            model.save()
        }
        draft = ""
    }

    private var creatorID: String? {
        model.me(in: scope.family)?.id?.uuidString ?? model.userID
    }

    /// Fällige zuerst, ohne Datum am Ende, sonst nach Anlage.
    static func dueOrder(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case let (l?, r?) where l != r: l < r
        case (.some, nil): true
        case (nil, .some): false
        default: (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
        }
    }
}

private struct TodoRow: View {
    @ObservedObject var todo: TodoItem
    let onToggle: () -> Void
    @Environment(\.today) private var today

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(todo.isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.isDone ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title ?? "")
                    .strikethrough(todo.isDone)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                if let due = todo.dueDate, !todo.isDone {
                    HStack(spacing: 4) {
                        Text(Self.dueText(due, today: today))
                        if todo.recurrenceRule != nil {
                            Image(systemName: "repeat")
                                .accessibilityLabel("Repeating")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Self.dueColor(due, today: today))
                }
            }
            Spacer(minLength: 4)
            if let assignee = todo.assignee {
                MemberAvatar(member: assignee, size: 26)
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func dueText(_ due: Date, today: Date) -> String {
        let calendar = Calendar.current
        switch calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: due)).day {
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Tomorrow")
        case -1: return String(localized: "Yesterday")
        default: return due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
    }

    static func dueColor(_ due: Date, today: Date) -> Color {
        let calendar = Calendar.current
        if due < calendar.startOfDay(for: today) { return .red }
        if calendar.isDate(due, inSameDayAs: today) { return .orange }
        return .secondary
    }
}

/// Todo anlegen oder bearbeiten.
struct TodoEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let todo: TodoItem?
    let scope: ListScope

    @State private var title: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var repeatChoice: TodoRepeat
    @State private var customInterval: Int
    @State private var customUnit: RecurrenceRule.Frequency
    @State private var assignee: Member?

    init(todo: TodoItem?, scope: ListScope, initialTitle: String = "", initialAssignee: Member? = nil) {
        self.todo = todo
        self.scope = scope
        _title = State(initialValue: todo?.title ?? initialTitle)
        _hasDueDate = State(initialValue: todo?.dueDate != nil)
        _dueDate = State(initialValue: todo?.dueDate ?? Calendar.current.startOfDay(for: .now))
        let parsed = TodoRepeat.parse(todo?.recurrenceRule)
        _repeatChoice = State(initialValue: parsed.choice)
        _customInterval = State(initialValue: parsed.interval)
        _customUnit = State(initialValue: parsed.unit)
        _assignee = State(initialValue: todo?.assignee ?? initialAssignee)
    }

    private var members: [Member] {
        scope.family.map(model.repository.activeMembers(of:)) ?? []
    }

    private var rule: String? {
        switch repeatChoice {
        case .never: nil
        case .preset(let rule), .imported(let rule): rule
        case .custom: RecurrenceRule(frequency: customUnit, interval: customInterval).rruleString
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, axis: .vertical)
                }
                Section {
                    Toggle("Due Date", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker("Date", selection: $dueDate, displayedComponents: .date)
                        if let todo {
                            AlertPicker(itemID: todo.id, isDayBased: true, defaultOffset: todo.defaultAlertOffset)
                        }
                        Picker("Repeat", selection: $repeatChoice) {
                            Text("Never").tag(TodoRepeat.never)
                            ForEach(TodoRepeat.presets, id: \.rule) { preset in
                                Text(preset.label).tag(TodoRepeat.preset(preset.rule))
                            }
                            if case .imported(let rule) = repeatChoice {
                                Text("Custom").tag(TodoRepeat.imported(rule))
                            }
                            Text("Custom…").tag(TodoRepeat.custom)
                        }
                        if repeatChoice == .custom {
                            Stepper(value: $customInterval, in: 1...99) {
                                Text(TodoRepeat.customDescription(interval: customInterval, unit: customUnit))
                            }
                            Picker("Unit", selection: $customUnit) {
                                Text("Days").tag(RecurrenceRule.Frequency.daily)
                                Text("Weeks").tag(RecurrenceRule.Frequency.weekly)
                                Text("Months").tag(RecurrenceRule.Frequency.monthly)
                                Text("Years").tag(RecurrenceRule.Frequency.yearly)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
                } footer: {
                    if hasDueDate && rule != nil {
                        Text("When you check it off, the to-do moves to the next date.")
                    }
                }
                if !members.isEmpty {
                    Section("Assigned To") {
                        Picker("Assigned To", selection: $assignee) {
                            Text("No one").tag(Member?.none)
                            ForEach(members) { member in
                                Text(member.displayLabel).tag(Member?.some(member))
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }
                if todo != nil {
                    Section {
                        Button("Delete To-do", systemImage: "trash", role: .destructive) {
                            if let todo { model.repository.delete(todo) }
                            model.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(todo == nil ? "New To-do" : "Edit To-do")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm, action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let due = hasDueDate ? dueDate : nil
        let rule = hasDueDate ? rule : nil
        if let todo {
            model.repository.update(todo, title: title, dueDate: due, assignee: assignee, recurrenceRule: rule)
        } else {
            model.repository.addTodo(title, dueDate: due, assignee: assignee, recurrenceRule: rule, to: scope,
                                     createdBy: model.me(in: scope.family)?.id?.uuidString ?? model.userID)
        }
        model.save()
        dismiss()
    }
}

/// Wiederholung eines Todos: feste Rhythmen, ein eigener Abstand („alle 3 Wochen“, Abstand und Einheit
/// stehen im Editor) oder eine Regel, die sich damit nicht abbilden lässt (bleibt unverändert erhalten).
enum TodoRepeat: Hashable {
    case never
    case preset(String)
    case custom
    case imported(String)

    static let presets: [(label: LocalizedStringKey, rule: String)] = [
        ("Every Day", "FREQ=DAILY"),
        ("Every Week", "FREQ=WEEKLY"),
        ("Every 2 Weeks", "FREQ=WEEKLY;INTERVAL=2"),
        ("Every Month", "FREQ=MONTHLY"),
        ("Every 2 Months", "FREQ=MONTHLY;INTERVAL=2"),
        ("Every 3 Months", "FREQ=MONTHLY;INTERVAL=3"),
        ("Every Year", "FREQ=YEARLY"),
    ]

    /// Auswahl für eine gespeicherte Regel, dazu Abstand und Einheit für „Eigene“ (sonst alle 3 Wochen).
    static func parse(_ string: String?) -> (choice: TodoRepeat, interval: Int, unit: RecurrenceRule.Frequency) {
        guard let string else { return (.never, 3, .weekly) }
        if presets.contains(where: { $0.rule == string }) { return (.preset(string), 3, .weekly) }
        if let rule = RecurrenceRule(rrule: string), rule.count == nil, rule.until == nil, rule.byDay.isEmpty,
           rule.byMonthDay.isEmpty, rule.byMonth.isEmpty, rule.otherParts.isEmpty {
            return (.custom, rule.interval, rule.frequency)
        }
        return (.imported(string), 3, .weekly)
    }

    static func customDescription(interval: Int, unit: RecurrenceRule.Frequency) -> String {
        switch unit {
        case .daily: String(localized: "Every \(interval) days")
        case .weekly: String(localized: "Every \(interval) weeks")
        case .monthly: String(localized: "Every \(interval) months")
        case .yearly: String(localized: "Every \(interval) years")
        }
    }
}
