import AppKit

/// `Controle PS5 --selftest-input` proves, on the app's real event path, that keys never become
/// commands and that the mouse still does. It posts synthetic key and mouse events to this very
/// app, reads the counters, prints a report and exits with 0 (pass) or 1 (fail). The app runs in
/// dry-run mode for this: nothing is sent to the PS5 or to the TV.
@MainActor
enum InputSelfTest {
    static var theater: HomeTheater?
    /// Called by the production key monitor, inside the dispatch of each key event.
    static var keyHook: ((NSEvent) -> Void)?

    private static let keys: [(code: UInt16, chars: String, name: String)] = [
        (126, "\u{F700}", "seta ↑"), (125, "\u{F701}", "seta ↓"), (123, "\u{F702}", "seta ←"), (124, "\u{F703}", "seta →"),
        (36, "\r", "Return"), (76, "\u{3}", "Enter"), (49, " ", "Espaço"), (53, "\u{1B}", "Esc"),
        (51, "\u{7F}", "Delete"), (117, "\u{F728}", "Delete adiante"), (48, "\t", "Tab"),
        (1, "s", "s"), (17, "t", "t"), (4, "h", "h"), (31, "o", "o"), (8, "c", "c"), (35, "p", "p"),
        (33, "[", "["), (30, "]", "]"), (43, ",", ","), (47, ".", "."), (24, "=", "+"), (27, "-", "-"), (46, "m", "m"),
        (18, "1", "1"), (29, "0", "0"),
    ]

    static func run() {
        var report: [String] = []
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            report.append((ok ? "ok     " : "FALHA  ") + what)
            if !ok { failures += 1 }
        }
        func finish() {
            print(report.joined(separator: "\n"))
            print(failures == 0 ? "RESULTADO: passou" : "RESULTADO: \(failures) falha(s)")
            fflush(stdout)
            exit(failures == 0 ? 0 : 1)
        }

        guard let theater,
              let window = NSApp.windows.first(where: { $0.isVisible && $0.sheetParent == nil }) else {
            check(false, "janela principal não encontrada")
            finish()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        let ps5 = theater.ps5
        let pairingFile = PSHost.fileURL.path
        let hadPairing = FileManager.default.fileExists(atPath: pairingFile)
        check(ProcessInfo.processInfo.environment["PS5_CONFIG_DIR"] != nil,
              "autoteste usa PS5_CONFIG_DIR, nunca o pareamento real")

        // What a focused button or a menu item activated from the keyboard would try, inside that event.
        func attemptEverything() {
            ps5.tap(.cross); ps5.press(.circle); ps5.release(.circle)
            ps5.setLeftStick(x: 20000, y: 0); ps5.setTrigger(.l2, 255)
            ps5.home(); ps5.watch(); ps5.wake(); ps5.requestStandby()
            theater.tvKey(.volumeUp); theater.tvKey(.mute); theater.turnOnAll(); theater.turnOffAll()
        }

        // Phase 1: keyboard. Every key must be dropped, and every command attempted while a key event
        // is being dispatched must be refused.
        let swallowedBefore = InputGuard.swallowed
        let acceptedBefore = ps5.acceptedCommands
        let tvBefore = theater.tvCommands
        var keyDispatches = 0
        var seenAsKeyboard = 0
        keyHook = { event in
            guard InputGuard.isKeyboard(event.type) else { return }
            keyDispatches += 1
            if InputGuard.cameFromKeyboard { seenAsKeyboard += 1 }
            attemptEverything()
        }
        for key in keys {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                                                timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: window.windowNumber, context: nil,
                                                characters: key.chars, charactersIgnoringModifiers: key.chars,
                                                isARepeat: false, keyCode: key.code) {
                    NSApp.postEvent(event, atStart: false)
                }
            }
        }

        // Phase 2 (after the keys drain): the same commands from a mouse event must go through.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            keyHook = nil
            let swallowed = InputGuard.swallowed - swallowedBefore
            let expected = keys.count * 2
            check(keyDispatches == expected, "\(keyDispatches) de \(expected) eventos de tecla chegaram ao monitor")
            check(swallowed == expected, "janela descartou \(swallowed) de \(expected) eventos de tecla")
            check(seenAsKeyboard == keyDispatches, "durante cada tecla, o evento corrente era de teclado (\(seenAsKeyboard)/\(keyDispatches))")
            check(ps5.acceptedCommands == acceptedBefore, "comandos do PS5 aceitos durante teclas: \(ps5.acceptedCommands - acceptedBefore) (esperado 0)")
            check(theater.tvCommands == tvBefore, "comandos da TV aceitos durante teclas: \(theater.tvCommands - tvBefore) (esperado 0)")

            // Command shortcuts and typing in sheets are not dropped (window management, form entry).
            if let cmdEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command],
                                               timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil,
                                               characters: "x", charactersIgnoringModifiers: "x",
                                               isARepeat: false, keyCode: 7) {
                check(!InputGuard.shouldSwallow(cmdEvent), "atalhos com Command (sair, fechar, ocultar) continuam livres")
            }

            let acceptedMid = ps5.acceptedCommands
            let tvMid = theater.tvCommands
            var mouseDispatches = 0
            var mouseSeenAsKeyboard = 0
            let mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
                MainActor.assumeIsolated {
                    mouseDispatches += 1
                    if InputGuard.cameFromKeyboard { mouseSeenAsKeyboard += 1 }
                    attemptEverything()
                }
                return nil   // keep the synthetic click away from the real controls
            }
            if let click = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 5, y: 5), modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil,
                                              eventNumber: 1, clickCount: 1, pressure: 1) {
                NSApp.postEvent(click, atStart: false)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
                check(mouseDispatches == 1, "clique sintético chegou ao monitor (\(mouseDispatches))")
                check(mouseSeenAsKeyboard == 0, "durante o clique, o evento corrente não era de teclado")
                check(ps5.acceptedCommands > acceptedMid, "comandos do PS5 aceitos durante o clique: \(ps5.acceptedCommands - acceptedMid)")
                check(theater.tvCommands > tvMid, "comandos da TV aceitos durante o clique: \(theater.tvCommands - tvMid)")
                check(FileManager.default.fileExists(atPath: pairingFile) == hadPairing, "arquivo de pareamento intacto depois do teste")
                finish()
            }
        }
    }
}
