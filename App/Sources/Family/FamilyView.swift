import CoreData
import SwiftUI
import YafoKit

/// Familien verwalten: Mitglieder einladen, Kinderprofile anlegen, geteilte Kalender, Farben.
/// Ohne Familie läuft die App mit eigenem Kalender und privaten Listen.
struct FamilyView: View {
    private enum Prompt: Identifiable {
        case child(Family)
        case calendar(Family)

        var id: String {
            switch self {
            case .child(let family): "child-\(family.objectID)"
            case .calendar(let family): "calendar-\(family.objectID)"
            }
        }
    }

    @Environment(AppModel.self) private var model

    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)])
    private var families: FetchedResults<Family>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt)],
                  predicate: NSPredicate(format: "family == nil"))
    private var personalCalendars: FetchedResults<EventCalendar>

    @AppStorage(LaunchTab.key) private var launchTab = LaunchTab.last.rawValue
    @State private var creatingFamily = false
    @State private var joiningByCode = false
    @State private var importing = false
    @State private var importingBirthdays = false
    @State private var exporting = false
    @State private var restoring = false
    @State private var joining: Family?
    @State private var prompt: Prompt?
    @State private var promptText = ""
    @AppStorage(InterfaceStyle.storageKey) private var interfaceStyle = InterfaceStyle.tabs
    /// Gesetzt, wenn die Ansicht als Blatt offen ist (Knopf oben rechts): zeigt „Fertig“.
    var onDone: (() -> Void)?

    var body: some View {
        NavigationStack {
            List {
                if !model.familiesNeedingProfile.isEmpty {
                    Section {
                        ForEach(model.familiesNeedingProfile) { family in
                            Button {
                                joining = family
                            } label: {
                                Label("Set up your profile in \(family.name ?? "")", systemImage: "person.crop.circle.badge.plus")
                            }
                        }
                    }
                }

                Section("Just me") {
                    ForEach(personalCalendars) { calendar in
                        CalendarRow(calendar: calendar)
                    }
                }

                ForEach(families) { family in
                    FamilySection(family: family,
                                  addChild: { ask(.child(family)) },
                                  addCalendar: { ask(.calendar(family)) })
                }

                Section {
                    Picker("On Launch", systemImage: "app.badge", selection: $launchTab) {
                        ForEach(LaunchTab.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                } footer: {
                    Text("Tapping the widget always opens the calendar.")
                }

                Section {
                    NavigationLink {
                        ExternalCalendarsView()
                    } label: {
                        Label("Device Calendars", systemImage: "iphone")
                    }
                    Button("Import Events", systemImage: "square.and.arrow.down") { importing = true }
                    Button("Import Birthdays", systemImage: "birthday.cake") { importingBirthdays = true }
                } footer: {
                    Text("Show work or Google calendars in gray, or copy events into yafo once.")
                }

                Section {
                    Button("Export & Backup", systemImage: "square.and.arrow.up") { exporting = true }
                    Button("Restore from Backup…", systemImage: "arrow.counterclockwise") { restoring = true }
                } footer: {
                    Text("Calendars and lists as files, a copy in a device calendar, and the weekly backup. Restoring adds what is missing and keeps what is there.")
                }

                Section {
                    Picker("Navigation", selection: $interfaceStyle) {
                        ForEach(InterfaceStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                } footer: {
                    Text("Swipe: months scroll up and down like in Apple's Calendar, swipe right for to-dos and left for the shopping list. Only on this device.")
                }

                Section {
                    NavigationLink {
                        DangerZoneView()
                    } label: {
                        Label("Leave or Delete", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Leave a family, delete one you own, or delete all your data.")
                }

                if families.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No family yet", systemImage: "person.3")
                        } description: {
                            Text("Create a family to share calendars and lists, or join one with an invitation link or QR code. Until then yafo works with your own calendar.")
                        } actions: {
                            Button("Create Family") { creatingFamily = true }
                                .buttonStyle(.borderedProminent)
                            Button("Join with QR Code") { joiningByCode = true }
                                .disabled(!model.sharing.isAvailable)
                        }
                    }
                }
            }
            .navigationTitle("Family")
            .toolbar {
                if let onDone {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", role: .confirm, action: onDone)
                    }
                }
                // Als Blatt steht rechts „Fertig“, dann wandert „+“ nach links.
                ToolbarItem(placement: onDone == nil ? .topBarTrailing : .topBarLeading) {
                    Menu("Add Family", systemImage: "plus") {
                        Button("Create Family", systemImage: "person.3") { creatingFamily = true }
                        Button("Join with QR Code", systemImage: "qrcode.viewfinder") { joiningByCode = true }
                            .disabled(!model.sharing.isAvailable)
                    }
                }
            }
            .sheet(isPresented: $creatingFamily) {
                CreateFamilyView()
            }
            .sheet(isPresented: $joiningByCode) {
                JoinCodeView()
            }
            .sheet(item: $joining) { family in
                JoinFamilyView(family: family)
            }
            .sheet(isPresented: $importing) {
                ImportView()
            }
            .sheet(isPresented: $importingBirthdays) {
                BirthdayImportView()
            }
            .sheet(isPresented: $exporting) {
                ExportView()
            }
            .backupRestore(isPresented: $restoring)
            .alert(promptTitle, isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })) {
                TextField("Name", text: $promptText)
                Button("Add") { submitPrompt() }
                    .disabled(promptText.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var promptTitle: LocalizedStringKey {
        switch prompt {
        case .child: "Add Child Profile"
        case .calendar: "Add Shared Calendar"
        case nil: ""
        }
    }

    private func ask(_ newPrompt: Prompt) {
        promptText = ""
        prompt = newPrompt
    }

    private func submitPrompt() {
        let name = promptText.trimmingCharacters(in: .whitespaces)
        switch prompt {
        case .child(let family): model.repository.addChildProfile(name: name, to: family)
        case .calendar(let family): model.repository.addSharedCalendar(name: name, to: family)
        case nil: break
        }
        model.save()
        prompt = nil
    }
}

private struct FamilySection: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var family: Family
    let addChild: () -> Void
    let addCalendar: () -> Void

    @State private var inviting = false
    @State private var showingCode = false

    private var isOwner: Bool { model.isOwner(of: family) }

    var body: some View {
        Section {
            ForEach(model.repository.activeMembers(of: family)) { member in
                HStack {
                    MemberAvatar(member: member, size: 30)
                    VStack(alignment: .leading) {
                        Text(member.displayLabel)
                        if member == model.me(in: family) {
                            Text("You").font(.caption).foregroundStyle(.secondary)
                        } else if member.kind == .child {
                            Text(member.hasAccount ? "Child with Apple Account" : "Child profile")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            ForEach((family.calendars ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }) { calendar in
                CalendarRow(calendar: calendar)
            }
            Button("Add Child Profile", systemImage: "figure.child", action: addChild)
            Button("Add Shared Calendar", systemImage: "calendar.badge.plus", action: addCalendar)
            if isOwner {
                Button("Invite Members", systemImage: "person.badge.plus") {
                    Task { await invite() }
                }
                .disabled(!model.sharing.isAvailable || inviting)
                Button("Invite with QR Code", systemImage: "qrcode") { showingCode = true }
                    .disabled(!model.sharing.isAvailable)
                    .sheet(isPresented: $showingCode) {
                        InviteCodeView(family: family)
                    }
            }
        } header: {
            HStack {
                Text(family.name ?? "")
                Spacer()
                Text(isOwner ? "Owner" : "Member")
            }
        } footer: {
            if isOwner && !model.sharing.isAvailable {
                Text("Sign in to iCloud to invite family members.")
            }
        }
    }

    private func invite() async {
        inviting = true
        defer { inviting = false }
        do {
            let share = try await model.sharing.share(for: family)
            if let container = model.sharing.ckContainer {
                CloudSharingPresenter.present(share: share, container: container, title: family.name ?? "yafo")
            }
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

/// Kalender mit eigener Farbe (nur für einen selbst) und Sichtbarkeit.
private struct CalendarRow: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var calendar: EventCalendar
    @FetchRequest(sortDescriptors: []) private var appearances: FetchedResults<CalendarAppearance>

    var body: some View {
        let _ = appearances.count // neu zeichnen, wenn sich Farbe oder Sichtbarkeit ändert
        NavigationLink {
            CalendarSettingsView(calendar: calendar)
        } label: {
            HStack {
                Image(systemName: "circle.fill")
                    .foregroundStyle(Color(hex: model.repository.color(of: calendar)))
                Text(calendar.displayName)
                Spacer()
                if let region = model.repository.holidayRegion(of: calendar) {
                    Text(region.shortName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(hex: CalendarColors.publicHoliday))
                }
            }
        }
    }
}
