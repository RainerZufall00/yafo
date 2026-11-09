import SwiftUI
import UIKit
import YafoKit

/// Vorschau „Screenshot zu Termin“, in der App und in der Share Extension: erkannte Termine
/// prüfen, bearbeiten, abwählen, Ziel-Kalender wählen und übernehmen.
struct ScreenshotReviewView: View {
    struct CalendarOption: Identifiable, Hashable {
        let id: UUID
        let name: String
        let colorHex: String
    }

    /// Zuletzt gewählter Kalender, gemeinsam für App und Share Extension.
    static let lastCalendarKey = "screenshotCalendarID"

    let calendars: [CalendarOption]
    /// Hinweis unter dem Hinzufügen-Knopf, z. B. dass die Share Extension erst die App braucht.
    var saveNote: String?
    let loadImage: () async -> UIImage?
    let onSave: ([EventSuggestion], UUID) -> Void
    let onCancel: () -> Void

    @State private var image: UIImage?
    @State private var isAnalyzing = true
    @State private var method: ScreenshotAnalyzer.Method?
    @State private var suggestions: [EventSuggestion] = []
    @State private var excluded: Set<UUID> = []
    @State private var calendarID: UUID?

    private var chosen: [EventSuggestion] {
        suggestions.filter { !excluded.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if isAnalyzing {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Looking for events…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if image == nil {
                    Section {
                        Text("The image couldn't be loaded.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if suggestions.isEmpty {
                        Section {
                            Text("No events found in this screenshot.")
                                .foregroundStyle(.secondary)
                            Button("Add Event Manually", systemImage: "plus") { addBlank() }
                        }
                    }
                    ForEach($suggestions) { $suggestion in
                        SuggestionSection(suggestion: $suggestion, isIncluded: Binding(
                            get: { !excluded.contains(suggestion.id) },
                            set: { if $0 { excluded.remove(suggestion.id) } else { excluded.insert(suggestion.id) } }
                        ))
                    }
                    if !suggestions.isEmpty {
                        calendarSection
                    }
                }
                if let image {
                    Section {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } footer: {
                        Text(methodNote)
                    }
                }
            }
            .navigationTitle("Events from Screenshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if chosen.count > 1 { Text("Add \(chosen.count)") } else { Text("Add") }
                    }
                    .disabled(isAnalyzing || chosen.isEmpty || calendarID == nil)
                }
            }
        }
        .task { await analyze() }
    }

    private var calendarSection: some View {
        Section {
            if calendars.isEmpty {
                Text("No calendar available. Open yafo once, then try again.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Calendar", selection: $calendarID) {
                    ForEach(calendars) { calendar in
                        Label {
                            Text(calendar.name)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(swatch(calendar.colorHex))
                        }
                        .tag(UUID?.some(calendar.id))
                    }
                }
                .pickerStyle(.navigationLink)
            }
        } footer: {
            if let saveNote { Text(saveNote) }
        }
    }

    private var methodNote: String {
        switch method {
        case .imageModel, .textModel:
            String(localized: "Recognized with Apple Intelligence on this device. The image never leaves it.")
        case .dataDetector:
            String(localized: "Without Apple Intelligence, yafo only finds dates in the text. Please check titles and times.")
        case nil:
            String(localized: "The image never leaves this device.")
        }
    }

    private func analyze() async {
        guard isAnalyzing else { return }
        image = await loadImage()
        if let image {
            let result = await ScreenshotAnalyzer.analyze(image)
            suggestions = result.suggestions
            method = result.method
        }
        let last = UserDefaults(suiteName: PersistenceController.appGroupIdentifier)?
            .string(forKey: Self.lastCalendarKey).flatMap(UUID.init(uuidString:))
        calendarID = calendars.first { $0.id == last }?.id ?? calendars.first?.id
        isAnalyzing = false
    }

    private func addBlank() {
        let calendar = Calendar.current
        let hour = calendar.dateInterval(of: .hour, for: .now)?.end ?? .now
        suggestions.append(EventSuggestion(title: "", start: hour, end: hour.addingTimeInterval(3600), isAllDay: false))
    }

    private func save() {
        guard let calendarID else { return }
        UserDefaults(suiteName: PersistenceController.appGroupIdentifier)?
            .set(calendarID.uuidString, forKey: Self.lastCalendarKey)
        onSave(chosen.map { $0.normalized() }, calendarID)
    }

    private func swatch(_ hex: String) -> Color {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x8E8E93
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}

/// Ein erkannter Termin zum Bearbeiten.
private struct SuggestionSection: View {
    @Binding var suggestion: EventSuggestion
    @Binding var isIncluded: Bool

    var body: some View {
        Section {
            Toggle(isOn: $isIncluded) {
                TextField("Title", text: $suggestion.title)
                    .font(.headline)
            }
            if isIncluded {
                Toggle("All day", isOn: Binding(
                    get: { suggestion.isAllDay },
                    set: { allDay in
                        suggestion.isAllDay = allDay
                        if !allDay, suggestion.end.timeIntervalSince(suggestion.start) >= 86_400 {
                            suggestion.end = suggestion.start.addingTimeInterval(3600)
                        }
                    }
                ))
                DatePicker("Starts", selection: Binding(
                    get: { suggestion.start },
                    set: { newStart in
                        // Dauer beibehalten, wenn der Beginn verschoben wird.
                        let duration = suggestion.end.timeIntervalSince(suggestion.start)
                        suggestion.start = newStart
                        suggestion.end = newStart.addingTimeInterval(max(duration, 0))
                    }
                ), displayedComponents: suggestion.isAllDay ? .date : [.date, .hourAndMinute])
                DatePicker("Ends", selection: Binding(
                    get: { suggestion.isAllDay ? suggestion.end.addingTimeInterval(-1) : suggestion.end },
                    set: { suggestion.end = max($0, suggestion.start) }
                ), in: suggestion.start..., displayedComponents: suggestion.isAllDay ? .date : [.date, .hourAndMinute])
                TextField("Location", text: Binding(
                    get: { suggestion.location ?? "" },
                    set: { suggestion.location = $0.isEmpty ? nil : $0 }
                ))
            }
        }
    }
}
