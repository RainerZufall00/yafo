import SwiftUI
import YafoKit

/// Nach dem Annehmen einer Einladung: eigenes Profil anlegen oder, als Teenager,
/// ein vorhandenes Kinderprofil übernehmen (bisherige Teilnahmen bleiben).
struct JoinFamilyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let family: Family

    @State private var name = ""
    @State private var linkedProfile: Member?

    private var unlinkedChildren: [Member] {
        model.repository.activeMembers(of: family).filter { $0.kind == .child && !$0.hasAccount }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $name)
                        .textContentType(.givenName)
                        .disabled(linkedProfile != nil)
                } header: {
                    Text("Welcome to \(family.name ?? "")")
                }
                if !unlinkedChildren.isEmpty {
                    Section {
                        Picker("Child profile", selection: $linkedProfile) {
                            Text("None, I'm new here").tag(Member?.none)
                            ForEach(unlinkedChildren) { child in
                                Text(child.displayLabel).tag(Member?.some(child))
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } header: {
                        Text("Already have a child profile?")
                    } footer: {
                        Text("Link your Apple Account to an existing profile to keep its events.")
                    }
                }
            }
            .navigationTitle("Join Family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join", role: .confirm) { join() }
                        .disabled(model.userID == nil
                                  || linkedProfile == nil && name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func join() {
        guard let userID = model.userID else { return }
        model.repository.join(family, userID: userID, name: name.trimmingCharacters(in: .whitespaces),
                              linking: linkedProfile)
        model.save()
        model.refreshAfterSync()
        dismiss()
    }
}
