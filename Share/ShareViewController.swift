import SwiftUI
import UIKit
import UniformTypeIdentifiers
import YafoKit

/// Share Extension „Screenshot zu Termin“: nimmt ein Bild aus jeder App an, erkennt die Termine
/// und zeigt dieselbe Vorschau wie die App. Gespeichert wird nicht hier, sondern als Auftrag im
/// Postfach der App Group: Nur die App schreibt in Core Data und synchronisiert mit iCloud.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let snapshot = WidgetSnapshot.load()
        let calendars = snapshot.calendars.map { calendar in
            ScreenshotReviewView.CalendarOption(
                id: calendar.id,
                name: calendar.familyName.map { "\(calendar.name) · \($0)" } ?? calendar.name,
                colorHex: calendar.colorHex)
        }
        let review = ScreenshotReviewView(
            calendars: calendars,
            saveNote: String(localized: "The events appear in yafo the next time you open it."),
            loadImage: { [weak self] in await self?.loadImage() },
            onSave: { [weak self] suggestions, calendarID in self?.save(suggestions, calendarID: calendarID) },
            onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            }
        )
        let host = UIHostingController(rootView: review)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func save(_ suggestions: [EventSuggestion], calendarID: UUID) {
        do {
            try AppGroupInbox().append(.addEvents(suggestions, calendarID: calendarID))
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            extensionContext?.cancelRequest(withError: error)
        }
    }

    /// Erstes Bild unter den geteilten Anhängen.
    private func loadImage() async -> UIImage? {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) })
        else { return nil }
        let data: Data? = await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: .image) { data, _ in
                continuation.resume(returning: data)
            }
        }
        return data.flatMap(UIImage.init(data:))
    }
}
