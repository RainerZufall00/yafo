import CoreData
import SwiftUI
import YafoKit

/// Einkaufsliste als Kacheln mit Piktogrammen, nach Abteilungen in Laufreihenfolge.
/// Tippen hakt ab; abgehakte Artikel landen unter „Zuletzt gekauft“ und lassen sich dort
/// mit einem Tipp wieder auf die Liste setzen.
struct ShoppingView: View {
    @Environment(AppModel.self) private var model
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)])
    private var families: FetchedResults<Family>

    var body: some View {
        let scope = model.listScope(families: families)
        NavigationStack {
            ShoppingListContent(scope: scope)
                .id(scope)
                .safeAreaInset(edge: .top, spacing: 0) {
                    PersonalListBanner(families: families)
                }
                .navigationTitle("Shopping")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        ListScopeMenu(families: families)
                    }
                }
                .familyButton()
        }
    }
}

private struct ShoppingListContent: View {
    @Environment(AppModel.self) private var model
    let scope: ListScope

    @FetchRequest private var items: FetchedResults<ShoppingItem>
    @State private var draft = ""
    @State private var editing: ShoppingItem?
    @State private var confirmingClear = false
    @State private var checkedCount = 0
    @FocusState private var inputFocused: Bool

    init(scope: ListScope) {
        self.scope = scope
        _items = FetchRequest(sortDescriptors: [SortDescriptor(\.sortKey), SortDescriptor(\.createdAt)],
                              predicate: scope.predicate)
    }

    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 140), spacing: 10)]
    private let recentColumns = [GridItem(.adaptive(minimum: 72, maximum: 110), spacing: 8)]

    var body: some View {
        let open = items.filter { !$0.isChecked }
        let groups = ShoppingCategory.allCases.compactMap { category -> (ShoppingCategory, [ShoppingItem])? in
            let inAisle = open.filter { $0.category == category }
            return inAisle.isEmpty ? nil : (category, inAisle)
        }
        let recent = items.filter(\.isChecked)
            .sorted { ($0.checkedAt ?? .distantPast) > ($1.checkedAt ?? .distantPast) }
            .prefix(40)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
                    suggestions
                } else if open.isEmpty {
                    ContentUnavailableView("Nothing to buy", systemImage: "cart",
                                           description: Text("Add items above. Tap an item once it is in the cart."))
                }
                ForEach(groups, id: \.0) { category, inAisle in
                    VStack(alignment: .leading, spacing: 8) {
                        AisleHeader(category: category)
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(inAisle) { item in
                                ShoppingTile(emoji: item.emoji, icon: item.icon, name: item.name ?? "", quantity: item.quantity,
                                             color: category.color, isChecked: false)
                                    .itemGestures(hint: "Marks the item as bought") {
                                        withAnimation(.snappy) {
                                            model.repository.setChecked(item, true)
                                            model.save()
                                        }
                                        checkedCount += 1
                                    } onDetails: {
                                        editing = item
                                    }
                            }
                        }
                    }
                }
                // Eigener Kasten mit kleineren, grauen Kacheln, damit „Zuletzt gekauft“ nicht wie
                // eine weitere Abteilung aussieht.
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Label("Recently Bought", systemImage: "clock.arrow.circlepath")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                            Button("Clear") { confirmingClear = true }
                                .font(.subheadline)
                        }
                        Text("Tap an item to put it back on the list.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: recentColumns, spacing: 8) {
                            ForEach(recent) { item in
                                ShoppingTile(emoji: item.emoji, icon: item.icon, name: item.name ?? "", quantity: nil,
                                             color: item.category.color, isChecked: true, isCompact: true)
                                    .itemGestures(hint: "Puts the item back on the list") {
                                        withAnimation(.snappy) {
                                            model.repository.setChecked(item, false)
                                            model.save()
                                        }
                                    } onDetails: {
                                        editing = item
                                    }
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { inputField }
        .sensoryFeedback(.success, trigger: checkedCount)
        .sensoryFeedback(.impact(weight: .medium), trigger: editing) { _, new in new != nil }
        .sheet(item: $editing) { item in
            ShoppingItemSheet(item: item)
        }
        .confirmationDialog("Clear recently bought items?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                withAnimation {
                    model.repository.clearRecentlyBought(in: scope)
                    model.save()
                }
            }
        } message: {
            Text("Suggestions while typing will no longer include them.")
        }
    }

    private var inputField: some View {
        HStack {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.tint)
                .font(.title3)
            TextField("What do you need?", text: $draft)
                .focused($inputFocused)
                .submitLabel(.done)
                .onSubmit { add(draft) }
            if !draft.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { draft = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// Kacheln für das Getippte und passende Vorschläge aus „Zuletzt gekauft“ und dem Katalog.
    private var suggestions: some View {
        let typed = draft.trimmingCharacters(in: .whitespaces)
        let completions = model.repository.shoppingCompletions(for: typed, in: scope)
        let names = completions.contains { $0.compare(typed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            ? completions : [typed] + completions
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(names, id: \.self) { name in
                let category = ShoppingCatalog.category(for: name)
                Button {
                    add(name)
                } label: {
                    ShoppingTile(emoji: ShoppingCatalog.emoji(for: name), icon: ShoppingCatalog.icon(for: name),
                                 name: name, quantity: nil,
                                 color: category.color, isChecked: false, isSuggestion: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Add \(name)"))
            }
        }
    }

    private func add(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        withAnimation(.snappy) {
            model.repository.addShoppingItem(name, to: scope)
            model.save()
        }
        draft = ""
        inputFocused = true
    }
}

private struct AisleHeader: View {
    let category: ShoppingCategory

    var body: some View {
        HStack(spacing: 6) {
            ItemIcon(icon: category.icon, emoji: category.emoji)
                .frame(width: 18, height: 18)
                .foregroundStyle(category.color)
            Text(category.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Kachel mit großem Piktogramm, Name und Menge. Offen: kräftige Farbe der Abteilung,
/// abgehakt: grau (mit `isCompact` kleiner), Vorschlag: getönt mit Rahmen.
struct ShoppingTile: View {
    @Environment(\.colorScheme) private var colorScheme
    let emoji: String
    let icon: String
    let name: String
    let quantity: String?
    let color: Color
    let isChecked: Bool
    var isSuggestion = false
    var isCompact = false

    var body: some View {
        VStack(spacing: 3) {
            ItemIcon(icon: icon, emoji: emoji)
                .frame(width: isCompact ? 28 : 40, height: isCompact ? 28 : 40)
                .foregroundStyle(iconColor)
                .opacity(isChecked ? 0.6 : 1)
            Text(name)
                .font(isCompact ? .caption.weight(.medium) : .footnote.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
            if let quantity, !quantity.isEmpty {
                Text(quantity)
                    .font(.caption2.weight(.medium))
                    .opacity(0.85)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, isCompact ? 6 : 8)
        .frame(maxWidth: .infinity, minHeight: isCompact ? 70 : 96)
        .foregroundStyle(foreground)
        .background(RoundedRectangle(cornerRadius: 14).fill(background))
        .overlay {
            if isSuggestion {
                RoundedRectangle(cornerRadius: 14).strokeBorder(color.opacity(0.6), lineWidth: 1.5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var iconColor: Color {
        if isChecked { return .secondary }
        return isSuggestion ? color : .white
    }

    private var foreground: Color {
        if isChecked { return .secondary }
        return isSuggestion ? .primary : .white
    }

    private var background: Color {
        // Hebt sich vom grauen Kasten „Zuletzt gekauft“ ab (hell: weiß, dunkel: etwas heller).
        if isChecked { return Color(.tertiarySystemBackground) }
        if isSuggestion { return color.opacity(colorScheme == .dark ? 0.25 : 0.14) }
        return color
    }
}

extension ShoppingCategory {
    var title: String {
        switch self {
        case .produce: String(localized: "Fruit & Vegetables")
        case .bakery: String(localized: "Bread & Bakery")
        case .meat: String(localized: "Meat & Fish")
        case .dairy: String(localized: "Dairy & Eggs")
        case .pantry: String(localized: "Pantry")
        case .breakfast: String(localized: "Breakfast & Coffee")
        case .snacks: String(localized: "Sweets & Snacks")
        case .drinks: String(localized: "Drinks")
        case .frozen: String(localized: "Frozen")
        case .household: String(localized: "Household")
        case .hygiene: String(localized: "Personal Care")
        case .baby: String(localized: "Baby")
        case .pets: String(localized: "Pets")
        case .other: String(localized: "Other")
        }
    }

    /// Kräftige Kachelfarben; weiße Schrift bleibt überall lesbar.
    var color: Color { Color(hex: colorHex) }
}
