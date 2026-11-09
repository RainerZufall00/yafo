import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var openedFile: OpenedFile?
    @State private var tab: AppTab = .calendar

    enum AppTab: Hashable {
        case calendar, shopping, todos, family
    }

    /// Eine .ics-Datei, mit der yafo geöffnet wurde (Teilen, Dateien-App, Mail).
    struct OpenedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    var body: some View {
        @Bindable var model = model
        TabView(selection: $tab) {
            Tab("Calendar", systemImage: "calendar", value: AppTab.calendar) {
                MonthView()
            }
            Tab("Shopping", systemImage: "cart", value: AppTab.shopping) {
                ShoppingView()
            }
            Tab("To-dos", systemImage: "checklist", value: AppTab.todos) {
                TodoView()
            }
            Tab("Family", systemImage: "person.3", value: AppTab.family) {
                FamilyView()
            }
            .badge(model.familiesNeedingProfile.count)
        }
        .onChange(of: scenePhase) { _, phase in
            // Abos beim Öffnen der App aktualisieren (ICS höchstens alle 15 Minuten).
            if phase == .active {
                model.processInbox()
                Task { await model.refreshSubscriptions() }
                Task { await model.autoBackupIfDue() }
            }
        }
        .onOpenURL { url in
            if url.isFileURL {
                openedFile = OpenedFile(url: url)
            } else if url.scheme == "yafo" {
                open(url)
            }
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

    /// Links aus den Widgets: `yafo://shopping?list=<key>` und `yafo://todos?list=<key>`.
    private func open(_ url: URL) {
        let list = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "list" }?.value
        switch url.host() {
        case "shopping": tab = .shopping
        case "todos": tab = .todos
        default: return
        }
        if let list, !list.isEmpty, list != "sample" { model.listScopeKey = list }
    }
}
