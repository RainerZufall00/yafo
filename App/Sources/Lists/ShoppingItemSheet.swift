import CoreData
import SwiftUI
import YafoKit

/// Detailblatt nach langem Drücken auf einen Artikel: Menge und Details als freier Text oder
/// per Schnellauswahl (Mengen plus Typen aus dem Katalog, z. B. AA/AAA bei Batterien),
/// dazu Abteilung, Umbenennen und Löschen. Änderungen gelten sofort.
struct ShoppingItemSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var item: ShoppingItem

    @State private var details: String
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingDelete = false

    init(item: ShoppingItem) {
        self.item = item
        _details = State(initialValue: item.quantity ?? "")
    }

    var body: some View {
        let name = item.name ?? ""
        let category = item.category
        let tokens = ShoppingDetails.amounts + ShoppingDetails.variants(for: name)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }

                TextField("Quantity or details, e.g. 500 g", text: $details)
                    .submitLabel(.done)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Details for \(name)")
                        .font(.headline)
                    FlowLayout(spacing: 8) {
                        ForEach(tokens, id: \.self) { token in
                            let isOn = ShoppingDetails.contains(token, in: details)
                            Button {
                                withAnimation(.snappy(duration: 0.2)) {
                                    details = ShoppingDetails.toggle(token, in: details)
                                }
                            } label: {
                                Text(token)
                                    .font(.body.weight(isOn ? .semibold : .regular))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .frame(minWidth: 40)
                                    .foregroundStyle(isOn ? Color.white : Color.primary)
                                    .background(RoundedRectangle(cornerRadius: 10)
                                        .fill(isOn ? category.color : Color(.secondarySystemBackground)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                }

                FlowLayout(spacing: 8) {
                    Menu {
                        Picker("Aisle", selection: Binding(
                            get: { item.categoryRaw.flatMap(ShoppingCategory.init(rawValue:)) },
                            set: { model.repository.setCategory($0, of: item); model.save() }
                        )) {
                            let automatic = ShoppingCatalog.category(for: name)
                            Text("Automatic (\(automatic.title))").tag(ShoppingCategory?.none)
                            ForEach(ShoppingCategory.allCases, id: \.self) { category in
                                Text(category.title).tag(ShoppingCategory?.some(category))
                            }
                        }
                    } label: {
                        actionLabel(category.title, systemImage: "square.grid.2x2")
                    }
                    Button {
                        newName = name
                        renaming = true
                    } label: {
                        actionLabel(String(localized: "Rename"), systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        actionLabel(String(localized: "Delete"), systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: details) {
            let trimmed = details.trimmingCharacters(in: .whitespaces)
            item.quantity = trimmed.isEmpty ? nil : trimmed
        }
        .onDisappear { model.save() }
        .alert("Rename", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                item.name = trimmed
                model.save()
            }
        }
        .confirmationDialog("Delete \(name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                dismiss()
                withAnimation {
                    model.repository.delete(item)
                    model.save()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.body.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

extension View {
    /// Tippen für die Hauptaktion (abhaken), langes Drücken öffnet die Details.
    /// Für VoiceOver beides als Aktionen.
    func itemGestures(hint: LocalizedStringKey, onTap: @escaping () -> Void,
                      onDetails: @escaping () -> Void) -> some View {
        contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 0.35, perform: onDetails)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(hint)
            .accessibilityAction(.default, onTap)
            .accessibilityAction(named: "Details", onDetails)
    }
}

/// Bricht Kinder wie Text in Zeilen um (Chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (subview, point) in zip(subviews, result.points) {
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (points, CGSize(width: maxX, height: y + rowHeight))
    }
}
