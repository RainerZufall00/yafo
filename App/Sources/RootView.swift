import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var openedFile: OpenedFile?
    @AppStorage(InterfaceStyle.storageKey) private var interfaceStyle = InterfaceStyle.tabs

    /// Eine .ics-Datei, mit der yafo geöffnet wurde (Teilen, Dateien-App, Mail).
    struct OpenedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    var body: some View {
        Group {
            switch interfaceStyle {
            case .tabs: tabs
            case .swipe: swipePages
            }
        }
        .onAppear { leaveFamilyTabIfSwiping() }
        .onChange(of: interfaceStyle) { leaveFamilyTabIfSwiping() }
        .onChange(of: model.selectedTab) { leaveFamilyTabIfSwiping() }
        .onChange(of: scenePhase) { _, phase in
            // Abos beim Öffnen der App aktualisieren (ICS höchstens alle 15 Minuten).
            if phase == .background { model.didEnterBackground() }
            if phase == .active {
                model.didBecomeActive()
                model.processInbox()
                Task { await model.refreshSubscriptions() }
                Task { await model.autoBackupIfDue() }
            }
        }
        .onOpenURL { url in
            if url.isFileURL { openedFile = OpenedFile(url: url) } else { model.open(url) }
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

    /// „Familie“ ist im Wisch-Modus keine Seite, sondern ein Blatt am Kalender.
    private func leaveFamilyTabIfSwiping() {
        if interfaceStyle == .swipe, model.selectedTab == .family { model.selectedTab = .calendar }
    }

    /// Klassisch: Tab-Leiste unten.
    private var tabs: some View {
        @Bindable var model = model
        return TabView(selection: $model.selectedTab) {
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
    }

    /// Modern: Kalender in der Mitte, Todos links, Einkauf rechts, per Wischen erreichbar.
    private var swipePages: some View {
        @Bindable var model = model
        return TabView(selection: $model.selectedTab) {
            TodoView()
                .tag(AppTab.todos)
            MonthView()
                .tag(AppTab.calendar)
            ShoppingView()
                .tag(AppTab.shopping)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PageSwitcher(tab: $model.selectedTab)
        }
    }
}
