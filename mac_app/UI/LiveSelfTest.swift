import Foundation

/// `Controle PS5 --selftest-live` drives the real console through the app's own connection policy:
/// three PS taps, each after the previous session was let go for inactivity, so every tap goes through
/// "connect on the first command, flush the queued tap" and the last two also through the minimum gap
/// between sessions. The Control Center should end up open (three toggles). Prints the timings and exits.
@MainActor
enum LiveSelfTest {
    static func run(_ ps5: PS5Controller) async {
        func stamp(_ start: Date) -> String { String(format: "%5.1f s", Date().timeIntervalSince(start)) }
        func waitFor(_ timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if condition() { return true }
                try? await Task.sleep(for: .milliseconds(100))
            }
            return condition()
        }
        var failures = 0
        ps5.idleOverride = 4
        let start = Date()
        guard await waitFor(15, { ps5.link == .ready }) else {
            print("FALHA  o console não apareceu como pronto (estado: \(ps5.statusText))")
            exit(1)
        }
        print("\(stamp(start))  console pronto: \(ps5.consoleName)")
        for round in 1...3 {
            let tapAt = Date()
            ps5.tap(.ps)
            var sawCooldown = false
            let connected = await waitFor(25) {
                if case .cooldown = ps5.link { sawCooldown = true }
                return ps5.link == .connected
            }
            if !connected {
                failures += 1
                print("FALHA  toque \(round): não conectou (estado: \(ps5.statusText), erro: \(ps5.lastError ?? "-"))")
                break
            }
            print(String(format: "%@  toque %d: conectado %.1f s depois do toque%@", stamp(start), round,
                         Date().timeIntervalSince(tapAt), sawCooldown ? " (passou pelo intervalo entre sessões)" : ""))
            let released = await waitFor(15) { ps5.link != .connected }
            if !released {
                failures += 1
                print("FALHA  toque \(round): a sessão não foi solta por inatividade")
                break
            }
            print(String(format: "%@  toque %d: sessão solta %.1f s depois do toque (esperado ~4 s de inatividade)",
                         stamp(start), round, Date().timeIntervalSince(tapAt)))
        }
        print(failures == 0 ? "RESULTADO: passou (confira a Central de Controle: deve estar ABERTA)" : "RESULTADO: \(failures) falha(s)")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }
}
