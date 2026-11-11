import CoreData
import SwiftUI
import YafoKit

/// Erster Start: Begrüßung, Bedienung wählen, dann Familie anlegen (und per QR-Code einladen),
/// einer Familie beitreten oder allein loslegen. Läuft als Vollbild über `RootView`.
struct OnboardingView: View {
    /// Schlüssel in den UserDefaults: Onboarding abgeschlossen oder übersprungen.
    static let doneKey = "onboardingDone"

    private enum Step: Hashable {
        case style, family, create, invite(Family), join
    }

    @Environment(AppModel.self) private var model
    let onFinished: () -> Void

    @State private var path: [Step] = []

    var body: some View {
        NavigationStack(path: $path) {
            WelcomePage { path.append(.style) }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .style:
                        StylePage { path.append(.family) }
                    case .family:
                        FamilyPage(create: { path.append(.create) },
                                   join: { path.append(.join) },
                                   finish: onFinished)
                    case .create:
                        CreatePage { family in
                            // Kein Zurück zum Formular, die Familie gibt es jetzt.
                            path = [.style, .family, .invite(family)]
                        }
                    case .invite(let family):
                        InvitePage(family: family, finish: onFinished)
                    case .join:
                        OnboardingPage(systemImage: "qrcode.viewfinder", title: "Join a Family",
                                       subtitle: "Ask someone in the family to open Family › Invite with QR Code, then scan it.") {
                            JoinCodeContent(onFinished: onFinished)
                        }
                    }
                }
        }
    }
}

// MARK: - Gerüst

/// Gemeinsamer Aufbau der Seiten: Symbol, Titel, Untertitel, Inhalt und unten die Hauptaktion.
private struct OnboardingPage<Content: View, Actions: View>: View {
    var systemImage: String?
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 46, weight: .semibold))
                            .foregroundStyle(.tint)
                            .padding(.bottom, 4)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    if let subtitle {
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                content
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) { actions }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .frame(maxWidth: 520)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension OnboardingPage where Actions == EmptyView {
    init(systemImage: String? = nil, title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil,
         @ViewBuilder content: () -> Content) {
        self.init(systemImage: systemImage, title: title, subtitle: subtitle, content: content) { EmptyView() }
    }
}

/// Große Hauptaktion am unteren Rand.
private struct PrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }
}

// MARK: - Seiten

private struct WelcomePage: View {
    let next: () -> Void

    var body: some View {
        OnboardingPage(title: "Welcome to yafo", subtitle: "The organizer for your whole family.") {
            VStack(alignment: .leading, spacing: 22) {
                feature("calendar", .blue, "Shared Calendars",
                        "Everyone sees who has to be where, with a color for each calendar.")
                feature("cart.fill", .green, "Shopping List",
                        "Sorted by aisle, so nobody walks through the store twice.")
                feature("checklist", .orange, "To-dos",
                        "With due dates, and with a name on them.")
                feature("lock.icloud.fill", .indigo, "Your iCloud, No Account",
                        "Everything stays in your family's iCloud. There is no yafo server.")
            }
            .padding(.top, 8)
        } actions: {
            PrimaryButton(title: "Get Started", action: next)
        }
    }

    private func feature(_ systemImage: String, _ color: Color, _ title: LocalizedStringKey,
                         _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Bedienung wählen: zwei Karten mit einer kleinen Skizze der App.
private struct StylePage: View {
    @AppStorage(InterfaceStyle.storageKey) private var interfaceStyle = InterfaceStyle.tabs
    let next: () -> Void

    var body: some View {
        OnboardingPage(title: "Pick Your Style", subtitle: "How do you want to move around in yafo?") {
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    card(.tabs, text: "A tab bar at the bottom. Months flip sideways.")
                    card(.swipe, text: "No tab bar. Swipe sideways for to-dos and shopping, months scroll up and down.")
                }
                Text("You can change this at any time under Family.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } actions: {
            PrimaryButton(title: "Continue", action: next)
        }
    }

    private func card(_ style: InterfaceStyle, text: LocalizedStringKey) -> some View {
        let isSelected = interfaceStyle == style
        return Button {
            withAnimation(.snappy) { interfaceStyle = style }
        } label: {
            VStack(spacing: 12) {
                StyleSketch(style: style)
                    .frame(height: 170)
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    Text(style.title).font(.headline)
                }
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                                  lineWidth: isSelected ? 2.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Skizze eines iPhones in der jeweiligen Bedienung: Monatsraster, darunter Tab-Leiste oder
/// Seitenanzeige; beim Wischen schauen links und rechts die Nachbarseiten hervor.
private struct StyleSketch: View {
    let style: InterfaceStyle

    var body: some View {
        HStack(spacing: 5) {
            if style == .swipe { neighbor("checklist") }
            phone
            if style == .swipe { neighbor("cart") }
        }
        .accessibilityHidden(true)
    }

    private var phone: some View {
        VStack(spacing: 6) {
            Capsule().fill(.tertiary).frame(width: 34, height: 5)
                .frame(maxWidth: .infinity, alignment: .leading)
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                ForEach(0..<5, id: \.self) { row in
                    GridRow {
                        ForEach(0..<5, id: \.self) { column in
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(row == 2 && column == 1 ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        }
                    }
                }
            }
            switch style {
            case .tabs:
                HStack(spacing: 0) {
                    ForEach(["calendar", "cart", "checklist", "person.3"], id: \.self) { name in
                        Image(systemName: name)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(name == "calendar" ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 16)
            case .swipe:
                HStack(spacing: 3) {
                    Circle().fill(.tertiary).frame(width: 5, height: 5)
                    Capsule().fill(.tint).frame(width: 16, height: 5)
                    Circle().fill(.tertiary).frame(width: 5, height: 5)
                }
                .frame(height: 16)
            }
        }
        .padding(8)
        .frame(width: 92)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.tertiary, lineWidth: 1.5)
        }
    }

    /// Angeschnittene Nachbarseite im Wisch-Modus.
    private func neighbor(_ systemImage: String) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.quaternary)
            .frame(width: 16)
            .padding(.vertical, 14)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
    }
}

/// Familie: anlegen, beitreten oder allein loslegen. Ist schon eine Familie da (Einladungslink
/// vor dem ersten Start angenommen, zweites Gerät), geht es damit weiter.
private struct FamilyPage: View {
    @Environment(AppModel.self) private var model
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)])
    private var families: FetchedResults<Family>
    let create: () -> Void
    let join: () -> Void
    let finish: () -> Void

