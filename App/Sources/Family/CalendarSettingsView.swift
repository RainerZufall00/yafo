import CoreData
import SwiftUI
import YafoKit

/// Einstellungen eines Kalenders: eigene Farbe und Sichtbarkeit (nur für mich),
/// Feiertags-Abo (für alle; bei geteilten Kalendern ändert das nur der Owner).
struct CalendarSettingsView: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var calendar: EventCalendar
    @FetchRequest(sortDescriptors: []) private var appearances: FetchedResults<CalendarAppearance>
    @FetchRequest(sortDescriptors: []) private var subscriptions: FetchedResults<CalendarSubscription>

    /// Abos ändert beim eigenen Kalender man selbst, beim geteilten der Owner.
    private var canEditSubscriptions: Bool {
        calendar.family.map(model.isOwner(of:)) ?? true
    }

    var body: some View {
        let _ = (appearances.count, subscriptions.count)
        let region = model.repository.holidayRegion(of: calendar)
        Form {
            Section {
                ColorPicker("Color", selection: Binding(
                    get: { Color(hex: model.repository.color(of: calendar)) },
                    set: { color in
                        model.repository.setAppearance(of: calendar, color: color.hexString)
                        model.save()
                    }
                ), supportsOpacity: false)
                Toggle("Show in Calendar", isOn: Binding(
                    get: { model.repository.isVisible(calendar) },
                    set: { visible in
                        model.repository.setAppearance(of: calendar, isVisible: visible)
                        model.save()
                    }
                ))
            } footer: {
                Text("Color and visibility only apply to you.")
            }

            Section {
                Picker("Public Holidays", selection: Binding(
                    get: { region },
                    set: { region in
                        model.repository.setHolidayRegion(region, for: calendar)
                        model.save()
                    }
                )) {
                    Text("None").tag(HolidayRegion?.none)
                    Section("Germany") {
                        ForEach(HolidayRegion.allCases.filter(\.isGerman)) { region in
                            Text(region.germanName).tag(HolidayRegion?.some(region))
                        }
                    }
                    Section("Austria & Switzerland") {
                        Text("Austria").tag(HolidayRegion?.some(.at))
                        Text("Switzerland (general)").tag(HolidayRegion?.some(.ch))
                    }
                }
                .pickerStyle(.navigationLink)
                .disabled(!canEditSubscriptions)
            } header: {
                Text("Subscriptions")
            } footer: {
                if !canEditSubscriptions {
                    Text("Only the owner of the family changes subscriptions of shared calendars.")
                } else if let region, let other = model.repository.calendarsSubscribed(to: region, except: calendar).first {
                    Text("Already subscribed via “\(other.displayName)”. It still shows only once.")
                } else {
                    Text("Holidays appear for everyone who sees this calendar.")
                }
            }
        }
        .navigationTitle(calendar.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
