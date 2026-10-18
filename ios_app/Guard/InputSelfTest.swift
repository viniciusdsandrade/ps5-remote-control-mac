import UIKit

/// `-ps5-selftest-input`: the iPhone twin of the Mac's --selftest-input. It posts 52 synthetic key events (the
/// same 26 keys, down and up) through the app's real `sendEvent`, in the two situations that matter:
///   1. an ordinary screen: every key must be dropped before it reaches a view;
///   2. a text sheet (pairing code, login PIN), where keys are allowed through: every command attempted while a
///      key event is being dispatched must be refused (the third layer);
/// then the same commands from a touch-like context must go through. Dry run: nothing goes to the PS5 or the TV.
/// Exits with 0 (pass) or 1 (fail) and prints the report. The XCUITest in the Simulator cannot do this: its
/// typeKey does not arrive as UIPressesEvent.
@MainActor
enum InputSelfTest {
    private final class FakeKeyEvent: UIEvent {
        override var type: UIEvent.EventType { .presses }
    }

    private static let keyNames = ["↑", "↓", "←", "→", "Return", "Enter", "Espaço", "Esc", "Delete", "Delete adiante", "Tab",
                                   "s", "t", "h", "o", "c", "p", "[", "]", ",", ".", "=", "-", "m", "1", "0"]

    static func run(theater: HomeTheater) {
        var report: [String] = []
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            report.append((ok ? "ok     " : "FALHA  ") + what)
            if !ok { failures += 1 }
        }
        func finish() -> Never {
            print(report.joined(separator: "\n"))
            print(failures == 0 ? "RESULTADO: passou" : "RESULTADO: \(failures) falha(s)")
            fflush(stdout)
            exit(failures == 0 ? 0 : 1)
        }

        let ps5 = theater.ps5
        guard ps5.dryRun, theater.dryRun else { check(false, "autoteste fora do modo de teste (dry run)"); finish() }
        check(PSHostStorage.current is MemoryHostStore, "autoteste usa o pareamento de mentira, nunca o do Keychain")

        func attemptEverything() {
            ps5.tap(.cross); ps5.press(.circle); ps5.release(.circle)
            ps5.setLeftStick(x: 20000, y: 0); ps5.setTrigger(.l2, 255)
            ps5.home(); ps5.watch(); ps5.wake(); ps5.requestStandby()
            theater.tvKey(.volumeUp); theater.tvKey(.mute); theater.turnOnAll(); theater.turnOffAll()
        }

        var dispatched = 0
        var seenAsKeyboard = 0
        GuardedApplication.testHook = { _ in
            dispatched += 1
            if GuardedApplication.cameFromKeyboard { seenAsKeyboard += 1 }
            attemptEverything()
            return true
        }
        func postKeys() {
            for _ in keyNames { for _ in 0..<2 { GuardedApplication.shared.sendEvent(FakeKeyEvent()) } }
        }
        let expected = keyNames.count * 2

        // 1. Ordinary screen: the guard drops every key before any view (or the hook) sees it.
        GuardedApplication.allowsKeyboardEntry = false
        var droppedBefore = GuardedApplication.droppedPresses
        var acceptedBefore = ps5.acceptedCommands, tvBefore = theater.tvCommands
        postKeys()
        check(GuardedApplication.droppedPresses - droppedBefore == expected,
              "tela comum: o app descartou \(GuardedApplication.droppedPresses - droppedBefore) de \(expected) eventos de tecla")
        check(dispatched == 0, "tela comum: \(dispatched) teclas chegaram às telas (esperado 0)")
        check(ps5.acceptedCommands == acceptedBefore, "tela comum: comandos do PS5 aceitos durante teclas: \(ps5.acceptedCommands - acceptedBefore) (esperado 0)")
        check(theater.tvCommands == tvBefore, "tela comum: comandos da TV aceitos durante teclas: \(theater.tvCommands - tvBefore) (esperado 0)")

        // 2. Text sheet: keys pass, but no command may run while the event being handled is a key press.
        GuardedApplication.allowsKeyboardEntry = true
        droppedBefore = GuardedApplication.droppedPresses
        acceptedBefore = ps5.acceptedCommands; tvBefore = theater.tvCommands
        dispatched = 0; seenAsKeyboard = 0
        postKeys()
        GuardedApplication.allowsKeyboardEntry = false
        check(dispatched == expected, "folha de digitar: \(dispatched) de \(expected) teclas passaram (digitar continua possível)")
        check(seenAsKeyboard == dispatched, "folha de digitar: durante cada tecla o evento corrente era de teclado (\(seenAsKeyboard)/\(dispatched))")
        check(GuardedApplication.droppedPresses == droppedBefore, "folha de digitar: nenhuma tecla descartada")
        check(ps5.acceptedCommands == acceptedBefore, "folha de digitar: comandos do PS5 aceitos durante teclas: \(ps5.acceptedCommands - acceptedBefore) (esperado 0)")
        check(theater.tvCommands == tvBefore, "folha de digitar: comandos da TV aceitos durante teclas: \(theater.tvCommands - tvBefore) (esperado 0)")

        // 3. Outside a key event (what a touch does), the same commands go through.
        GuardedApplication.testHook = nil
        check(!GuardedApplication.cameFromKeyboard, "fora de evento de tecla: cameFromKeyboard é falso")
        acceptedBefore = ps5.acceptedCommands; tvBefore = theater.tvCommands
        attemptEverything()
        check(ps5.acceptedCommands > acceptedBefore, "toque: comandos do PS5 aceitos: \(ps5.acceptedCommands - acceptedBefore)")
        check(theater.tvCommands > tvBefore, "toque: comandos da TV aceitos: \(theater.tvCommands - tvBefore)")
        finish()
    }
}
