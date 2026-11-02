import SwiftUI
import YafoKit

/// Familie anlegen. Wer sie anlegt, wird Owner; die Daten liegen in seiner iCloud.
struct CreateFamilyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var familyName = ""
    @State private var ownerName = ""
    @State private var calendarName = String(localized: "Family")

    private var canCreate: Bool {
        ![familyName, ownerName, calendarName].contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Family name, e.g. The Millers", text: $familyName)
                    TextField("Your name", text: $ownerName)
                        .textContentType(.givenName)
                } footer: {
                    Text("The family's data is stored in your iCloud. You can invite other adults afterwards.")
                }
                Section("First shared calendar") {
                    TextField("Calendar name", text: $calendarName)
                }
            }
            .navigationTitle("Create Family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", role: .confirm) {
                        model.repository.createFamily(
                            name: familyName.trimmingCharacters(in: .whitespaces),
                            ownerName: ownerName.trimmingCharacters(in: .whitespaces),
                            ownerUserID: model.userID,
                            calendarName: calendarName.trimmingCharacters(in: .whitespaces))
                        model.save()
                        dismiss()
                    }
                    .disabled(!canCreate)
                }
            }
        }
    }
}
