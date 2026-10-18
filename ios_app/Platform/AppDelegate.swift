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
        PSDiscovery.policy = PSDiscoveryPolicy(broadcast: false, sweepAfter: 1.0, sweepMinInterval: 30)
        Haptics.install()
        if UITestMode.isOn { UITestMode.installSyntheticPairing() }
        return true
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let ps5 = PS5Controller()
        // Third layer of "touch only": a command refuses to run when the event that started it was a key press.
        ps5.inputGate = { !GuardedApplication.cameFromKeyboard }
        let theater = HomeTheater(ps5: ps5, tv: LGTVClient())
        if UITestMode.isOn { ps5.dryRun = true; theater.dryRun = true }
        window.rootViewController = UIHostingController(rootView: RootView(theater: theater))
        if CommandLine.arguments.contains("-ps5-selftest-input") {
            // Needs the test mode (dry run, made-up pairing); runs once the first screen is up.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { InputSelfTest.run(theater: theater) }
        }
        window.makeKeyAndVisible()
        self.window = window
    }
}
