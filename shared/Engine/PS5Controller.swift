import Foundation
import Combine

/// What the UI asks the pad to do.
enum PadAction: Equatable {
    case tap(PSButton)
    case hold(PSButton, milliseconds: Int)
    case press(PSButton)
    case release(PSButton)
    case leftStick(Int16, Int16)
    case rightStick(Int16, Int16)
    case trigger(PSButton, UInt8)

    var isTap: Bool {
        switch self {
        case .tap, .hold: return true
        default: return false
        }
    }
}

struct SessionQuit: Error, CustomStringConvertible {
    let reason: ChiakiQuitReason
    let text: String
    let detail: String?

    var inUse: Bool { reason == CHIAKI_QUIT_REASON_SESSION_REQUEST_RP_IN_USE }
    var description: String { detail.map { "\(text) (\($0))" } ?? text }
}

/// The app's model: finds the console, opens sessions on demand, applies the connection policy
/// (connect on the first command, let go while you watch) and exposes state for SwiftUI.
@MainActor
final class PS5Controller: ObservableObject {
    enum Link: Equatable {
        case noHost
        case unknown
        case offline
        case standby
        case ready
        case waking
        case cooldown(until: Date)
        case connecting
        case connected
        case inUse
    }

    struct Policy: Codable, Equatable {
        var idleSeconds: Double = 30           // outside known video apps
        var afterCrossSeconds: Double = 6      // outside known video apps, after ✕: the console doesn't say
                                               // when a video app opens mid-session, and ✕ is usually play
        var videoIdleSeconds: Double = 20      // in a video app, after any command but ✕
        var videoAfterPlaySeconds: Double = 5  // in a video app, after ✕ (probably play)
        var minimumGapSeconds: Double = 8      // measured: refused at 6 s, accepted at 8 s
        var tapMilliseconds: Int = 80
    }

    @Published private(set) var host: PSHost?
    @Published private(set) var console: PSDiscoveredHost?
    @Published private(set) var link: Link = .unknown
    @Published private(set) var lastError: String?
    @Published private(set) var pressed: Set<PSButton> = []
    @Published private(set) var logLines: [String] = []
    @Published private(set) var needsLoginPin = false
    /// The console said what it is showing can't be streamed: a video app is in front, and while a
    /// session is open the picture on the TV is blacked out.
    @Published private(set) var videoBlocked = false
    @Published var watching: Bool { didSet { defaults.set(watching, forKey: "watching") } }
    @Published var cecEnabled: Bool { didSet { defaults.set(cecEnabled, forKey: "cecEnabled") } }
    @Published var verboseLog: Bool {
        didSet {
            defaults.set(verboseLog, forKey: "verboseLog")
            log.setLevel(verbose: verboseLog)
        }
    }
    @Published var policy: Policy {
        didSet { if let data = try? JSONEncoder().encode(policy) { defaults.set(data, forKey: "policy") } }
    }

    /// Asked before every command that comes from the UI. The app sets it to refuse anything that was
    /// started by a key event: the remote is mouse-only (see InputGuard). Defaults to "allow" so the
    /// CLI, which has no UI, is unaffected.
    var inputGate: @MainActor () -> Bool = { true }
    /// Self-test only: count accepted commands without touching the console.
    var dryRun = false
    private(set) var acceptedCommands = 0
    /// Self-test only: idle time before letting the session go, without touching the saved policy.
    var idleOverride: Double?

    let log: ChiakiLogger
    private let defaults = UserDefaults.standard
    private var session: PSSession?
    private var pad = PadState()
    private var queue: [PadAction] = []
    private var disconnectAfterFlush = false
    private var idleTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var discoveryTask: Task<Void, Never>?
    private var sendChain: Task<Void, Never>?
    private var connectContinuation: CheckedContinuation<Result<Void, Error>, Never>?
    private var lastDisconnect: Date?
    /// iOS: the app is out of the foreground. No session may open and nothing is polled until `resume()`.
    private var suspended = false

