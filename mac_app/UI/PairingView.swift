import SwiftUI
import AppKit

/// Three steps: find the console, get the PSN account id, type the 8-digit code.
struct PairingView: View {
    @ObservedObject var ps5: PS5Controller
    @Environment(\.dismiss) private var dismiss

    @State private var consoles: [PSDiscoveredHost] = []
    @State private var scanning = false
    @State private var selectedAddress: String?
    @State private var accountInput = ""
    @State private var accountID: String?
    @State private var accountBusy = false
    @State private var pin = ""
    @State private var pairing = false
    @State private var message: String?
    @State private var failed = false

    private var selected: PSDiscoveredHost? { consoles.first { $0.address == selectedAddress } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Parear com o PS5").font(.title2.bold())
            Text("Uma vez só. O PS5 precisa estar ligado e na mesma rede, com *Configurações › Sistema › Uso remoto › Ativar o Uso remoto* ligado.")
                .font(.callout).foregroundColor(.secondary)

            GroupBox("1. Console") {
                VStack(alignment: .leading, spacing: 6) {
                    if consoles.isEmpty {
                        HStack {
                            if scanning { ProgressView().controlSize(.small) }
                            Text(scanning ? "Procurando…" : "Nenhum console respondeu.").foregroundColor(.secondary)
                        }
                    }
                    ForEach(consoles, id: \.address) { console in
                        HStack {
                            Image(systemName: console.address == selectedAddress ? "largecircle.fill.circle" : "circle")
                            Text("\(console.hostName ?? "?") · \(console.address) · \(console.state == .ready ? "ligado" : console.state == .standby ? "em repouso" : "?")")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedAddress = console.address }
                    }
                    Button("Procurar de novo") { scan() }.disabled(scanning)
                }
                .padding(4)
            }

            GroupBox("2. ID da conta PSN") {
                VStack(alignment: .leading, spacing: 6) {
                    if let accountID {
                        Label("ID: \(accountID)", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                    }
                    Text("Entre na Sony com a conta usada no PS5. Depois do login a página fica em branco ou dá erro: copie a URL inteira da barra de endereços e cole abaixo. Quem já tem o ID pode colar o ID.")
                        .font(.caption).foregroundColor(.secondary)
                    HStack {
                        Button("Abrir login da Sony") { NSWorkspace.shared.open(PSNAccountID.loginURL) }
                        TextField("URL de redirecionamento ou ID", text: $accountInput)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { resolveAccount() }
                        Button("Usar") { resolveAccount() }.disabled(accountInput.isEmpty || accountBusy)
                        if accountBusy { ProgressView().controlSize(.small) }
                    }
                }
                .padding(4)
            }

            GroupBox("3. Código de 8 dígitos") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No PS5: *Configurações › Sistema › Uso remoto › Emparelhar dispositivo*. O código vale enquanto a tela estiver aberta.")
                        .font(.caption).foregroundColor(.secondary)
                    HStack {
                        TextField("12345678", text: $pin)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .onChange(of: pin) { _, value in pin = String(value.filter(\.isNumber).prefix(8)) }
                        Button(pairing ? "Pareando…" : "Parear") { pair() }
                            .disabled(pairing || pin.count != 8 || accountID == nil || selectedAddress == nil)
                        if pairing { ProgressView().controlSize(.small) }
                    }
                }
                .padding(4)
            }

            if let message {
                Label(message, systemImage: failed ? "xmark.octagon.fill" : "checkmark.circle.fill")
                    .foregroundColor(failed ? .red : .green)
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("Fechar") { dismiss() }
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            if let host = ps5.host { accountID = host.accountID }
            scan()
        }
    }

    private func scan() {
        scanning = true
        let log = ps5.log
        Task {
            let found = await Task.detached { (try? PSDiscovery.scan(timeout: 2, directHost: nil, log: log)) ?? [] }.value
            consoles = found.filter { $0.isPS5 || $0.hostType == nil }
            if selectedAddress == nil { selectedAddress = consoles.first?.address }
            scanning = false
        }
    }

    private func resolveAccount() {
        let text = accountInput.trimmingCharacters(in: .whitespacesAndNewlines)
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
