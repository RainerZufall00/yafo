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
                        Text(Self.dueText(due))
                        if todo.recurrenceRule != nil {
                            Image(systemName: "repeat")
                                .accessibilityLabel("Repeating")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Self.dueColor(due))
                }
            }
            Spacer(minLength: 4)
            if let assignee = todo.assignee {
                MemberAvatar(member: assignee, size: 26)
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func dueText(_ due: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(due) { return String(localized: "Today") }
        if calendar.isDateInTomorrow(due) { return String(localized: "Tomorrow") }
        if calendar.isDateInYesterday(due) { return String(localized: "Yesterday") }
        return due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func dueColor(_ due: Date) -> Color {
        let today = Calendar.current.startOfDay(for: .now)
        if due < today { return .red }
        if Calendar.current.isDateInToday(due) { return .orange }
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
    @State private var rule: String?
    @State private var assignee: Member?

    init(todo: TodoItem?, scope: ListScope, initialTitle: String = "", initialAssignee: Member? = nil) {
        self.todo = todo
        self.scope = scope
        _title = State(initialValue: todo?.title ?? initialTitle)
        _hasDueDate = State(initialValue: todo?.dueDate != nil)
        _dueDate = State(initialValue: todo?.dueDate ?? Calendar.current.startOfDay(for: .now))
        _rule = State(initialValue: todo?.recurrenceRule)
        _assignee = State(initialValue: todo?.assignee ?? initialAssignee)
    }

    private var members: [Member] {
        scope.family.map(model.repository.activeMembers(of:)) ?? []
    }

    private static let rules: [(LocalizedStringKey, String)] = [
        ("Every Day", "FREQ=DAILY"),
        ("Every Week", "FREQ=WEEKLY"),
        ("Every 2 Weeks", "FREQ=WEEKLY;INTERVAL=2"),
        ("Every Month", "FREQ=MONTHLY"),
        ("Every Year", "FREQ=YEARLY"),
    ]

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
                        Picker("Repeat", selection: $rule) {
                            Text("Never").tag(String?.none)
                            ForEach(Self.rules, id: \.1) { label, value in
                                Text(label).tag(String?.some(value))
                            }
                            if let rule, !Self.rules.contains(where: { $0.1 == rule }) {
                                Text("Custom").tag(String?.some(rule))
                            }
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