    static let videoAppKeywords = ["netflix", "youtube", "prime video", "disney", "max", "globoplay", "crunchyroll",
                                   "spotify", "apple tv", "plex", "twitch", "paramount", "star+", "hbo", "deezer",
                                   "pluto", "mubi", "vix", "mercado play", "claro tv", "directv", "media player"]

    init() {
        ChiakiCore.ensureInitialized()
        let verbose = defaults.bool(forKey: "verboseLog")
        log = ChiakiLogger(verbose: verbose)
        watching = defaults.bool(forKey: "watching")
        cecEnabled = defaults.bool(forKey: "cecEnabled")
        verboseLog = verbose
        if let data = defaults.data(forKey: "policy"), let saved = try? JSONDecoder().decode(Policy.self, from: data) {
            policy = saved
        } else {
            policy = Policy()
        }
        host = PSHost.load()
        link = host == nil ? .noHost : .unknown
        log.sink = { [weak self] level, message in
            let line = "\(level == CHIAKI_LOG_ERROR ? "ERRO " : level == CHIAKI_LOG_WARNING ? "aviso " : "")\(message)"
            if level == CHIAKI_LOG_ERROR || level == CHIAKI_LOG_WARNING { NSLog("chiaki: %@", message) }
            Task { @MainActor [weak self] in self?.appendLog(line) }
        }
        startDiscovery()
    }

    // MARK: - Derived state

    var isPaired: Bool { host != nil }
    var consoleName: String { host?.nickname ?? console?.hostName ?? "PS5" }
    var runningApp: String? { console?.runningAppName }

    /// A streaming app is in front: sessions are let go quickly so the picture comes back.
    var isVideoApp: Bool {
        if watching || videoBlocked { return true }
        guard let app = runningApp?.lowercased() else { return false }
        return Self.videoAppKeywords.contains { app.contains($0) }
    }

    var statusText: String {
        switch link {
        case .noHost: return "não pareado"
        case .unknown: return "procurando o console…"
        case .offline: return "sem resposta (desligado ou fora da rede)"
        case .standby: return "em repouso · um toque acorda"
        case .ready: return "pronto · conecta ao tocar"
        case .waking: return "acordando…"
        case .cooldown(let until): return "pronto em \(max(1, Int(until.timeIntervalSinceNow.rounded(.up)))) s"
        case .connecting: return "conectando…"
        case .connected: return isVideoApp ? "conectado · vídeo escuro na TV até soltar" : "conectado"
        case .inUse: return "em uso por outro dispositivo"
        }
    }

    // MARK: - Pairing

    func adopt(_ newHost: PSHost) {
        var merged = newHost
        if let old = host, old.hostID == newHost.hostID { merged.consolePin = old.consolePin }
        try? merged.save()
        host = merged
        needsLoginPin = false
        lastError = nil
        if link == .noHost { link = .unknown }
    }

    func setLoginPin(_ pin: String?) {
        guard var current = host else { return }
        current.consolePin = pin?.isEmpty == true ? nil : pin
        try? current.save()
        host = current
        needsLoginPin = false
    }

    func forget() {
        guard inputGate() else { return }
        acceptedCommands += 1
        if dryRun { return }   // the self-test must never touch the saved pairing
        Task { await disconnect() }
        PSHost.forget()
        host = nil
        link = .noHost
    }

    // MARK: - Pad input

    func tap(_ button: PSButton) { perform(.tap(button)) }
    func press(_ button: PSButton) { perform(.press(button)) }
    func release(_ button: PSButton) { perform(.release(button)) }
    func setLeftStick(x: Int16, y: Int16) { perform(.leftStick(x, y)) }
    func setRightStick(x: Int16, y: Int16) { perform(.rightStick(x, y)) }
    func setTrigger(_ button: PSButton, _ value: UInt8) { perform(.trigger(button, value)) }

    /// Holding PS takes the console to its home screen. 1 s sits right at the console's threshold and
    /// sometimes counted as a short press in tests; 1.5 s leaves margin for network jitter.
    func home() { perform(.hold(.ps, milliseconds: 1500)) }

