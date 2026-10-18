import SwiftUI

/// Phase 1 screen: proves on the phone that the Local Network alert appears, that the console is found without
/// broadcast, and how long the subnet sweep takes. It becomes the real app in Phase 2.
struct DiagnosticView: View {
    @State private var lines: [String] = ["Toque nos passos, de cima para baixo."]
    @State private var busy = false
    @State private var ignoreSavedAddress = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Controle PS5 · diagnóstico").font(.title2.bold())
            Button("1. Pedir a permissão de Rede Local") { requestLocalNetwork() }
                .buttonStyle(.borderedProminent).disabled(busy)
            Button("2. Procurar o PS5 (sem broadcast)") { search() }
                .buttonStyle(.borderedProminent).disabled(busy)
            Toggle("Ignorar o endereço salvo (testa só a varredura)", isOn: $ignoreSavedAddress).font(.footnote)
            ScrollView {
                Text(lines.joined(separator: "\n"))
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .preferredColorScheme(.dark)
    }

    private func log(_ text: String) { lines.append(text) }

    private func requestLocalNetwork() {
        busy = true
        let count = PSDiscovery.localSubnetAddresses().count
        log("Endereços na sub-rede: \(count)")
        LocalNetworkAccess.triggerPrompt()
        log("Pedido feito. Se o iOS mostrou o alerta, responda Permitir.")
        Task {
            guard let probeAddress = PSDiscovery.localSubnetAddresses().first else {
                log("Sem rede local: o iPhone está no Wi-Fi de casa?"); busy = false; return
            }
            let result = await LocalNetworkAccess.probe(host: probeAddress)
            switch result {
            case .allowed: log("Permissão: concedida")
            case .denied: log("Permissão: NEGADA. Ajustes > Privacidade e Segurança > Rede Local")
            case .undetermined: log("Permissão: sem resposta em 3 s (alerta ainda na tela?)")
            }
            busy = false
        }
    }

    private func search() {
        busy = true
        let saved = PSHostStorage.current.load()
        let direct = ignoreSavedAddress ? nil : saved?.lastAddress
        log("Procurando (até 30 s, repetindo a cada segundo)...")
        Task.detached {
            let logger = ChiakiLogger()
            let started = Date()
            var found: PSDiscoveredHost?
            var rounds = 0
            while found == nil, Date().timeIntervalSince(started) < 30 {
                rounds += 1
                found = try? PSDiscovery.find(hostID: saved?.hostID, lastAddress: direct, timeout: 3, log: logger)
            }
            let elapsed = Date().timeIntervalSince(started)
            await MainActor.run {
                if let found {
                    log("Achou \(found.hostName ?? "?") em \(found.address): \(found.state == .ready ? "ligado" : "repouso")")
                    log(String(format: "Resposta %.1f s depois da primeira sondagem da rodada; total %.1f s, %d rodada(s)",
                               found.answeredAfter, elapsed, rounds))
                } else {
                    log(String(format: "Nada em %.0f s. Permissão de Rede Local negada, PS5 desligado ou outra rede.", elapsed))
                }
                busy = false
            }
        }
    }
}
