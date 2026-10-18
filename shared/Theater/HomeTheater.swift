import Foundation
import Combine

/// Ties the PS5 to the LG TV (code shared with "Controle Remoto LG"): one button turns both on
/// or off, and, when enabled, some keys travel through the TV's SIMPLINK instead of a session.
/// Every command entry point asks the PS5 controller's input gate first, so a command started by a
/// key event is refused (the remote is mouse-only; see InputGuard).
@MainActor
final class HomeTheater: ObservableObject {
    let ps5: PS5Controller
    let tv: LGTVClient
    @Published private(set) var step: String = ""
    @Published private(set) var busy = false
    /// Commands that reached the TV side through the gate. The self-test reads it.
    private(set) var tvCommands = 0
    /// Self-test only: count commands without sending them.
    var dryRun = false

    init(ps5: PS5Controller, tv: LGTVClient) {
        self.ps5 = ps5
        self.tv = tv
    }

    /// The TV app has been configured on this Mac (its config.json exists).
    var tvConfigured: Bool { LGTVClient.loadConfigFromDisk() != nil }

    /// Volume, mute and the like, straight to the TV.
    func tvKey(_ key: TVKey) {
        guard ps5.inputGate() else { return }
        tvCommands += 1
        if dryRun { return }
        tv.sendKey(key)
    }

    /// Wakes the PS5 and expects the TV to come on by HDMI-CEC (One-Touch Play). If the TV stays
    /// silent, falls back to the TV Box route the TV app already uses.
    func turnOnAll() {
        guard ps5.inputGate() else { return }
        tvCommands += 1
        if dryRun { return }
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false; step = "" }
            step = "Acordando o PS5…"
            let awake = await ps5.wakeAndWait()
            if !awake { step = "O PS5 não respondeu; tentando a TV mesmo assim…" }
            step = "Esperando a TV ligar pelo HDMI…"
            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline, tv.powerState != .on {
                try? await Task.sleep(for: .seconds(2))
                await tv.refreshStatus()
            }
            if tv.powerState != .on, tv.canTurnOnTV {
                step = "A TV não ligou pelo HDMI; usando a TV Box…"
                tv.turnOn()
                let boxDeadline = Date().addingTimeInterval(95)
                while Date() < boxDeadline, tv.powerState != .on {
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }

    /// PS5 to rest mode, then the TV off.
    func turnOffAll() {
        guard ps5.inputGate() else { return }
        tvCommands += 1
        if dryRun { return }
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false; step = "" }
            step = "Colocando o PS5 em repouso…"
            await ps5.standby()
            step = "Desligando a TV…"
            tv.sendKey(.power)
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Keys the TV can forward to the PS5 over SIMPLINK (HDMI-CEC), if the Fase 0 test confirms it.
    static func tvKey(for button: PSButton) -> TVKey? {
        switch button {
        case .cross: return .ok
        case .circle: return .back
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        default: return nil
        }
    }

    /// The CEC route applies while a video plays and no session is open: the TV forwards the key
    /// (no session, no blackout). Everything else goes through the Remote Play session.
    private func routesThroughTV(_ button: PSButton) -> Bool {
        ps5.cecEnabled && ps5.isVideoApp && ps5.link != .connected && tv.powerState == .on
            && HomeTheater.tvKey(for: button) != nil
    }

    func tap(_ button: PSButton) {
        if routesThroughTV(button), let key = HomeTheater.tvKey(for: button) {
            tvKey(key)
            return
        }
        ps5.tap(button)
    }

    /// How a click on a pad key reaches the console.
    enum ClickMode {
        case tap        // one fixed-length tap per click, whatever the click lasts
        case repeating  // a tap now, and more while the mouse stays down (like the console's own auto-repeat)
        case hold       // press on mouse down, release on mouse up (analog triggers)
    }

    /// Fixed-length taps are what the console handles reliably: in tests, taps of 80 ms never failed,
    /// while mirroring a longer click sometimes lost the press. Only the triggers keep a real hold.
    static func clickMode(for button: PSButton) -> ClickMode {
        switch button {
        case .up, .down, .left, .right: return .repeating
        case .l2, .r2: return .hold
        default: return .tap
        }
    }

    static let repeatDelay: Duration = .milliseconds(400)
    static let repeatInterval: Duration = .milliseconds(160)
    private var repeatTask: Task<Void, Never>?

    /// Mouse down. On the TV route the key is sent on release, as a tap.
    func keyDown(_ button: PSButton) {
        if routesThroughTV(button) { return }
        switch HomeTheater.clickMode(for: button) {
        case .tap:
            ps5.tap(button)
        case .hold:
            ps5.press(button)
        case .repeating:
            ps5.tap(button)
            repeatTask?.cancel()
            repeatTask = Task { [weak self] in
                try? await Task.sleep(for: HomeTheater.repeatDelay)
                while !Task.isCancelled {
                    self?.ps5.tap(button)
                    try? await Task.sleep(for: HomeTheater.repeatInterval)
                }
            }
        }
    }

    /// Mouse up.
    func keyUp(_ button: PSButton) {
        if routesThroughTV(button), let key = HomeTheater.tvKey(for: button) {
            tvKey(key)
            return
        }
        switch HomeTheater.clickMode(for: button) {
        case .tap:
            break
        case .hold:
            ps5.release(button)
        case .repeating:
            repeatTask?.cancel()
            repeatTask = nil
        }
    }
}
