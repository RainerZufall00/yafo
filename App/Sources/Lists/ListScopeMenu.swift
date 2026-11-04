import CoreData
import SwiftUI
import YafoKit

/// Umschalter oben in Einkauf und Todos: Familien und „Nur ich“.
struct ListScopeMenu: View {
    @Environment(AppModel.self) private var model
    let families: FetchedResults<Family>

    var body: some View {
        let scope = model.listScope(families: families)
        Menu {
            Picker("List", selection: Binding(
                get: { scope.family?.id?.uuidString ?? "personal" },
                set: { model.listScopeKey = $0 }
            )) {
                ForEach(families) { family in
                    Label(family.name ?? "", systemImage: "person.3").tag(family.id?.uuidString ?? "")
                }
                Label("Just me", systemImage: "person").tag("personal")
            }
        } label: {
            HStack(spacing: 4) {
                if scope.family == nil {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                }
                Text(scope.title)
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(.primary)
        }
        .accessibilityLabel(Text("List: \(scope.title)"))
    }
}

/// Hinweis über Einkauf und Todos, solange „Nur ich“ gewählt ist: Die Familie sieht diese
/// Liste nicht. Ein Tipp wechselt zur ersten Familie. Ohne Familie gibt es nichts zu verwechseln.
struct PersonalListBanner: View {
    @Environment(AppModel.self) private var model
    let families: FetchedResults<Family>

    var body: some View {
        if model.listScope(families: families).family == nil, let family = families.first {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Only visible to you")
                        .font(.subheadline.weight(.semibold))
                    Text("Your family won't see anything you add here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    withAnimation(.snappy) { model.listScopeKey = family.id?.uuidString ?? "" }
                } label: {
                    Text("Switch to \(family.name ?? "")")
                        .lineLimit(1)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.14))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.orange.opacity(0.35)).frame(height: 0.5)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

extension ListScope {
    var title: String {
        family?.name ?? String(localized: "Just me")
    }

}
