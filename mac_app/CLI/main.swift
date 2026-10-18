import Foundation

// ps5ctl: Fase 1 proof CLI. Same engine the Mac app will use; blocking calls are fine here.

/// Set by --ds4. The app itself always announces a DualSense, like the official client.
nonisolated(unsafe) var announceAsDualSense = true

@main
struct PS5Ctl {
    static let usage = """
    ps5ctl: controle do PS5 pela rede (Uso remoto, só controle)

    Uso: ps5ctl [-v] [--host IP] COMANDO [opções]

    Comandos
      discover [--timeout S] [--no-direct]
                                        Procura consoles na rede (padrão 2 s). --no-direct ignora o endereço salvo
      status                            Estado do console pareado (ligado, repouso, app aberto)
      account-id [--url URL | --code C] ID da conta PSN: abre o login da Sony e converte o código
      pair --pin 12345678 [--account-id B64]
                                        Pareia com o código de "Emparelhar dispositivo" do PS5
      wake                              Acorda o console do repouso e espera ele responder
      press BOTÃO [--hold MS]           Toca um botão (padrão 80 ms)
      hold BOTÃO MS                     Segura um botão por MS milissegundos
      home                              Testa o comando "ir para o início" da biblioteca
      standby                           Coloca o console em repouso
      bench [--rounds N]                Mede tempo de conexão e intervalo mínimo entre sessões
      script [--out DIR] PASSO...       Roda uma sequência numa sessão com vídeo e salva capturas da tela
                                        do PS5 (precisa do ffmpeg). Passos: "wait 1.5", "shot nome",
                                        "press right [ms]", "hold circle 600", "home", "stick x y",
                                        "stickoff". Só para testes.
      set-login-pin 1234                Guarda o PIN de login do usuário do PS5 (se houver)
      forget                            Apaga o pareamento salvo

    Opção global --ds4: anuncia o cliente como DualShock 4 em vez de DualSense (para comparar).
    Opção global --no-broadcast: descoberta como a do iPhone, sem broadcast: pergunta ao endereço salvo e, se
    ele ficar em silêncio por 1 s, a cada endereço da sub-rede, um por um.

    Botões: cross(x, ok) circle(o, back) square triangle up down left right
            l1 r1 l2 r2 l3 r3 options create(share) touchpad ps(home)
    Arquivo: ~/.config/ps5_remote_control/host.json
    """

    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        var verbose = false
        var hostOverride: String?
        var positional: [String] = []
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "-v" || arg == "--verbose" {
                verbose = true
            } else if arg == "--ds4" {
                announceAsDualSense = false
            } else if arg == "--no-broadcast" {
                PSDiscovery.policy = PSDiscoveryPolicy(broadcast: false, sweepAfter: 1.0)
            } else if arg == "--host", index + 1 < args.count {
                hostOverride = args[index + 1]
                index += 1
            } else if arg == "-h" || arg == "--help" {
                print(usage)
                return
            } else {
                positional.append(arg)
            }
            index += 1
        }
        args = positional
        guard let command = args.first else {
            print(usage)
            exit(2)
        }
        let options = Array(args.dropFirst())
        let log = ChiakiLogger(verbose: verbose)
        ChiakiCore.ensureInitialized()

        do {
            switch command {
            case "discover": try discover(options, log: log)
            case "status": try status(hostOverride: hostOverride, log: log)
            case "account-id": try await accountID(options)
            case "pair": try await pair(options, hostOverride: hostOverride, log: log)
            case "wake": try wake(hostOverride: hostOverride, log: log)
            case "press": try press(options, hostOverride: hostOverride, log: log)
            case "hold": try hold(options, hostOverride: hostOverride, log: log)
            case "home": try home(hostOverride: hostOverride, log: log)
            case "standby": try standby(hostOverride: hostOverride, log: log)
            case "bench": try bench(options, hostOverride: hostOverride, log: log)
            case "script": try script(options, hostOverride: hostOverride, log: log)
            case "set-login-pin": try setLoginPin(options)
            case "forget":
                PSHost.forget()
                print("Pareamento apagado.")
            default:
                print("Comando desconhecido: \(command)\n")
                print(usage)
                exit(2)
            }
        } catch {
            fail("\(error)")
        }
    }

    // MARK: - Commands

    static func discover(_ options: [String], log: ChiakiLogger) throws {
        let timeout = TimeInterval(value(of: "--timeout", in: options) ?? "2") ?? 2
        let saved = options.contains("--no-direct") ? nil : PSHost.load()
        print("Procurando consoles (\(formatSeconds(timeout)))...")
        let hosts = try PSDiscovery.scan(timeout: timeout, directHost: saved?.lastAddress, log: log)
        if hosts.isEmpty {
            print("Nenhum console respondeu. O PS5 está ligado (ou em repouso com a rede ativa) e na mesma rede?")
            return
        }
        for host in hosts {
            print(describe(host))
            print("  respondeu \(formatSeconds(host.answeredAfter)) depois da primeira sondagem")
        }
    }

    static func status(hostOverride: String?, log: ChiakiLogger) throws {
        var saved = try requireHost()
        guard let found = try PSDiscovery.find(hostID: saved.hostID, lastAddress: hostOverride ?? saved.lastAddress, timeout: 1.5, log: log) else {
            print("\(saved.nickname): sem resposta (desligado, fora da rede ou repouso sem rede)")
            return
        }
        print(describe(found))
        if found.address != saved.lastAddress {
            saved.lastAddress = found.address
            try saved.save()
            print("Endereço atualizado em host.json: \(found.address)")
        }
    }

    static func accountID(_ options: [String]) async throws {
        var code = value(of: "--code", in: options)
        if code == nil, let url = value(of: "--url", in: options) {
            code = PSNAccountID.code(fromRedirectURL: url)
            guard code != nil else { throw PSNAccountID.Failure.noCode }
        }
        if code == nil {
            print("""
            1. O navegador vai abrir o login da Sony: entre com a conta PSN usada no PS5.
               Se não abrir, use este endereço:

            \(PSNAccountID.loginURL.absoluteString)

            2. Depois do login a página fica em branco ou dá erro; isso é esperado.
               Copie a URL inteira da barra de endereços (ela contém "code=") e cole aqui.

            """)
            let opener = Process()
            opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            opener.arguments = [PSNAccountID.loginURL.absoluteString]
            try? opener.run()
            print("URL: ", terminator: "")
            guard let line = readLine(), let parsed = PSNAccountID.code(fromRedirectURL: line) else {
                throw PSNAccountID.Failure.noCode
            }
            code = parsed
        }
        print("Trocando o código pelo ID da conta...")
        let id = try await PSNAccountID.fetchAccountID(code: code!)
        print("ID da conta PSN (base64): \(id)")
        print("Use: ps5ctl pair --pin 12345678 --account-id \(id)")
    }

    static func pair(_ options: [String], hostOverride: String?, log: ChiakiLogger) async throws {
        guard let pinText = value(of: "--pin", in: options), pinText.count == 8, let pin = UInt32(pinText) else {
            throw ChiakiError.failed("informe --pin com os 8 dígitos de Configurações › Sistema › Uso remoto › Emparelhar dispositivo")
        }
        guard let accountText = (value(of: "--account-id", in: options) ?? PSHost.load()?.accountID)?
                .trimmingCharacters(in: .whitespacesAndNewlines) else {
            print("Sem --account-id: obtendo o ID da conta PSN primeiro.")
            try await Self.accountID(options)
            throw ChiakiError.failed("agora repita o pair com --account-id")
        }
        guard PSNAccountID.decode(accountText) != nil else {
            throw ChiakiError.failed("ID da conta inválido: esperado base64 de 8 bytes")
        }

        print("Procurando o PS5...")
        let found = try PSDiscovery.find(hostID: nil, lastAddress: hostOverride, timeout: 2, log: log)
        let address = hostOverride ?? found?.address
        guard let address else {
            throw ChiakiError.failed("nenhum PS5 respondeu; ligue o console ou passe --host IP")
        }
        if let found { print("Console: \(describe(found))") }
        if found?.state == .standby {
            throw ChiakiError.failed("o PS5 está em repouso; ligue-o para parear")
        }

        print("Pareando com \(address) (PIN \(pinText))...")
        let started = Date()
        var host = try PSRegistration.pair(address: address, pin: pin, accountID: accountText,
                                           hostID: found?.hostID, systemVersion: found?.systemVersion, log: log)
        if let previous = PSHost.load(), previous.hostID == host.hostID { host.consolePin = previous.consolePin }
        try host.save()
        print(String(format: "Pareado em %.1f s.", Date().timeIntervalSince(started)))
        print("  Console:   \(host.nickname) (\(host.mac))")
        print("  RegistKey: \(host.registKey)")
        print("  Salvo em:  \(PSHost.fileURL.path)")
        print("Teste: ps5ctl press down")
    }

    static func wake(hostOverride: String?, log: ChiakiLogger) throws {
        let host = try requireHost()
        let address = hostOverride ?? host.lastAddress
        let before = try PSDiscovery.find(hostID: host.hostID, lastAddress: address, timeout: 1.5, log: log)
        if before?.state == .ready {
            print("\(host.nickname) já está ligado.")
            return
        }
        print("Acordando \(host.nickname) em \(address)...")
        try PSWake.wake(address: address, host: host, log: log)
        let started = Date()
        var lastSent = started
        var packets = 1
        while Date().timeIntervalSince(started) < 60 {
            if let now = try PSDiscovery.find(hostID: host.hostID, lastAddress: address, timeout: 1.5, log: log), now.state == .ready {
                print(String(format: "Ligado após %.1f s (%d pacote(s) de wake).", Date().timeIntervalSince(started), packets))
                return
            }
            // A single packet can be lost: send it again every 4 s while waiting.
            if Date().timeIntervalSince(lastSent) >= 4 {
                try PSWake.wake(address: address, host: host, log: log)
                lastSent = Date()
                packets += 1
            }
        }
        print("O console não respondeu como ligado em 60 s. Em repouso, 'Continuar conectado à Internet' e 'Habilitar opção de ligar o PS5 a partir da rede' precisam estar ativos.")
    }

    static func press(_ options: [String], hostOverride: String?, log: ChiakiLogger) throws {
        guard let name = options.first, let button = PSButton.parse(name) else {
            throw ChiakiError.failed("botão inválido; veja a lista em ps5ctl --help")
        }
        let holdMs = Int(value(of: "--hold", in: options) ?? "80") ?? 80
        let runner = try connect(hostOverride: hostOverride, log: log)
        try runner.tap(button, holdMs: holdMs)
        print("\(button.rawValue): enviado (\(holdMs) ms).")
        runner.disconnect()
    }

    static func hold(_ options: [String], hostOverride: String?, log: ChiakiLogger) throws {
        guard options.count >= 2, let button = PSButton.parse(options[0]), let ms = Int(options[1]) else {
            throw ChiakiError.failed("uso: ps5ctl hold BOTÃO MS")
        }
        let runner = try connect(hostOverride: hostOverride, log: log)
        try runner.tap(button, holdMs: ms)
        print("\(button.rawValue): segurado por \(ms) ms.")
        runner.disconnect()
    }

    static func home(hostOverride: String?, log: ChiakiLogger) throws {
        let runner = try connect(hostOverride: hostOverride, log: log)
        try runner.session.goHome()
        Thread.sleep(forTimeInterval: 1.0)
        print("Comando 'ir para o início' enviado. A TV foi para a tela inicial? Se não, o app usa PS segurado.")
        runner.disconnect()
    }

    static func standby(hostOverride: String?, log: ChiakiLogger) throws {
        let runner = try connect(hostOverride: hostOverride, log: log)
        try runner.session.gotoBed()
        let ended = runner.waitForQuit(timeout: 5)
        print(ended ? "Console indo para o repouso." : "Comando de repouso enviado (a sessão ainda não fechou).")
        runner.disconnect()
    }

    static func bench(_ options: [String], hostOverride: String?, log: ChiakiLogger) throws {
        let rounds = max(1, Int(value(of: "--rounds", in: options) ?? "2") ?? 2)
        print("Medindo tempo de conexão e intervalo mínimo entre sessões (\(rounds) rodadas)...")
        var lastClosed: Date?
        for round in 1...rounds {
            let runner = try connectWithRetry(hostOverride: hostOverride, log: log, since: lastClosed, label: "[\(round)]")
            Thread.sleep(forTimeInterval: 1.0)
            runner.disconnect()
            lastClosed = Date()
        }
    }

    /// Retries every 2 s while the console still reports the previous session as in use, and prints
    /// how long after the previous close it finally accepted the new one.
    static func connectWithRetry(hostOverride: String?, log: ChiakiLogger, since: Date?, label: String) throws -> SessionRunner {
        var attempt = 0
        while true {
            attempt += 1
            let attemptStart = Date()
            let elapsed = since.map { String(format: "%.1f s após fechar a anterior", attemptStart.timeIntervalSince($0)) } ?? "primeira sessão"
            do {
                let runner = try connect(hostOverride: hostOverride, log: log, timeout: 12)
                print(String(format: "  %@ conectou em %.2f s · tentativa %d · %@", label, runner.connectSeconds, attempt, elapsed))
                return runner
            } catch {
                print("  \(label) recusada (\(error)) · tentativa \(attempt) · \(elapsed)")
                if attempt >= 12 { throw error }
                Thread.sleep(forTimeInterval: 2)
            }
        }
    }

    /// Test harness: one session with video, a scripted sequence, and screenshots of the console's
    /// screen taken at the "shot" steps. Everything stays on this Mac; nothing is uploaded.
    static func script(_ options: [String], hostOverride: String?, log: ChiakiLogger) throws {
        var steps: [String] = []
        var outDir = FileManager.default.currentDirectoryPath + "/ps5-shots"
        var index = 0
        while index < options.count {
            if options[index] == "--out", index + 1 < options.count {
                outDir = options[index + 1]
                index += 2
            } else {
                steps.append(options[index])
                index += 1
            }
        }
        guard !steps.isEmpty else {
            throw ChiakiError.failed("uso: ps5ctl script [--out DIR] \"wait 1\" \"shot antes\" \"press right\" \"shot depois\"")
        }
        let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let ffmpeg else { throw ChiakiError.failed("o comando script precisa do ffmpeg (brew install ffmpeg)") }
        let directory = URL(fileURLWithPath: outDir)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let recorder = FrameRecorder()
        let runner = try connect(hostOverride: hostOverride, log: log, recorder: recorder)
        print("Sessão aberta (\(announceAsDualSense ? "DualSense" : "DualShock 4")). Esperando o vídeo...")
        let videoDeadline = Date().addingTimeInterval(6)
        while recorder.count < 5, Date() < videoDeadline { Thread.sleep(forTimeInterval: 0.1) }
        print("  \(recorder.count) quadros recebidos.")

        var pad = PadState.idle
        var shots: [(name: String, frame: Int)] = []
        for step in steps {
            let words = step.split(separator: " ").map(String.init)
            guard let verb = words.first else { continue }
            print("  > \(step)")
            switch verb {
            case "wait":
                Thread.sleep(forTimeInterval: Double(words.dropFirst().first ?? "1") ?? 1)
            case "press", "hold":
                guard words.count >= 2, let button = PSButton.parse(words[1]) else {
                    throw ChiakiError.failed("passo inválido: \(step)")
                }
                let defaultMs = verb == "hold" ? 600 : 80
                let ms = words.count > 2 ? (Int(words[2]) ?? defaultMs) : defaultMs
                try runner.tap(button, holdMs: ms)
            case "home":
                try runner.tap(.ps, holdMs: 1500)
            case "stick":
                guard words.count >= 3, let x = Double(words[1]), let y = Double(words[2]) else {
                    throw ChiakiError.failed("passo inválido: \(step)")
                }
                pad.setLeftStick(x: PadState.axis(x), y: PadState.axis(y))
                try runner.session.send(pad)
            case "stickoff":
                pad.setLeftStick(x: 0, y: 0)
                try runner.session.send(pad)
            case "shot":
                guard words.count >= 2 else { throw ChiakiError.failed("passo inválido: \(step)") }
                Thread.sleep(forTimeInterval: 0.5)   // let the screen settle and the frame arrive
                shots.append((words[1], max(0, recorder.count - 1)))
            default:
                throw ChiakiError.failed("passo desconhecido: \(step)")
            }
        }
        Thread.sleep(forTimeInterval: 0.3)
        runner.disconnect()

        let stream = directory.appendingPathComponent("stream.h264")
        try recorder.write(to: stream)
        let frames = directory.appendingPathComponent("frames")
        try? FileManager.default.removeItem(at: frames)
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        let decode = Process()
        decode.executableURL = URL(fileURLWithPath: ffmpeg)
        decode.arguments = ["-loglevel", "error", "-y", "-f", "h264", "-i", stream.path, "-fps_mode", "passthrough",
                            "-q:v", "2", frames.appendingPathComponent("f_%05d.jpg").path]
        try decode.run()
        decode.waitUntilExit()

        let produced = ((try? FileManager.default.contentsOfDirectory(atPath: frames.path)) ?? []).filter { $0.hasSuffix(".jpg") }.sorted()
        print("\(recorder.count) quadros gravados, \(produced.count) decodificados.")
        guard !produced.isEmpty else { throw ChiakiError.failed("o ffmpeg não decodificou nenhum quadro") }
        for shot in shots {
            let pick = produced[min(shot.frame, produced.count - 1)]
            let target = directory.appendingPathComponent("\(shot.name).jpg")
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: frames.appendingPathComponent(pick), to: target)
            print("  \(shot.name): \(target.path) (quadro \(min(shot.frame, produced.count - 1)))")
        }
        try? FileManager.default.removeItem(at: frames)
    }

    static func setLoginPin(_ options: [String]) throws {
        guard let pin = options.first, pin.count == 4, Int(pin) != nil else {
            throw ChiakiError.failed("uso: ps5ctl set-login-pin 1234")
        }
        var host = try requireHost()
        host.consolePin = pin
        try host.save()
        print("PIN de login guardado.")
    }

    // MARK: - Helpers

    /// Opens a session. Right after a previous session closes, the console answers "already in use"
    /// for 6 to 8 s (measured 18/10/2026), so this retries once a second for up to 12 s.
    static func connect(hostOverride: String?, log: ChiakiLogger, timeout: TimeInterval = 15,
                        recorder: FrameRecorder? = nil) throws -> SessionRunner {
        let host = try requireHost()
        var attempt = 0
        while true {
            attempt += 1
            let runner = try SessionRunner(host: host, address: hostOverride, log: log,
                                           dualSense: announceAsDualSense, recorder: recorder)
            do {
                try runner.connect(timeout: timeout)
                return runner
            } catch let error as ChiakiError {
                guard attempt < 12, "\(error)".contains("already in use") else { throw error }
                if attempt == 1 { FileHandle.standardError.write(Data("[sessão] console ainda liberando a sessão anterior; tentando de novo...\n".utf8)) }
                Thread.sleep(forTimeInterval: 1.0)
            }
        }
    }

    static func requireHost() throws -> PSHost {
        guard let host = PSHost.load() else {
            throw ChiakiError.failed("nenhum console pareado; rode 'ps5ctl pair --pin ...' primeiro")
        }
        return host
    }

    static func value(of flag: String, in options: [String]) -> String? {
        guard let index = options.firstIndex(of: flag), index + 1 < options.count else { return nil }
        return options[index + 1]
    }

    static func describe(_ host: PSDiscoveredHost) -> String {
        var parts = ["\(host.hostName ?? "?") (\(host.hostType ?? "?")) em \(host.address)"]
        switch host.state {
        case .ready: parts.append("ligado")
        case .standby: parts.append("em repouso")
        case .unknown: parts.append("estado desconhecido")
        }
        if let version = host.systemVersionText { parts.append("sistema \(version)") }
        if let id = host.hostID { parts.append("id \(id)") }
        if let app = host.runningAppName { parts.append("app: \(app)\(host.runningAppTitleID.map { " [\($0)]" } ?? "")") }
        return parts.joined(separator: " · ")
    }

    static func formatSeconds(_ seconds: TimeInterval) -> String {
        seconds == seconds.rounded() ? "\(Int(seconds)) s" : String(format: "%.1f s", seconds)
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("Erro: \(message)\n".utf8))
        exit(1)
    }
}

