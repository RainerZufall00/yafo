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

extension ListScope {
    var title: String {
        family?.name ?? String(localized: "Just me")
    }

}
