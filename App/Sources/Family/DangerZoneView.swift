import SwiftUI
import YafoKit

/// Endgültiges Löschen, bewusst abseits der übrigen Einstellungen: Familien verlassen oder löschen
/// und alle eigenen Daten entfernen. Jede Aktion fragt zweimal nach, beim zweiten Mal muss der Name
/// der Familie (bzw. „yafo“) eingetippt werden.
struct DangerZoneView: View {
    private enum Action: Identifiable {
        case leave(Family)
        case delete(Family)
        case deleteAll

        var id: String {
            switch self {
            case .leave(let family): "leave-\(family.objectID)"
            case .delete(let family): "delete-\(family.objectID)"
            case .deleteAll: "all"
            }
        }

        /// Was zur Bestätigung eingetippt werden muss.
        var confirmationWord: String {
            switch self {
            case .leave(let family), .delete(let family): family.name ?? ""
            case .deleteAll: "yafo"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)])
    private var families: FetchedResults<Family>

    /// Erste Nachfrage (Dialog), dann zweite (Eingabe des Namens).
    @State private var asking: Action?
    @State private var confirming: Action?
    @State private var typed = ""
    @State private var working = false

    var body: some View {
        List {
            Section {
                Text("Everything here is permanent. There is no undo. Make a backup first under Export & Backup if you are not sure.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            ForEach(families) { family in
                FamilyRemovalSection(family: family) { asking = $0 ? .delete(family) : .leave(family) }
            }

            Section {
                Button("Delete All My Data", systemImage: "trash.fill", role: .destructive) {
                    asking = .deleteAll
                }
            } footer: {
                Text("Removes your own calendar, your private lists, your settings and every family you own, on this device and in your iCloud. Families you were invited to stay; leave them above.")
            }
        }
        .navigationTitle("Delete")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.red) // Symbole der Knöpfe ebenfalls rot, nicht nur der Text
        .disabled(working)
        .overlay {
            if working { ProgressView().controlSize(.large) }
        }
        .confirmationDialog(firstTitle, isPresented: Binding(get: { asking != nil },
                                                             set: { if !$0 { asking = nil } }),
                            titleVisibility: .visible, presenting: asking) { action in
            Button(firstButton(for: action), role: .destructive) {
                typed = ""
                confirming = action
            }
        } message: { action in
            Text(firstMessage(for: action))
        }
        .alert("Are you really sure?", isPresented: Binding(get: { confirming != nil },
                                                           set: { if !$0 { confirming = nil } }),
               presenting: confirming) { action in
            TextField(action.confirmationWord, text: $typed)
                .autocorrectionDisabled()
            Button(firstButton(for: action), role: .destructive) { perform(action) }
                .disabled(!matches(action))
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text("Type “\(action.confirmationWord)” to confirm.")
        }
    }

    // MARK: - Texte

    private var firstTitle: LocalizedStringKey {
        switch asking {
        case .leave(let family): "Leave \(family.name ?? "")?"
        case .delete(let family): "Delete \(family.name ?? "")?"
        case .deleteAll: "Delete all your data?"
        case nil: ""
        }
    }

    private func firstButton(for action: Action) -> LocalizedStringKey {
        switch action {
        case .leave: "Leave Family"
        case .delete: "Delete Family"
        case .deleteAll: "Delete Everything"
        }
    }

    private func firstMessage(for action: Action) -> LocalizedStringKey {
        switch action {
        case .leave:
            "You lose access to the family's calendars and lists. Your profile stays marked as former member so the others keep their events."
        case .delete:
            "All members lose the family's calendars, events, shopping list and to-dos. This cannot be undone."
        case .deleteAll:
            "Your calendar, lists, settings and the families you own are deleted everywhere. This cannot be undone."
        }
    }

    private func matches(_ action: Action) -> Bool {
        typed.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(action.confirmationWord) == .orderedSame
    }

    // MARK: - Ausführen

    private func perform(_ action: Action) {
        working = true
        Task {
            defer { working = false }
            do {
                switch action {
                case .leave(let family), .delete(let family):
                    try await model.remove(family)
                case .deleteAll:
                    // Erst kopieren: die Liste ändert sich beim Löschen.
                    for family in families.filter({ model.isOwner(of: $0) }) {
                        try await model.remove(family)
                    }
                    model.deleteAllOwnData()
                }
                if case .deleteAll = action { dismiss() }
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }
}

/// Eine Familie: Owner löschen sie, Mitglieder verlassen sie.
private struct FamilyRemovalSection: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var family: Family
    /// `true` = löschen (Owner), `false` = verlassen.
    let remove: (Bool) -> Void

    var body: some View {
        let isOwner = model.isOwner(of: family)
        let others = model.repository.activeMembers(of: family).filter { $0.hasAccount && $0 != model.me(in: family) }
        Section {
            if isOwner {
                Button("Delete Family", systemImage: "trash", role: .destructive) { remove(true) }
            } else {
                Button("Leave Family", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    remove(false)
                }
            }
        } header: {
            Text(family.name ?? "")
        } footer: {
            if isOwner {
                if others.isEmpty {
                    Text("You are the only member. Calendars, events and lists are deleted from your iCloud.")
                } else {
                    Text("Deletes the family for all \(others.count + 1) members, including every calendar, event and list.")
                }
            } else {
                Text("You lose access to the family's calendars and lists. The others keep them.")
            }
        }
    }
}