/// Collects the raw H.264 samples of a session (codec header first, then one sample per frame).
final class FrameRecorder {
    private let lock = NSLock()
    private var stream = Data()
    private var samples = 0

    func add(_ sample: Data) {
        lock.lock()
        stream.append(sample)
        samples += 1
        lock.unlock()
    }

    /// Frames received so far, not counting the codec header.
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return max(0, samples - 1)
    }

    func write(to url: URL) throws {
        lock.lock()
        let copy = stream
        lock.unlock()
        try copy.write(to: url)
    }
}

/// Blocking wrapper around PSSession for the CLI: connect, tap buttons, wait for quit.
final class SessionRunner {
    let session: PSSession
    private let host: PSHost
    private let connected = DispatchSemaphore(value: 0)
    private let quitSignal = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var quitMessage: String?
    private var isConnected = false
    private var screenBlocked = false
    private(set) var connectSeconds: TimeInterval = 0

    /// The console reported content that can't be streamed (a video app in front).
    var contentBlocked: Bool {
        lock.lock(); defer { lock.unlock() }
        return screenBlocked
    }

    init(host: PSHost, address: String?, log: ChiakiLogger, dualSense: Bool = true, recorder: FrameRecorder? = nil) throws {
        self.host = host
        session = try PSSession(host: host, address: address, log: log, dualSense: dualSense,
                                videoSink: recorder.map { recorder in { recorder.add($0) } })
        session.onEvent = { [weak self] event in self?.handle(event) }
    }

