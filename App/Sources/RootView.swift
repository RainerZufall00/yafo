import CoreData
import SwiftUI
import YafoKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var openedFile: OpenedFile?
    /// Familie, für die gerade das eigene Profil angelegt wird (nach dem Annehmen einer Einladung).
    @State private var joining: Family?
    /// Schon einmal angebotene Familien; nach „Später“ erst beim nächsten Start wieder.
    @State private var offeredJoins: Set<NSManagedObjectID> = []
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
        .onAppear {
            leaveFamilyTabIfSwiping()
            offerJoin()
        }
        .onChange(of: interfaceStyle) { leaveFamilyTabIfSwiping() }
        .onChange(of: model.selectedTab) { leaveFamilyTabIfSwiping() }
        .onChange(of: model.familiesNeedingProfile) { offerJoin() }
        .sheet(item: $joining) { family in
            JoinFamilyView(family: family)
        }
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

    /// Im Wisch-Modus gibt es keine Familie-Seite; ein gemerkter Familie-Tab zeigt dann den Kalender.
    private func leaveFamilyTabIfSwiping() {
        if interfaceStyle == .swipe, model.selectedTab == .family { model.selectedTab = .calendar }
    }

    /// Nach dem Beitritt gleich nach dem eigenen Profil fragen; ohne Profil taucht man in der
    /// Familie nicht auf und kann nicht als Teilnehmer gewählt werden.
    private func offerJoin() {
        guard joining == nil, openedFile == nil,
              let family = model.familiesNeedingProfile.first(where: { !offeredJoins.contains($0.objectID) })
        else { return }
        offeredJoins.insert(family.objectID)
        joining = family
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

    /// Modern: Kalender, links die Todos, rechts der Einkauf, per Wischen erreichbar. „Familie“ ist
    /// keine Seite, sondern ein Knopf oben rechts auf jeder Seite (`familyButton()`).
    private var swipePages: some View {
        @Bindable var model = model
        return GeometryReader { proxy in
            // Abstand über dem Home-Indikator; die Seiten selbst reichen bis an den Rand.
            let bottomInset = proxy.safeAreaInsets.bottom
            TabView(selection: $model.selectedTab) {
                TodoView()
                    .safeAreaPadding(.bottom, PageSwitcher.height)
                    .tag(AppTab.todos)
                // Der Kalender blättert seitenweise und endet daher über der Seitenanzeige,
                // sonst schaut die nächste Woche bzw. der nächste Monat darunter hervor.
                MonthView()
                    .padding(.bottom, PageSwitcher.height + bottomInset)
                    .tag(AppTab.calendar)
                ShoppingView()
                    .safeAreaPadding(.bottom, PageSwitcher.height)
                    .tag(AppTab.shopping)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Seiten bis an Statusleiste und Home-Indikator, sonst bleibt oben und unten ein Streifen
            // in Hintergrundfarbe stehen. Die Seitenanzeige schwebt darüber; die Listen halten mit
            // `safeAreaPadding` Abstand, damit ihr Inhalt nicht dahinter verschwindet.
            .ignoresSafeArea(edges: .vertical)
            .overlay(alignment: .bottom) {
                PageSwitcher(tab: $model.selectedTab)
            }
        }
    }
}
