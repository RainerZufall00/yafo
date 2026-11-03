import EventKit
import Foundation
import Observation

/// Kalender des Geräts (Arbeit, Google, CalDAV), die nur in der eigenen Ansicht grau
/// eingeblendet werden. Die Auswahl bleibt auf dem Gerät und wird nicht geteilt.
@MainActor @Observable
final class ExternalCalendars {
    struct Item: Identifiable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let location: String?
        let calendarTitle: String
    }

    private static let defaultsKey = "externalCalendarIDs"

    @ObservationIgnored let store = EKEventStore()
    private(set) var enabledIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(enabledIDs), forKey: Self.defaultsKey) }
    }
    /// Zählt bei jeder Änderung in EventKit hoch, damit Ansichten neu laden.
    private(set) var revision = 0
    @ObservationIgnored private var cache: [DateInterval: [Item]] = [:]
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        enabledIDs = Set(UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? [])
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.storeChanged() }
        }
    }

    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var isActive: Bool { hasAccess && !enabledIDs.isEmpty }

    func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        storeChanged()
        return granted
    }

    var calendars: [EKCalendar] {
        guard hasAccess else { return [] }
        return store.calendars(for: .event).sorted {
            ($0.source.title, $0.title) < ($1.source.title, $1.title)
        }
    }

    func isEnabled(_ calendar: EKCalendar) -> Bool { enabledIDs.contains(calendar.calendarIdentifier) }

    func setEnabled(_ enabled: Bool, for calendar: EKCalendar) {
        if enabled { enabledIDs.insert(calendar.calendarIdentifier) } else { enabledIDs.remove(calendar.calendarIdentifier) }
        storeChanged()
    }

    func items(overlapping interval: DateInterval) -> [Item] {
        _ = revision
        guard isActive else { return [] }
        if let cached = cache[interval] { return cached }
        let chosen = store.calendars(for: .event).filter { enabledIDs.contains($0.calendarIdentifier) }
        guard !chosen.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: chosen)
        let items = store.events(matching: predicate).map { event in
            let calendar = Calendar.current
            let end = event.isAllDay
                ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: event.endDate))!
                : event.endDate!
            return Item(id: "\(event.calendarItemIdentifier)#\(Int(event.startDate.timeIntervalSince1970))",
                        title: event.title ?? "", start: event.isAllDay ? calendar.startOfDay(for: event.startDate) : event.startDate,
                        end: end, isAllDay: event.isAllDay, location: event.location,
                        calendarTitle: event.calendar.title)
        }
        if cache.count > 24 { cache.removeAll() }
        cache[interval] = items
        return items
    }

    private func storeChanged() {
        cache.removeAll()
        revision += 1
    }
}
