import EventKit
import SwiftUI

/// Auswahl der Gerätekalender, die grau in der eigenen Ansicht erscheinen.
struct ExternalCalendarsView: View {
    @Environment(AppModel.self) private var model
    @State private var denied = false

    var body: some View {
        let external = model.external
        let _ = external.revision
        Form {
            if !external.hasAccess {
                Section {
                    Button("Allow Access to Calendars", systemImage: "calendar") {
                        Task { denied = !(await external.requestAccess()) }
                    }
                    if denied {
                        Text("yafo has no access to your calendars. You can allow it in Settings.")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    footer
                }
            } else {
                Section {
                    ForEach(external.calendars, id: \.calendarIdentifier) { calendar in
                        Toggle(isOn: Binding(
                            get: { external.isEnabled(calendar) },
                            set: { external.setEnabled($0, for: calendar) }
                        )) {
                            VStack(alignment: .leading) {
                                Text(calendar.title)
                                Text(calendar.source.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    footer
                }
            }
        }
        .navigationTitle("Device Calendars")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var footer: some View {
        Text("Events from these calendars appear in gray, only on this device and only for you. yafo does not change or share them.")
    }
}
