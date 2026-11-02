import CloudKit
import UIKit

/// Zeigt den System-Freigabedialog (`UICloudSharingController`) für den Share einer Familie.
/// Direkt über UIKit, weil der Controller als Sheet in SwiftUI nicht zuverlässig funktioniert.
enum CloudSharingPresenter {
    /// Der Controller hält seinen Delegate nur schwach.
    private static var delegate: Delegate?

    static func present(share: CKShare, container: CKContainer, title: String) {
        let controller = UICloudSharingController(share: share, container: container)
        // Alle Erwachsenen bekommen Schreibrechte, nur per Einladung.
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        delegate = Delegate(title: title)
        controller.delegate = delegate
        topViewController()?.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    private final class Delegate: NSObject, UICloudSharingControllerDelegate {
        let title: String

        init(title: String) {
            self.title = title
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            title
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            AppModel.shared.errorMessage = error.localizedDescription
        }
    }
}
