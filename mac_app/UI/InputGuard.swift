import AppKit

/// The remote answers to the mouse and to nothing else: no key ever becomes a PS5 or TV command.
/// Three layers keep it that way:
///   1. the window drops every key event (`shouldSwallow`), except Command shortcuts (quit, close,
///      hide, minimise) and typing inside a sheet (pairing code, login PIN), which send nothing to the console;
///   2. the controls don't take keyboard focus, so Space or Return can't press a focused button;
///   3. every command entry point refuses to run when the event being handled is a key event
///      (`cameFromKeyboard`), which also covers a menu item chosen with Return.
@MainActor
enum InputGuard {
    /// Key events dropped so far. The self-test reads it.
    private(set) static var swallowed = 0

    static func isKeyboard(_ type: NSEvent.EventType?) -> Bool {
        guard let type else { return false }
        return type == .keyDown || type == .keyUp
    }

    /// True while the code that is running was started by a key event.
    static var cameFromKeyboard: Bool { isKeyboard(NSApp.currentEvent?.type) }

    /// Whether `event` must be kept away from the window.
    static func shouldSwallow(_ event: NSEvent) -> Bool {
        guard isKeyboard(event.type) else { return false }
        if event.modifierFlags.contains(.command) { return false }
        if NSApp.keyWindow?.sheetParent != nil { return false }
        swallowed += 1
        return true
    }
}