    /// "▶ Assistir": ✕ and let the session go right away, so the picture is back in a few seconds.
    func watch() {
        guard inputGate() else { return }
        if dryRun { acceptedCommands += 1; return }
        if link == .connected {
            perform(.tap(.cross))
            enqueueSend { [weak self] in await self?.disconnect() }
        } else {
            disconnectAfterFlush = true
            perform(.tap(.cross))
        }
    }

    func perform(_ action: PadAction) {
        guard inputGate() else { return }
        acceptedCommands += 1
        guard host != nil, !dryRun, !suspended else { return }
        if link == .connected, session != nil {
            apply(action)
            scheduleIdle(afterCross: action == .tap(.cross))
            return
        }
        // Not connected: keep the first tap (a repeat is impatience), turn holds into taps, drop stick moves.
        switch action {
        case .tap, .hold:
            if !queue.contains(where: { $0.isTap }) { queue.append(action) }
        case .press(let button):
            if !queue.contains(where: { $0.isTap }) { queue.append(.tap(button)) }
        case .release, .leftStick, .rightStick, .trigger:
            break
        }
        ensureConnected()
    }

    private func apply(_ action: PadAction) {
        switch action {
        case .tap(let button):
            let ms = policy.tapMilliseconds
            enqueueSend { [weak self] in
                await self?.sendPad { $0.press(button) }
                try? await Task.sleep(for: .milliseconds(ms))
                await self?.sendPad { $0.release(button) }
            }
        case .hold(let button, let ms):
            enqueueSend { [weak self] in
                await self?.sendPad { $0.press(button) }
                try? await Task.sleep(for: .milliseconds(ms))
                await self?.sendPad { $0.release(button) }
            }
        case .press(let button):
            enqueueSend { [weak self] in await self?.sendPad { $0.press(button) } }
        case .release(let button):
            enqueueSend { [weak self] in await self?.sendPad { $0.release(button) } }
        case .leftStick(let x, let y):
            enqueueSend { [weak self] in await self?.sendPad { $0.setLeftStick(x: x, y: y) } }
        case .rightStick(let x, let y):
            enqueueSend { [weak self] in await self?.sendPad { $0.setRightStick(x: x, y: y) } }
        case .trigger(let button, let value):
            enqueueSend { [weak self] in await self?.sendPad { $0.setTrigger(button, value) } }
        }
    }

