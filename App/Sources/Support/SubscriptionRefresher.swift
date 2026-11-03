import Foundation
import YafoKit

/// Lädt abonnierte Quellen (eigene ICS-Adressen, Schulferien) und legt sie in den lokalen
/// Cache. Jedes Gerät lädt selbst; synchronisiert wird nur die Abo-Einstellung.
extension AppModel {
    /// ICS-Abos beim Öffnen der App, aber nicht öfter als alle 15 Minuten.
    static let icsRefreshInterval: TimeInterval = 15 * 60

    func refreshSubscriptions(force: Bool = false) async {
        let sources = repository.subscriptionSources()
        repository.pruneCache(keeping: Set(sources.map(\.sourceKey)))
        let now = Date.now
        for source in sources {
            let interval = source.kind == .schoolHolidays ? SchoolHolidays.refreshInterval : Self.icsRefreshInterval
            if !force, let last = repository.lastFetch(of: source.sourceKey), now.timeIntervalSince(last) < interval {
                continue
            }
            guard let entries = await Self.load(source, now: now) else { continue }
            repository.replaceCache(of: source.sourceKey, with: entries, fetchedAt: now)
        }
        save()
    }

    /// `nil` bei Netzwerk- oder Formatfehlern; dann bleibt der alte Cache stehen.
    private static func load(_ source: SubscriptionSource, now: Date) async -> [SubscriptionEntry]? {
        let url: URL
        switch source.kind {
        case .ics:
            guard let address = source.url else { return nil }
            url = address
        case .schoolHolidays:
            guard let region = SchoolHolidayRegion.region(code: source.region) else { return nil }
            url = SchoolHolidays.url(for: region, around: now)
        case .publicHolidays:
            return nil
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
            switch source.kind {
            case .schoolHolidays:
                return try SchoolHolidays.parse(data)
            default:
                let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
                guard text.contains("BEGIN:VCALENDAR") || text.contains("BEGIN:VEVENT") else { return nil }
                return SubscriptionFeed.entries(from: ICSParser.parse(text), in: SubscriptionFeed.window(around: now))
            }
        } catch {
            return nil
        }
    }
}
