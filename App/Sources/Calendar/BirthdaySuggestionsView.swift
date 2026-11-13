import CoreData
import SwiftUI
import YafoKit

/// Weggeklickte Vorschläge (Termin-IDs, durch Kommas getrennt), nur auf dem Gerät. Ansichten lesen den
/// Wert zusätzlich per `@AppStorage`, damit sie sich beim Ändern neu zeichnen.
enum DismissedBirthdays {
    static func ids(_ raw: String) -> Set<String> { Set(raw.split(separator: ",").map(String.init)) }

    static func dismiss(_ suggestions: some Sequence<BirthdaySuggestion>) {
        let defaults = UserDefaults.standard
        let current = ids(defaults.string(forKey: CalendarDisplay.dismissedBirthdaysKey) ?? "")
        let new = current.union(suggestions.flatMap(\.events).compactMap { $0.id?.uuidString })
        defaults.set(new.sorted().joined(separator: ","), forKey: CalendarDisplay.dismissedBirthdaysKey)
    }
}

/// Hinweis über dem Kalender, wenn Termine wie Geburtstage aussehen (z. B. nach einem Import).
struct BirthdaySuggestionBanner: View {
    @FetchRequest(sortDescriptors: [], predicate: Repository.birthdayCandidatePredicate)
    private var candidates: FetchedResults<Event>
    @AppStorage(CalendarDisplay.dismissedBirthdaysKey) private var dismissedRaw = ""
    @State private var reviewing = false

    var body: some View {
        let suggestions = Repository.birthdaySuggestions(among: candidates, dismissed: DismissedBirthdays.ids(dismissedRaw))
        if !suggestions.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "birthday.cake.fill")
                    .font(.title3)
                    .foregroundStyle(Color(hex: CalendarColors.birthdayDefault))
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(suggestions.count) events look like birthdays")
                        .font(.subheadline.weight(.semibold))
                    Text("As birthdays they repeat every year and show the age.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button("Review") { reviewing = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Not Now", systemImage: "xmark") {
                    withAnimation(.snappy) { DismissedBirthdays.dismiss(suggestions) }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
            .sheet(isPresented: $reviewing) {
                NavigationStack {
                    BirthdaySuggestionsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done", role: .confirm) { reviewing = false }
                            }
                        }
                }
            }
        }
    }
}

/// Alle Vorschläge zum Umwandeln oder Ignorieren; auch unter Familie › Geburtstage erreichbar.
struct BirthdaySuggestionsView: View {
    @Environment(AppModel.self) private var model
    @FetchRequest(sortDescriptors: [], predicate: Repository.birthdayCandidatePredicate)
    private var candidates: FetchedResults<Event>
    @AppStorage(CalendarDisplay.dismissedBirthdaysKey) private var dismissedRaw = ""
    @State private var showingIgnored = false

    var body: some View {
        let dismissed = DismissedBirthdays.ids(dismissedRaw)
        let all = Repository.birthdaySuggestions(among: candidates)
        let suggestions = all.filter { !isDismissed($0, dismissed) }
        let ignored = all.filter { isDismissed($0, dismissed) }
        List {
            Section {
                if suggestions.isEmpty {
                    Text("No events that look like birthdays.")
                        .foregroundStyle(.secondary)
                }
                ForEach(suggestions) { suggestion in
                    row(suggestion)
                        .swipeActions {
                            Button("Ignore", systemImage: "eye.slash") {
                                withAnimation { DismissedBirthdays.dismiss([suggestion]) }
                            }
                        }
                }
            } footer: {
                Text("All-day events with “Birthday” in the title. As birthdays they repeat every year, show the age and get their own color. Copies from other years are removed.")
            }
            if !ignored.isEmpty {
                Section {
                    DisclosureGroup("Ignored (\(ignored.count))", isExpanded: $showingIgnored) {
                        ForEach(ignored) { suggestion in
                            row(suggestion)
                        }
                        Button("Show All Again") {
                            withAnimation { dismissedRaw = "" }
                        }
                    }
                }
            }
        }
        .navigationTitle("Birthday Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if suggestions.count > 1 {
                ToolbarItem(placement: .bottomBar) {
                    Button("Convert All (\(suggestions.count))") {
                        withAnimation {
                            suggestions.forEach { model.repository.convertToBirthday($0) }
                            model.save()
                        }
                    }
                }
            }
        }
    }

    private func isDismissed(_ suggestion: BirthdaySuggestion, _ dismissed: Set<String>) -> Bool {
        suggestion.events.contains { $0.id.map { dismissed.contains($0.uuidString) } ?? false }
    }

    private func row(_ suggestion: BirthdaySuggestion) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.name)
                    .font(.body.weight(.semibold))
                Group {
                    if let year = suggestion.birthYear {
                        Text("\(suggestion.day.formatted(.dateTime.day().month(.wide))) · born \(String(year))")
                    } else {
                        Text(suggestion.day.formatted(.dateTime.day().month(.wide)))
                    }
                }
                .font(.subheadline)
                Text(origin(suggestion))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("Convert") {
                withAnimation {
                    model.repository.convertToBirthday(suggestion)
                    model.save()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func origin(_ suggestion: BirthdaySuggestion) -> String {
        let title = suggestion.event.title ?? ""
        let calendar = suggestion.event.calendar?.displayName ?? ""
        if suggestion.duplicates.isEmpty {
            return String(localized: "“\(title)” in \(calendar)")
        }
        return String(localized: "“\(title)” in \(calendar), \(suggestion.events.count) entries")
    }
}
