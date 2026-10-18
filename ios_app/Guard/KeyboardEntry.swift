import SwiftUI

extension View {
    /// Screens that collect text (pairing code, login PIN) and send nothing to the console let the hardware
    /// keyboard through while they are on screen; everywhere else GuardedApplication drops it.
    func allowsKeyboardEntry() -> some View {
        onAppear { GuardedApplication.allowsKeyboardEntry = true }
            .onDisappear { GuardedApplication.allowsKeyboardEntry = false }
    }

    /// Touch only: no keyboard focus (Tab, arrows, Space and Return, or Full Keyboard Access, never press it).
    func touchOnly() -> some View { focusable(false) }
}
