import UIKit

/// The app lives in the foreground only: when it leaves (screen locked, another app), the session is let go
/// cleanly. iOS grants a few seconds for that through a background task; nothing runs after it.
@MainActor
enum Lifecycle {
    static func leaveForeground(_ ps5: PS5Controller) {
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "soltar a sessão do PS5") {
            UIApplication.shared.endBackgroundTask(task)
        }
        Task { @MainActor in
            await ps5.suspend()
            UIApplication.shared.endBackgroundTask(task)
        }
    }
}

/// Taptic Engine feedback: the glass gives none, so a pad key down is a light tap and a connection that opens
/// is a distinct one.
@MainActor
enum Haptics {
    private static let tap = UIImpactFeedbackGenerator(style: .light)
    private static let notify = UINotificationFeedbackGenerator()

    static func install() {
        tap.prepare()
        PadFeedback.onKeyDown = { MainActor.assumeIsolated { tap.impactOccurred() } }
    }

    static func connected() { notify.notificationOccurred(.success) }
}
