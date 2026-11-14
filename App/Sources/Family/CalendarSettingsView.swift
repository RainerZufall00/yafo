import CoreData
import SwiftUI
import YafoKit

/// Einstellungen eines Kalenders: eigene Farbe, Termin-Darstellung und Sichtbarkeit (nur für mich),
/// Abos für Feiertage, Schulferien und eigene ICS-Adressen (für alle; bei geteilten
/// Kalendern ändert das nur der Owner).
struct CalendarSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var calendar: EventCalendar
    @FetchRequest(sortDescriptors: []) private var appearances: FetchedResults<CalendarAppearance>
    @FetchRequest(sortDescriptors: []) private var subscriptions: FetchedResults<CalendarSubscription>
    @State private var addingSubscription = false
    @State private var newAddress = ""
    @State private var newName = ""

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
                eventStylePicker
                Toggle("Show in Calendar", isOn: Binding(
                    get: { model.repository.isVisible(calendar) },
                    set: { visible in
                        model.repository.setAppearance(of: calendar, isVisible: visible)
                        model.save()
                    }
                ))
            } footer: {
                Text("Color, event style and visibility only apply to you. The style applies to events with a time; all-day events stay filled.")
            }

            Section {
                Picker("Public Holidays", selection: Binding(
                    get: { region },
                    set: { region in
                        model.repository.setHolidayRegion(region, for: calendar)
                        saveSubscriptions()
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

                Picker("School Holidays", selection: Binding(
                    get: { model.repository.schoolHolidayRegion(of: calendar) },
                    set: { region in
                        model.repository.setSchoolHolidayRegion(region, for: calendar)
                        saveSubscriptions()
                    }
                )) {
                    Text("None").tag(SchoolHolidayRegion?.none)
                    Section("Germany") { schoolRegions(.de) }
                    Section("Austria") { schoolRegions(.at) }
                    Section("Switzerland") { schoolRegions(.ch) }
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
                    Text("Holidays appear for everyone who sees this calendar. School holiday data: OpenHolidays API, ODbL.")
                }
            }

            Section {
                ForEach(model.repository.icsSubscriptions(of: calendar)) { subscription in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(subscription.name ?? "")
                        Text(subscription.url ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .deleteDisabled(!canEditSubscriptions)
                }
                .onDelete { offsets in
                    let list = model.repository.icsSubscriptions(of: calendar)
                    offsets.map { list[$0] }.forEach(model.repository.delete)
                    saveSubscriptions()
                }
                if canEditSubscriptions {
                    Button("Add Calendar Address", systemImage: "plus") {
                        newAddress = ""
                        newName = ""
                        addingSubscription = true
                    }
                }
            } header: {
                Text("Calendar Addresses")
            } footer: {
                Text("e.g. waste collection, school or club calendars. Updated when you open yafo; each device loads them itself.")
            }
        }
        .alert("Add Calendar Address", isPresented: $addingSubscription) {
            TextField("https://… or webcal://…", text: $newAddress)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Name (optional)", text: $newName)
            Button("Add") {
                if model.repository.addICSSubscription(address: newAddress, name: newName, to: calendar) != nil {
                    saveSubscriptions()
                } else {
                    model.errorMessage = String(localized: "This address is not valid or already subscribed.")
                }
            }
            .disabled(SubscriptionFeed.normalizedURL(newAddress) == nil)
            Button("Cancel", role: .cancel) {}
        }
        .navigationTitle(calendar.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Drei Muster-Termine in der Kalenderfarbe zum Antippen.
    private var eventStylePicker: some View {
        let color = Color(hex: model.repository.color(of: calendar))
        let selected = model.repository.eventStyle(of: calendar)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Event Style")
            HStack(spacing: 8) {
                ForEach(EventStyle.allCases, id: \.self) { style in
                    Button {
                        model.repository.setAppearance(of: calendar, eventStyle: style)
                        model.save()
                    } label: {
                        Text(style.title)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(style.textColor(for: color, in: colorScheme))
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(EventBackground(shape: RoundedRectangle(cornerRadius: 5), color: color,
                                                        style: style))
                            .padding(3)
                            .contentShape(Rectangle())
                            .overlay {
                                if style == selected {
                                    RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor, lineWidth: 2)
                                }
                            }
                    }
                    // Borderless: in einer Form-Zeile reagiert sonst die ganze Zeile auf jeden Button.
                    .buttonStyle(.borderless)
                    .accessibilityLabel(style.title)
                    .accessibilityAddTraits(style == selected ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func schoolRegions(_ country: SchoolHolidayRegion.Country) -> some View {
        ForEach(SchoolHolidayRegion.regions(in: country)) { region in
            Text(region.name).tag(SchoolHolidayRegion?.some(region))
        }
    }

    /// Speichern und neue Quellen gleich laden.
    private func saveSubscriptions() {
        model.save()
        Task { await model.refreshSubscriptions() }
    }
}
