import UIKit

/// The remote answers to touch and to nothing else: no key ever becomes a PS5 or TV command. On iOS the first
/// layer of that guarantee is here: every UIEvent goes through `sendEvent`, and a hardware-keyboard press
/// (`.presses`) is dropped before any view sees it. Typing stays possible only while a screen that sends
/// nothing to the console (the pairing code, the login PIN) turns `allowsKeyboardEntry` on.
final class GuardedApplication: UIApplication {
    /// Key presses dropped so far; the tests read it.
    private(set) static var droppedPresses = 0
    /// True only inside the screens that collect text and send nothing to the console.
    static var allowsKeyboardEntry = false

    /// Type of the event being dispatched right now, for the third layer (commands refuse to run when the
    /// event that started them was a key press).
    private(set) static var currentEventType: UIEvent.EventType?
    static var cameFromKeyboard: Bool { currentEventType == .presses }

    override func sendEvent(_ event: UIEvent) {
        if event.type == .presses, !Self.allowsKeyboardEntry {
            Self.droppedPresses += 1
            return
        }
        Self.currentEventType = event.type
        defer { Self.currentEventType = nil }
        super.sendEvent(event)
    }
}
