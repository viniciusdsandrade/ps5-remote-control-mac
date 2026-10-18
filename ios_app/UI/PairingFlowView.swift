import SwiftUI

/// Pairing, once: find the console, get the PSN account id, type the 8-digit code. Same steps as the Mac app.
struct PairingFlowView: View {
    @ObservedObject var ps5: PS5Controller
    @Environment(\.dismiss) private var dismiss

    @State private var consoles: [PSDiscoveredHost] = []
    @State private var scanning = false
    @State private var selectedAddress: String?
    @State private var accountID: String?
    @State private var accountInput = ""
    @State private var accountBusy = false
    @State private var showLogin = false
    @State private var pin = ""
    @State private var pairing = false
    @State private var message: String?
    @State private var failed = false
    @State private var scanTask: Task<Void, Never>?

    private var selected: PSDiscoveredHost? { consoles.first { $0.address == selectedAddress } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Uma vez só. O PS5 precisa estar ligado e na mesma rede Wi-Fi, com *Configurações › Sistema › Uso remoto › Ativar o Uso remoto* ligado.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("1. Console") {
                    if consoles.isEmpty {
                        HStack(spacing: 8) {
                            if scanning { ProgressView() }
                            Text(scanning ? "Procurando… se o iOS pedir acesso à Rede Local, permita." : "Nenhum console respondeu.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(consoles, id: \.address) { console in
                        Button {
                            selectedAddress = console.address
                        } label: {
                            HStack {
                                Image(systemName: console.address == selectedAddress ? "largecircle.fill.circle" : "circle")
                                Text("\(console.hostName ?? "?") · \(console.address) · \(console.state == .ready ? "ligado" : console.state == .standby ? "em repouso" : "?")")
                                    .foregroundStyle(.primary)
                            }
                        }
                        .touchOnly()
                    }
                    Button("Procurar de novo") { scan() }.disabled(scanning).touchOnly()
                }
                Section("2. ID da conta PSN") {
                    if let accountID {
                        Label("ID obtido", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(accountID).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Button("Entrar na Sony") { showLogin = true }.disabled(accountBusy).touchOnly()
                    Text("Entre com a conta usada no PS5. Ou cole abaixo o ID, ou a URL em que a página termina.")
                        .font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        TextField("ID ou URL de redirecionamento", text: $accountInput)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Usar") { resolveAccount(accountInput) }
                            .disabled(accountInput.isEmpty || accountBusy).touchOnly()
                    }
                    if accountBusy { ProgressView() }
                }
                Section("3. Código de 8 dígitos") {
                    Text("No PS5: *Configurações › Sistema › Uso remoto › Emparelhar dispositivo*. O código vale enquanto a tela estiver aberta.")
                        .font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        TextField("12345678", text: $pin)
                            .keyboardType(.numberPad)
                            .onChange(of: pin) { _, value in pin = String(value.filter(\.isNumber).prefix(8)) }
                        Button(pairing ? "Pareando…" : "Parear") { pair() }
                            .disabled(pairing || pin.count != 8 || accountID == nil || selectedAddress == nil)
                            .touchOnly()
                    }
                }
                if let message {
                    Section {
                        Label(message, systemImage: failed ? "xmark.octagon.fill" : "checkmark.circle.fill")
                            .foregroundStyle(failed ? .red : .green)
                    }
                }
            }
            .navigationTitle("Parear com o PS5")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fechar") { dismiss() }.touchOnly() } }
            .sheet(isPresented: $showLogin) {
                NavigationStack {
                    PSNLoginView { code in
                        showLogin = false
                        exchange(code: code)
                    }
                    .navigationTitle("Conta Sony")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { showLogin = false }.touchOnly() } }
                }
            }
        }
        .allowsKeyboardEntry()
        .onAppear {
            if let host = ps5.host { accountID = host.accountID }
            LocalNetworkAccess.triggerPrompt()
            scan()
        }
        .onDisappear { scanTask?.cancel() }
    }

    /// Looks for up to 30 s, because the first attempt can be denied while the Local Network alert is on screen.
    private func scan() {
        scanTask?.cancel()
        scanning = true
        let log = ps5.log
        scanTask = Task {
            let started = Date()
            var found: [PSDiscoveredHost] = []
            while found.isEmpty, !Task.isCancelled, Date().timeIntervalSince(started) < 30 {
                found = await Task.detached {
                    ((try? PSDiscovery.scan(timeout: 2.5, directHost: nil, forceSweep: true, log: log)) ?? [])
                        .filter { $0.isPS5 || $0.hostType == nil }
                }.value
            }
            consoles = found
            if selectedAddress == nil { selectedAddress = consoles.first?.address }
            scanning = false
        }
    }

    private func resolveAccount(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        message = nil
        if PSNAccountID.decode(text) != nil {
            accountID = text
            return
        }
        guard let code = PSNAccountID.code(fromRedirectURL: text) else {
            failed = true
            message = "Isso não é um ID nem uma URL com \"code=\"."
            return
        }
        exchange(code: code)
    }

    private func exchange(code: String) {
        accountBusy = true
        Task {
            do {
                accountID = try await PSNAccountID.fetchAccountID(code: code)
                failed = false
                message = "ID da conta obtido."
            } catch {
                failed = true
                message = "Não deu para obter o ID: \(error)"
            }
            accountBusy = false
        }
    }

    private func pair() {
        guard let console = selected, let accountID, let pinValue = UInt32(pin) else { return }
        pairing = true
        message = nil
        let log = ps5.log
        Task {
            let result: Result<PSHost, Error> = await Task.detached {
                do {
                    return .success(try PSRegistration.pair(address: console.address, pin: pinValue, accountID: accountID,
                                                            hostID: console.hostID, systemVersion: console.systemVersion, log: log))
                } catch {
                    return .failure(error)
                }
            }.value
            pairing = false
            switch result {
            case .success(let host):
                ps5.adopt(host)
                failed = false
                message = "Pareado com \(host.nickname). Pode fechar."
            case .failure(let error):
                failed = true
                message = "\(error)"
            }
        }
    }
}
