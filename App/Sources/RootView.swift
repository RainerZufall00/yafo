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
                ShoppingView()
            }
            Tab("To-dos", systemImage: "checklist") {
                TodoView()
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
