import SwiftUI
import YafoKit

/// Nach dem Annehmen einer Einladung als Erwachsener: eigenes Profil anlegen. Kinder mit eigenem
/// Gerät lädt der Owner gezielt für ihr Kinderprofil ein; sie übernehmen es ohne diesen Dialog
/// (`AppModel.claimInvitedProfiles`).
struct JoinFamilyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let family: Family

    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $name)
                        .textContentType(.givenName)
                } header: {
                    Text("Welcome to \(family.name ?? "")")
                }
            }
            .onAppear {
                if name.isEmpty { name = model.sharing.invitedName(in: family) ?? "" }
            }
            // Das Profil kam inzwischen anders zustande (Kinderprofil übernommen, anderes Gerät).
            .onChange(of: model.familiesNeedingProfile) {
                if !model.familiesNeedingProfile.contains(family) { dismiss() }
            }
            .navigationTitle("Join Family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join", role: .confirm) { join() }
                        .disabled(model.userID == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func join() {
        guard let userID = model.userID else { return }
        model.repository.join(family, userID: userID, name: name.trimmingCharacters(in: .whitespaces))
        model.save()
        model.refreshAfterSync()
        dismiss()
    }
}