    @State private var profileFamily: Family?
    @State private var restoring = false

    var body: some View {
        Group {
            if let invited = model.familiesNeedingProfile.first {
                OnboardingPage(systemImage: "party.popper.fill", title: "You're Invited",
                               subtitle: "You have joined \(invited.name ?? ""). Set up your profile so the others can add you to events.") {
                    EmptyView()
                } actions: {
                    PrimaryButton(title: "Set Up Profile") { profileFamily = invited }
                    Button("Later", action: finish)
                }
            } else if let family = families.first {
                OnboardingPage(systemImage: "checkmark.circle.fill", title: "You're All Set",
                               subtitle: "You are part of \(family.name ?? "").") {
                    EmptyView()
                } actions: {
                    PrimaryButton(title: "Open yafo", action: finish)
                }
            } else {
                choice
            }
        }
        .sheet(item: $profileFamily, onDismiss: finish) { family in
            JoinFamilyView(family: family)
        }
        // Mit Familie im Backup zeigt die Seite danach „You're All Set“, sonst geht es direkt los.
        .backupRestore(isPresented: $restoring) { _ in
            if families.isEmpty { finish() }
        }
    }

    private var choice: some View {
        OnboardingPage(systemImage: "person.3.fill", title: "Your Family",
                       subtitle: "Share calendars and lists with the people you live with.") {
            VStack(spacing: 12) {
                option("plus.circle.fill", "Create a Family",
                       "Start one and invite the others with a QR code.", action: create)
                option("qrcode.viewfinder", "Join a Family",
                       "Scan the QR code of someone who is already in.", action: join)
                    .disabled(!model.sharing.isAvailable)
                option("arrow.counterclockwise.circle.fill", "Restore a Backup",
                       "Bring back calendars and lists from a yafo backup file.") { restoring = true }
                if !model.sharing.isAvailable {
                    Label("Sign in to iCloud in Settings to share with your family.", systemImage: "icloud.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        } actions: {
            Button("Not Now, Just Me", action: finish)
                .padding(.bottom, 4)
        }
    }

    private func option(_ systemImage: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Familie anlegen: nur die zwei Namen, der erste geteilte Kalender heißt „Familie“.
private struct CreatePage: View {
    private enum Field {
        case family, owner
    }

    @Environment(AppModel.self) private var model
    let created: (Family) -> Void

    @State private var familyName = ""
    @State private var ownerName = ""
    @FocusState private var focus: Field?

    private var canCreate: Bool {
        ![familyName, ownerName].contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        OnboardingPage(systemImage: "house.fill", title: "Create a Family",
                       subtitle: "The family's data is stored in your iCloud.") {
            VStack(spacing: 12) {
                field("Family name, e.g. The Millers", text: $familyName, field: .family)
                    .submitLabel(.next)
                    .onSubmit { focus = .owner }
                field("Your name", text: $ownerName, field: .owner)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .onSubmit { if canCreate { create() } }
            }
        } actions: {
            PrimaryButton(title: "Create Family", action: create)
                .disabled(!canCreate)
        }
        .onAppear { focus = .family }
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>, field: Field) -> some View {
        TextField(title, text: text)
            .focused($focus, equals: field)
            .padding(16)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func create() {
        let family = model.repository.createFamily(
            name: familyName.trimmingCharacters(in: .whitespaces),
            ownerName: ownerName.trimmingCharacters(in: .whitespaces),
            ownerUserID: model.userID,
            calendarName: String(localized: "Family"))
        model.save()
        created(family)
    }
}

/// Nach dem Anlegen: QR-Code für die anderen, oder später unter „Familie“.
private struct InvitePage: View {
    @Environment(AppModel.self) private var model
    let family: Family
    let finish: () -> Void

    var body: some View {
        OnboardingPage(systemImage: model.sharing.isAvailable ? nil : "icloud.slash",
                       title: "Invite Your Family",
                       subtitle: model.sharing.isAvailable
                           ? "Let the others scan this code to join \(family.name ?? "")."
                           : "\(family.name ?? "") is ready. To invite the others, sign in to iCloud in Settings.") {
            if model.sharing.isAvailable {
                InviteCodeContent(family: family)
            }
        } actions: {
            PrimaryButton(title: "Done", action: finish)
            Text("You can invite more people later under Family.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .navigationBarBackButtonHidden()
    }
}
