import SwiftUI
import YafoKit

/// Einer Familie per QR-Code beitreten: Code scannen (oder Einladungslink einfügen), Einladung annehmen,
/// auf die Familiendaten warten und das eigene Profil anlegen. Reiner Inhalt ohne Navigation, damit er
/// ins Onboarding und in ein Blatt passt.
struct JoinCodeContent: View {
    private enum Phase {
        case scanning, accepting, waiting
    }

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    /// Profil angelegt, oder es geht ohne weiter (die App fragt später nach dem Profil).
    let onFinished: () -> Void

    @State private var phase = Phase.scanning
    @State private var camera: QRScanner.Access?
    @State private var failure: String?
    /// Zuletzt abgelehnter Text; derselbe Code im Bild soll nicht dauernd neu geprüft werden.
    @State private var rejected: String?
    @State private var profileFamily: Family?

    var body: some View {
        VStack(spacing: 20) {
            switch phase {
            case .scanning: scanning
            case .accepting: progress("Accepting invitation…")
            case .waiting: waiting
            }
        }
        .task {
            if camera == nil { camera = await QRScanner.requestAccess() }
        }
        .onAppear { model.joinHandledElsewhere = true }
        .onDisappear { model.joinHandledElsewhere = false }
        .onChange(of: model.familiesNeedingProfile) { offerProfile() }
        // Einladung galt einem Kinderprofil: es ist schon übernommen, kein Profil-Dialog nötig.
        .onChange(of: model.claimedProfile) {
            if phase == .waiting, profileFamily == nil { onFinished() }
        }
        .sheet(item: $profileFamily, onDismiss: onFinished) { family in
            JoinFamilyView(family: family)
        }
    }

    // MARK: - Schritte

    @ViewBuilder private var scanning: some View {
        Group {
            switch camera {
            case .granted:
                QRScanner { handle($0) }
            case .denied:
                placeholder("Camera access is turned off.", systemImage: "camera.fill") {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            case .unsupported:
                placeholder("This device can't scan codes. Paste the invitation link instead.",
                            systemImage: "qrcode.viewfinder") { EmptyView() }
            case nil:
                Color.clear
            }
        }
        .frame(maxWidth: 300)
        .aspectRatio(1, contentMode: .fit)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

        if let failure {
            Text(failure)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }

        if !model.sharing.isAvailable {
            Label("Sign in to iCloud to join a family.", systemImage: "icloud.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        VStack(spacing: 10) {
            Text("Got a link instead? Tap it in Messages or Mail, or paste it here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            PasteButton(payloadType: String.self) { strings in
                if let text = strings.first { handle(text, pasted: true) }
            }
            .labelStyle(.titleAndIcon)
        }
    }

    @ViewBuilder private var waiting: some View {
        progress("Loading the family from iCloud…")
        Text("This can take a moment. If you continue, yafo asks for your profile as soon as the family is there.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        Button("Continue Without Waiting", action: onFinished)
    }

    private func progress(_ title: LocalizedStringKey) -> some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(title).font(.headline)
        }
        .padding(.vertical, 40)
    }

    private func placeholder(_ text: LocalizedStringKey, systemImage: String,
                             @ViewBuilder action: () -> some View) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            action()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Ablauf

    private func handle(_ text: String, pasted: Bool = false) {
        guard phase == .scanning, pasted || text != rejected else { return }
        guard let url = FamilySharing.inviteURL(from: text) else {
            rejected = text
            failure = String(localized: "This is not a yafo invitation.")
            return
        }
        phase = .accepting
        failure = nil
        Task {
            do {
                let claimedBefore = model.claimedProfile
                try await model.accept(inviteURL: url)
                phase = .waiting
                if model.claimedProfile != claimedBefore { return onFinished() }
                offerProfile()
            } catch {
                rejected = text
                failure = error.localizedDescription
                phase = .scanning
            }
        }
    }

    /// Sobald die Familie aus iCloud da ist, nach dem eigenen Profil fragen.
    private func offerProfile() {
        guard phase == .waiting, profileFamily == nil,
              let family = model.familiesNeedingProfile.first else { return }
        profileFamily = family
    }
}

/// Beitreten per Code als Blatt, aus „Familie“ heraus.
struct JoinCodeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                JoinCodeContent { dismiss() }
                    .padding(24)
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle("Join a Family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
    }
}
