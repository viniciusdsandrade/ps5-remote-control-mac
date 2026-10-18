import SwiftUI
import UIKit

final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // The pairing lives in the Keychain of this device only; tests point PS5_KEYCHAIN_SERVICE elsewhere so
        // they never touch the real pairing.
        let service = ProcessInfo.processInfo.environment["PS5_KEYCHAIN_SERVICE"] ?? "ps5remote.pairing"
        PSHostStorage.current = KeychainHostStore(service: service)
        // iOS only lets an app send broadcast with an entitlement from Apple: ask the saved address first and,
        // if it stays silent, probe the local subnet address by address (unicast).
        PSDiscovery.policy = PSDiscoveryPolicy(broadcast: false, sweepAfter: 1.0)
        return true
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: DiagnosticView())
        window.makeKeyAndVisible()
        self.window = window
    }
}
