import Contacts
import CoreData
import SwiftUI
import UIKit
import YafoKit

/// Geburtstage aus den Kontakten übernehmen: alle Kontakte mit Geburtsdatum, pro Kontakt
/// „Nur ich“, ein geteilter Kalender oder gar nicht. Gibt es den Geburtstag vermutlich schon
/// (gleicher Tag, gleiches Jahr), ist „Nicht übernehmen“ vorgewählt und ein Hinweis zeigt, wo.
struct BirthdayImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt)])
    private var calendars: FetchedResults<EventCalendar>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)])
    private var families: FetchedResults<Family>

    @State private var candidates: [BirthdayCandidate]?
    /// Ziel je Kontakt-ID; fehlt ein Eintrag, wird der Kontakt nicht übernommen.
    @State private var targets: [String: EventCalendar] = [:]
    @State private var matches: [String: [Event]] = [:]
    @State private var accessDenied = false
    @State private var importedCount: Int?
    @State private var errorText: String?

    private var personalCalendar: EventCalendar? { calendars.first { $0.family == nil } }

    var body: some View {
        NavigationStack {
            Form {
                if let importedCount {
                    Section {
                        Label("\(importedCount) birthdays imported", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else if accessDenied {
                    deniedSection
                } else if let candidates {
                    if candidates.isEmpty {
                        ContentUnavailableView("No birthdays in your contacts", systemImage: "birthday.cake",
                                               description: Text("Add a birthday to a contact and try again."))
                    } else {
                        listSections(candidates)
                    }
                }
                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Birthdays")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(importedCount == nil ? "Cancel" : "Done", role: .cancel) { dismiss() }
                }
                if importedCount == nil, candidates?.isEmpty == false {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import (\(targets.count))", role: .confirm, action: importSelected)
                            .disabled(targets.isEmpty)
                    }
                }
            }
            .overlay {
                if candidates == nil && !accessDenied && errorText == nil { ProgressView() }
            }
            .task { await load() }
        }
    }

    // MARK: Liste

    @ViewBuilder
    private func listSections(_ candidates: [BirthdayCandidate]) -> some View {
        Section {
            Menu {
                ForEach(calendars) { calendar in
                    Button(calendarLabel(calendar)) { chooseAll(calendar) }
                }
                Divider()
                Button("None", role: .destructive) { targets = [:] }
            } label: {
                Label("Choose for All New Ones", systemImage: "checklist")
            }
        } footer: {
            Text("Birthdays that probably exist already stay unselected. Shared calendars are seen by the whole family.")
        }
        Section("\(candidates.count) contacts with a birthday") {
            ForEach(candidates) { candidate in
                row(candidate)
            }
        }
    }

    private func row(_ candidate: BirthdayCandidate) -> some View {
        Picker(selection: Binding(
            get: { targets[candidate.id]?.objectID },
            set: { id in targets[candidate.id] = id.flatMap { id in calendars.first { $0.objectID == id } } }
        )) {
            Text("Don't Import").tag(NSManagedObjectID?.none)
            ForEach(calendars) { calendar in
                Text(calendarLabel(calendar)).tag(NSManagedObjectID?.some(calendar.objectID))
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name)
                Text(dateText(candidate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let existing = matches[candidate.id]?.first {
                    Text("\(Image(systemName: "exclamationmark.circle")) \(hint(for: existing, candidate: candidate))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .pickerStyle(.menu)
    }

    private var deniedSection: some View {
        Section {
            Label("yafo has no access to your contacts.", systemImage: "person.crop.circle.badge.xmark")
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        } footer: {
            Text("Only names and birthdays are read. Nothing leaves your device unless you put a birthday in a shared calendar.")
        }
    }

    // MARK: Texte

    /// Wie im Termin-Editor: Familienname nur, wenn man in mehreren Familien ist.
    private func calendarLabel(_ calendar: EventCalendar) -> String {
        guard let family = calendar.family else { return calendar.displayName }
        return families.count > 1 ? "\(calendar.displayName) · \(family.name ?? "")" : calendar.displayName
    }

    private func dateText(_ candidate: BirthdayCandidate) -> String {
        let date = candidate.day()
        if candidate.year != nil {
            return date.formatted(.dateTime.day().month(.wide).year())
        }
        return date.formatted(.dateTime.day().month(.wide))
    }

    private func hint(for existing: Event, candidate: BirthdayCandidate) -> String {
        let name = existing.title ?? ""
        let calendar = existing.calendar?.displayName ?? ""
        return existing.importUID?.hasSuffix(candidate.id) == true
            ? String(localized: "Already imported into \(calendar)")
            : String(localized: "Probably exists already: \(name) in \(calendar)")
    }

    // MARK: Ablauf

    private func load() async {
        guard candidates == nil else { return }
        let store = CNContactStore()
        do {
            if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
                _ = try await store.requestAccess(for: .contacts)
            }
            switch CNContactStore.authorizationStatus(for: .contacts) {
            case .authorized, .limited:
                break
            default:
                accessDenied = true
                return
            }
            let loaded = try await Task.detached { try ContactBirthdays.load() }.value
            var targets: [String: EventCalendar] = [:]
            var matches: [String: [Event]] = [:]
            for candidate in loaded {
                let found = model.repository.matchingBirthdays(for: candidate)
                if !found.isEmpty { matches[candidate.id] = found }
                if found.isEmpty, let personalCalendar { targets[candidate.id] = personalCalendar }
            }
            self.matches = matches
            self.targets = targets
            candidates = loaded
        } catch {
            errorText = error.localizedDescription
            candidates = []
        }
    }

    /// Alle ohne vermutlichen Doppelgänger in einen Kalender.
    private func chooseAll(_ calendar: EventCalendar) {
        for candidate in candidates ?? [] where matches[candidate.id] == nil {
            targets[candidate.id] = calendar
        }
    }

    private func importSelected() {
        var count = 0
        for candidate in candidates ?? [] {
            guard let calendar = targets[candidate.id] else { continue }
            model.repository.importBirthday(candidate, into: calendar, createdBy: model.creatorID(for: calendar))
            count += 1
        }
        model.save()
        importedCount = count
    }
}

/// Liest Namen und Geburtstage aus den Kontakten; läuft nicht auf dem Main Thread.
nonisolated enum ContactBirthdays {
    static func load() throws -> [BirthdayCandidate] {
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        var result: [BirthdayCandidate] = []
        try CNContactStore().enumerateContacts(with: request) { contact, _ in
            guard let birthday = contact.birthday, let month = birthday.month, let day = birthday.day,
                  month != NSDateComponentUndefined, day != NSDateComponentUndefined else { return }
            let name = CNContactFormatter.string(from: contact, style: .fullName)
                ?? (contact.nickname.isEmpty ? nil : contact.nickname)
            guard let name, !name.isEmpty else { return }
            let year = birthday.year.flatMap { $0 == NSDateComponentUndefined || $0 < 1800 ? nil : $0 }
            result.append(BirthdayCandidate(id: contact.identifier, name: name, month: month, day: day, year: year))
        }
        return result
    }
}
