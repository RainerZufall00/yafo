import Foundation
import SwiftUI

/// Die Tabs der App. Der Rohwert landet in den UserDefaults. „Familie“ ist kein Tab, sondern ein
/// Knopf oben rechts (`familyButton()`); ein gemerkter alter Wert `family` fällt auf den Kalender zurück.
enum AppTab: String, CaseIterable, Identifiable {
    case calendar, shopping, todos

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .calendar: "Calendar"
        case .shopping: "Shopping"
        case .todos: "To-dos"
        }
    }
}

/// Einstellung „Beim Öffnen zeigen“: ein fester Tab oder der zuletzt geöffnete.
enum LaunchTab: String, CaseIterable, Identifiable {
    case last, calendar, shopping, todos

    var id: String { rawValue }

    static let key = "launchTab"
    /// So lange muss die App im Hintergrund gewesen sein, damit sie wieder mit dem
    /// gewählten Tab startet. Kurz in eine andere App wechseln reißt einen nicht heraus.
    static let backgroundThreshold: TimeInterval = 5 * 60

    var title: LocalizedStringKey {
        switch self {
        case .last: "Last Opened"
        case .calendar: "Calendar"
        case .shopping: "Shopping"
        case .todos: "To-dos"
        }
    }

    /// `nil` bei „Zuletzt geöffnet“.
    var tab: AppTab? {
        switch self {
        case .last: nil
        case .calendar: .calendar
        case .shopping: .shopping
        case .todos: .todos
        }
    }

    static var current: LaunchTab {
        UserDefaults.standard.string(forKey: key).flatMap(LaunchTab.init(rawValue:)) ?? .last
    }
}

/// Links in die App, z. B. vom Widget: `yafo://calendar`.
enum DeepLink {
    static let scheme = "yafo"
    static let calendar = URL(string: "yafo://calendar")!

    static func tab(for url: URL) -> AppTab? {
        guard url.scheme == scheme, let host = url.host() else { return nil }
        return AppTab(rawValue: host)
    }

    /// Gewählte Liste aus `?list=<key>`; leer oder „sample“ (Widget-Vorschau) zählt nicht.
    static func list(in url: URL) -> String? {
        let list = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "list" }?.value
        guard let list, !list.isEmpty, list != "sample" else { return nil }
        return list
    }
}
