import SwiftUI
import YafoKit

/// Einladung per QR-Code: ein Einmal-Link für genau eine Person. Wer ihn scannt (iPhone-Kamera oder
/// in yafo unter „Familie beitreten“), tritt bei; für die nächste Person gibt es einen neuen Code.
/// Reiner Inhalt ohne Navigation, damit er ins Onboarding und in ein Blatt passt.
struct InviteCodeContent: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var family: Family
    /// Kinderprofil, für das eingeladen wird (Kind mit eigenem Gerät); `nil` lädt einen Erwachsenen ein.
    var child: Member?

    @State private var code: URL?
    @State private var loading = false
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 20) {
            Group {
                if let code {
                    QRCodeImage(text: code.absoluteString)
                        .opacity(loading ? 0.3 : 1)
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.quaternary)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .frame(maxWidth: 260)
            .overlay {
                if loading {
                    ProgressView()
                } else if code == nil {
                    Image(systemName: "icloud.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)

            if let failure {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Try Again") { Task { await load(fresh: false) } }
            } else {
                Group {
                    if let child {
                        Text("Only for \(child.displayLabel): after scanning, this device uses \(child.displayLabel)'s profile, with all events and to-dos.")
                    } else {
                        Text("Scan with the iPhone camera or in yafo under “Join a Family”. Each code works for one person.")
                    }
                }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if code != nil {
                HStack(spacing: 12) {
                    Button("New Code", systemImage: "arrow.clockwise") {
                        Task { await load(fresh: true) }
                    }
                    if let code {
                        ShareLink("Send Link", item: code)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(loading)
            }

            members
        }
        .task(id: child?.objectID) {
            code = nil
            await load(fresh: false)
        }
    }

    /// Wer schon dabei ist; neue Mitglieder tauchen auf, sobald sie ihr Profil angelegt haben.
    private var members: some View {
        HStack(spacing: 6) {
            ForEach(model.repository.activeMembers(of: family)) { member in
                MemberAvatar(member: member, size: 30)
            }
        }
    }

    private func load(fresh: Bool) async {
        guard !loading else { return }
        loading = true
        failure = nil
        defer { loading = false }
        do {
            let target = child
            let url = try await model.sharing.inviteCode(for: family, child: target, fresh: fresh)
            // Inzwischen wurde eine andere Person gewählt: deren Code lädt gerade selbst.
            if target == child { code = url }
        } catch {
            failure = model.sharing.isAvailable
                ? error.localizedDescription
                : String(localized: "Sign in to iCloud to invite family members.")
        }
    }
}

/// Der QR-Code als Blatt, aus „Familie“ heraus. Der Owner wählt, wen er einlädt: einen Erwachsenen,
/// der sein Profil selbst anlegt, oder ein Kind mit eigenem Gerät, das sein Kinderprofil übernimmt.
struct InviteCodeView: View {
    private enum Audience {
        case adult, child
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var family: Family

    @State private var audience = Audience.adult
    @State private var child: Member?
    @State private var newChildName = ""

    /// Kinderprofile, die noch niemand mit eigenem Gerät übernommen hat.
    private var children: [Member] {
        model.repository.activeMembers(of: family).filter { $0.kind == .child && !$0.hasAccount }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Invite", selection: $audience) {
                        Text("Adult").tag(Audience.adult)
                        Text("Child with Own Device").tag(Audience.child)
                    }
                    .pickerStyle(.segmented)

                    switch audience {
                    case .adult:
                        InviteCodeContent(family: family)
                    case .child:
                        childChooser
                        if let child {
                            InviteCodeContent(family: family, child: child)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(family.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                }
            }
            .onChange(of: audience) {
                if audience == .child, child == nil { child = children.first }
            }
        }
    }

    /// Welches Kind: vorhandenes Profil wählen oder gleich ein neues anlegen.
    @ViewBuilder private var childChooser: some View {
        if !children.isEmpty {
            Picker("Child", selection: $child) {
                ForEach(children) { member in
                    Text(member.displayLabel).tag(Member?.some(member))
                }
            }
            .pickerStyle(.menu)
        }
        HStack {
            TextField(children.isEmpty ? "Name of the child" : "Another child", text: $newChildName)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit(addChild)
            Button("Add", action: addChild)
                .disabled(newChildName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addChild() {
        let name = newChildName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        child = model.repository.addChildProfile(name: name, to: family)
        model.save()
        newChildName = ""
    }
}
