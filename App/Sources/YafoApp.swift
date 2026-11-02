import CloudKit
import SwiftUI
import UIKit
import YafoKit

@main
struct YafoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.managedObjectContext, model.persistence.viewContext)
                .task { await model.start() }
        }
    }
}

/// Einladungslinks kommen über den Scene Delegate an, nicht über SwiftUI.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        // Kaltstart über einen Einladungslink.
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Task { await AppModel.shared.accept(metadata) }
        }
    }

    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { await AppModel.shared.accept(cloudKitShareMetadata) }
    }
}
