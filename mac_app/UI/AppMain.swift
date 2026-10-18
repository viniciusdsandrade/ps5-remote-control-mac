import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Mouse only, by design (see InputGuard): keys never reach the remote.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            MainActor.assumeIsolated {
                InputSelfTest.keyHook?(event)
                return InputGuard.shouldSwallow(event) ? nil : event
            }
        }
        if CommandLine.arguments.contains("--selftest-input") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { InputSelfTest.run() }
        }
        if CommandLine.arguments.contains("--selftest-live"), let ps5 = InputSelfTest.theater?.ps5 {
            Task { await LiveSelfTest.run(ps5) }
        }
    }
}

@main
struct PS5RemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var theater: HomeTheater

    init() {
        let ps5 = PS5Controller()
        let tv = LGTVClient()
        // Layer 3 of InputGuard: commands started by a key event are refused.
        ps5.inputGate = { !InputGuard.cameFromKeyboard }
        let selfTest = CommandLine.arguments.contains("--selftest-input")
        ps5.dryRun = selfTest
        let home = HomeTheater(ps5: ps5, tv: tv)
        home.dryRun = selfTest
        InputSelfTest.theater = home
        _theater = StateObject(wrappedValue: home)
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            PS5RemoteView(ps5: theater.ps5, tv: theater.tv)
                .environmentObject(theater)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 440, height: 600)
    }
}