    /// Serialises pad updates so a tap's press and release never overtake each other.
    private func enqueueSend(_ work: @escaping @MainActor () async -> Void) {
        let previous = sendChain
        sendChain = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    private func sendPad(_ mutate: (inout PadState) -> Void) {
        mutate(&pad)
        pressed = Set(PSButton.allCases.filter { pad.raw.buttons & $0.bit != 0 })
        guard let session else { return }
        do { try session.send(pad) } catch { lastError = "\(error)" }
    }

    // MARK: - Connection policy

    private func ensureConnected() {
        guard connectTask == nil else { return }
        connectTask = Task { [weak self] in
            await self?.connectFlow()
            self?.connectTask = nil
        }
    }

    private func connectFlow() async {
        if console?.state == .standby || link == .standby {
            guard await wakeAndWait() else {
                fail("o PS5 não acordou: em repouso, 'Continuar conectado à Internet' e 'Habilitar opção de ligar o PS5 a partir da rede' precisam estar ativos")
                return
            }
        }
        guard !suspended else { return }
        await waitCooldown()

        var attempt = 0
        while true {
            guard !suspended else { queue.removeAll(); return }
            attempt += 1
            link = .connecting
            switch await openSession() {
            case .success:
                if suspended {   // the app left the foreground while the session was opening
                    queue.removeAll()
                    await disconnect()
                    return
                }
                link = .connected
                lastError = nil
                await flushQueue()
                return
            case .failure(let error):
                if let quit = error as? SessionQuit, quit.inUse, attempt < 10 {
                    // Our own previous session is still being released by the console.
                    link = .inUse
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
                fail("\(error)")
                return
            }
        }
    }

    private func fail(_ message: String) {
        lastError = message
        queue.removeAll()
        disconnectAfterFlush = false
        if console == nil {
            link = .offline
        } else {
            link = console?.state == .standby ? .standby : .ready
        }
    }

    private func waitCooldown() async {
        guard let last = lastDisconnect else { return }
        while true {
            let remaining = policy.minimumGapSeconds - Date().timeIntervalSince(last)
            if remaining <= 0 { return }
            link = .cooldown(until: last.addingTimeInterval(policy.minimumGapSeconds))
            try? await Task.sleep(for: .seconds(min(remaining, 0.25)))
        }
    }

    private func openSession() async -> Result<Void, Error> {
        guard let host else { return .failure(ChiakiError.failed("nenhum console pareado")) }
        let address = console?.address ?? host.lastAddress
        let newSession: PSSession
        do {
            newSession = try PSSession(host: host, address: address, log: log)
        } catch {
            return .failure(error)
        }
        newSession.onEvent = { [weak self, weak newSession] event in
            Task { @MainActor [weak self] in
                guard let self, let newSession else { return }
                self.handle(event, from: newSession)
            }
        }
        session = newSession
        pad = PadState()
        do {
            try newSession.start()
        } catch {
            session = nil
            return .failure(error)
        }
        return await withCheckedContinuation { continuation in
            connectContinuation = continuation
        }
    }

    private func handle(_ event: PSSession.Event, from source: PSSession) {
        guard source === session else { return }
        switch event {
        case .connected:
            connectContinuation?.resume(returning: .success(()))
            connectContinuation = nil
        case .loginPinRequest(let incorrect):
            if let pin = host?.consolePin, !incorrect {
                try? source.setLoginPin(pin)
            } else {
                needsLoginPin = true
                lastError = incorrect ? "o PS5 recusou o PIN de login; corrija em Ajustes"
                                      : "o PS5 pede o PIN de login do usuário; informe em Ajustes"
            }
        case .nickname:
            break
        case .cantDisplay(let blocked):
            videoBlocked = blocked
        case .quit(let reason, let text, let detail, _):
            let quit = SessionQuit(reason: reason, text: text, detail: detail)
            session = nil
            videoBlocked = false
            idleTask?.cancel()
            Task.detached { source.stop() }
            lastDisconnect = Date()
            if let continuation = connectContinuation {
                connectContinuation = nil
                continuation.resume(returning: .failure(quit))
            } else {
                // The console ended a live session (rest mode, another device, network).
                link = console?.state == .standby ? .standby : .ready
                if reason != CHIAKI_QUIT_REASON_STOPPED && reason != CHIAKI_QUIT_REASON_STREAM_CONNECTION_REMOTE_SHUTDOWN {
                    lastError = "sessão encerrada: \(quit)"
                }
            }
        case .other:
            break
        }
    }

    private func flushQueue() async {
        let actions = queue
        queue.removeAll()
        var afterCross = false
        for action in actions {
            apply(action)
            if action == .tap(.cross) { afterCross = true }
        }
        if disconnectAfterFlush {
            disconnectAfterFlush = false
            enqueueSend { [weak self] in await self?.disconnect() }
        } else {
            scheduleIdle(afterCross: afterCross)
        }
    }

    private func scheduleIdle(afterCross: Bool) {
        idleTask?.cancel()
        let seconds: Double
        if let idleOverride {
            seconds = idleOverride
        } else if isVideoApp {
            seconds = afterCross ? policy.videoAfterPlaySeconds : policy.videoIdleSeconds
        } else {
            seconds = afterCross ? policy.afterCrossSeconds : policy.idleSeconds
        }
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.pressed.isEmpty else { return }
            await self.disconnect()
        }
    }

    /// iOS: the app is leaving the foreground (screen locked, another app). Lets the session go cleanly, drops
    /// what was queued and stops polling; the minimum gap counts from now. Nothing comes back by itself:
    /// the next tap opens a session again.
    func suspend() async {
        suspended = true
        discoveryTask?.cancel()
        discoveryTask = nil
        queue.removeAll()
        await disconnect()
    }

    /// iOS: the app is in the foreground again.
    func resume() {
        suspended = false
        if discoveryTask == nil { startDiscovery() }
    }

    /// Ends the session and waits for the library threads. The console then needs the minimum gap
    /// before it accepts a new one.
    func disconnect() async {
        idleTask?.cancel()
        idleTask = nil
        guard let current = session else { return }
        session = nil
        connectContinuation?.resume(returning: .failure(ChiakiError.failed("conexão cancelada")))
        connectContinuation = nil
        link = console?.state == .standby ? .standby : .ready
        await Task.detached { current.stop() }.value
        lastDisconnect = Date()
    }

    // MARK: - Power

    func wake() {
        guard inputGate() else { return }
        acceptedCommands += 1
        if dryRun { return }
        Task { _ = await wakeAndWait() }
    }

    /// Sends the wake packet and waits (up to 60 s) for the console to answer discovery as ready.
    func wakeAndWait() async -> Bool {
        guard let host else { return false }
        link = .waking
        let address = console?.address ?? host.lastAddress
        let log = log
        let sent = await Task.detached { (try? PSWake.wake(address: address, host: host, log: log)) != nil }.value
        guard sent else {
            lastError = "não consegui mandar o pacote de acordar"
            return false
        }
        // One wake packet can be lost, or arrive while the console is still settling into rest mode:
        // send it again every few seconds until the console answers as on.
        let deadline = Date().addingTimeInterval(60)
        var lastSent = Date()
        while Date() < deadline {
            let found = await Task.detached { try? PSDiscovery.find(hostID: host.hostID, lastAddress: address, timeout: 1.0, log: log) }.value
            if let found, found.state == .ready {
                console = found
                link = .ready
                return true
            }
            if Date().timeIntervalSince(lastSent) >= 4 {
                _ = await Task.detached { try? PSWake.wake(address: address, host: host, log: log) }.value
                lastSent = Date()
            }
            try? await Task.sleep(for: .seconds(1))
        }
        link = .standby
        return false
    }

    /// UI entry point for rest mode: the gate is checked right here, inside the event being handled.
    func requestStandby() {
        guard inputGate() else { return }
        acceptedCommands += 1
        if dryRun { return }
        Task { await standby() }
    }

    /// Rest mode. Opens a session if needed; the console closes it on its way to sleep.
    func standby() async {
        if link != .connected {
            queue.removeAll()
            ensureConnected()
            await connectTask?.value
        }
        guard let current = session else { return }
        do { try current.gotoBed() } catch { lastError = "\(error)"; return }
        try? await Task.sleep(for: .seconds(3))
        await disconnect()
        link = .standby
    }

    // MARK: - Discovery

    private func startDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let host = self.host
                let log = self.log
                let found = await Task.detached {
                    try? PSDiscovery.find(hostID: host?.hostID, lastAddress: host?.lastAddress, timeout: 1.2, log: log)
                }.value
                self.applyDiscovery(found)
                try? await Task.sleep(for: .seconds(found == nil ? 3 : 2.5))
            }
        }
    }

    private func applyDiscovery(_ found: PSDiscoveredHost?) {
        if found?.state != console?.state || (found == nil) != (console == nil) {
            NSLog("discovery: %@", found.map { "\($0.hostName ?? "?") \($0.address) \($0.state.rawValue)" } ?? "sem resposta")
        }
        console = found
        if var current = host, let found, found.address != current.lastAddress {
            current.lastAddress = found.address
            if let version = found.systemVersion { current.systemVersion = version }
            try? current.save()
            host = current
        }
        switch link {
        case .unknown, .offline, .standby, .ready:
            if host == nil { link = .noHost; return }
            guard let found else { link = .offline; return }
            link = found.state == .standby ? .standby : .ready
        default:
            break
        }
    }

    // MARK: - Log

    private func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > 400 { logLines.removeFirst(logLines.count - 400) }
    }

    func clearError() { lastError = nil }
}
