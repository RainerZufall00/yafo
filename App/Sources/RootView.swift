import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView {
            Tab("Calendar", systemImage: "calendar") {
                MonthView()
            }
            Tab("Shopping", systemImage: "cart") {
                ComingSoonView(title: "Shopping", systemImage: "cart")
            }
            Tab("To-dos", systemImage: "checklist") {
                ComingSoonView(title: "To-dos", systemImage: "checklist")
            }
            Tab("Family", systemImage: "person.3") {
                FamilyView()
            }
            .badge(model.familiesNeedingProfile.count)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

/// Platzhalter für Einkauf und Todos (Phase 3 der Roadmap).
struct ComingSoonView: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: systemImage,
                                   description: Text("Coming in a later version."))
                .navigationTitle(title)
        }
    }
}
