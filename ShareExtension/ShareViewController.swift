import CoreData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import YafoKit

/// Share Extension „Termin aus Screenshot“: nimmt ein Bild an und zeigt dieselbe Vorschau wie
/// die App. Gespeichert wird direkt in die Stores in der App Group, ohne eigene iCloud-Synchronisation;
/// die App holt die Änderungen beim nächsten Aktivwerden nach und lädt sie hoch.
final class ShareViewController: UIViewController {
    private var persistence: PersistenceController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        Task { await show() }
    }

    private func show() async {
        guard let image = await loadImage() else {
            finish(error: true)
            return
        }
        do {
            let persistence = try PersistenceController.makeDefault(forceLocal: true)
            persistence.viewContext.transactionAuthor = PersistenceController.shareExtensionAuthor
            self.persistence = persistence
            let repository = Repository(persistence: persistence)
            let userID = UserDefaults(suiteName: PersistenceController.appGroupIdentifier)?.string(forKey: "userID")
            let root = ScreenshotImportView(image: image, repository: repository, creatorID: { calendar in
                guard let userID else { return nil }
                guard let family = calendar.family else { return userID }
                return repository.me(in: family, userID: userID)?.id?.uuidString ?? userID
            }, onFinish: { [weak self] _ in self?.finish(error: false) })
                .environment(\.managedObjectContext, persistence.viewContext)
            embed(UIHostingController(rootView: root))
        } catch {
            finish(error: true)
        }
    }

    private func embed(_ child: UIViewController) {
        addChild(child)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(child.view)
        child.didMove(toParent: self)
    }

    private func finish(error: Bool) {
        if error {
            extensionContext?.cancelRequest(withError: CocoaError(.fileReadUnknown))
        } else {
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// Das erste Bild; kommt je nach App als Datei, Daten oder `UIImage`.
    private func loadImage() async -> UIImage? {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) })
        else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier) { item, _ in
                let image: UIImage? = switch item {
                case let image as UIImage: image
                case let url as URL: (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))
                case let data as Data: UIImage(data: data)
                default: nil
                }
                continuation.resume(returning: image)
            }
        }
    }
}