    func connect(timeout: TimeInterval) throws {
        let started = Date()
        try session.start()
        guard connected.wait(timeout: .now() + timeout) == .success else {
            session.stop()
            throw ChiakiError.timeout("conexão com o PS5")
        }
        lock.lock()
        let failure = quitMessage
        lock.unlock()
        if let failure {
            session.stop()
            throw ChiakiError.failed("sessão encerrada: \(failure)")
        }
        connectSeconds = Date().timeIntervalSince(started)
    }

    /// Press, hold, release. Leaves time for the release to go out before the caller disconnects.
    func tap(_ button: PSButton, holdMs: Int) throws {
        try session.send(PadState.idle.pressing(button))
        Thread.sleep(forTimeInterval: Double(holdMs) / 1000)
        try session.send(PadState.idle)
        Thread.sleep(forTimeInterval: 0.25)
    }

    func waitForQuit(timeout: TimeInterval) -> Bool {
        quitSignal.wait(timeout: .now() + timeout) == .success
    }

    func disconnect() {
        session.stop()
    }

    private func handle(_ event: PSSession.Event) {
        switch event {
        case .connected:
            lock.lock(); isConnected = true; lock.unlock()
            connected.signal()
        case .loginPinRequest(let incorrect):
            if let pin = host.consolePin, !incorrect {
                try? session.setLoginPin(pin)
            } else {
                lock.lock()
                quitMessage = incorrect ? "PIN de login recusado; corrija com 'ps5ctl set-login-pin'"
                                        : "o PS5 pede o PIN de login do usuário; guarde-o com 'ps5ctl set-login-pin 1234'"
                lock.unlock()
                connected.signal()
            }
        case .nickname(let name):
            FileHandle.standardError.write(Data("[sessão] console: \(name)\n".utf8))
        case .cantDisplay(let blocked):
            lock.lock(); screenBlocked = blocked; lock.unlock()
            FileHandle.standardError.write(Data("[sessão] o PS5 diz que a tela \(blocked ? "NÃO pode" : "pode") ser transmitida\n".utf8))
        case .quit(_, let text, let detail, let isError):
            lock.lock()
            if quitMessage == nil { quitMessage = detail.map { "\(text) (\($0))" } ?? text }
            let wasConnected = isConnected
            lock.unlock()
            if isError || !wasConnected {
                FileHandle.standardError.write(Data("[sessão] encerrada: \(text)\(detail.map { " (\($0))" } ?? "")\n".utf8))
            }
            quitSignal.signal()
            connected.signal()
        case .other:
            break
        }
    }
}
