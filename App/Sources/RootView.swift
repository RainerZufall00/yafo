import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var openedFile: OpenedFile?

    /// Eine .ics-Datei, mit der yafo geöffnet wurde (Teilen, Dateien-App, Mail).
    struct OpenedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

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
        .onChange(of: scenePhase) { _, phase in
            // Abos beim Öffnen der App aktualisieren (ICS höchstens alle 15 Minuten).
            if phase == .active {
                Task { await model.refreshSubscriptions() }
                Task { await model.autoBackupIfDue() }
            }
        }
        .onOpenURL { url in
            if url.isFileURL { openedFile = OpenedFile(url: url) }
        }
        .sheet(item: $openedFile) { file in
            ImportView(initialFile: file.url)
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
