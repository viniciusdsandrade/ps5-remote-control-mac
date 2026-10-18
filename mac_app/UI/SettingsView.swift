import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var ps5: PS5Controller
    @ObservedObject var tv: LGTVClient
    var repair: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var loginPin = ""
    @State private var confirmForget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Ajustes").font(.title2.bold())
                Spacer()
                Button("Fechar") { dismiss() }
            }
            .padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    consoleSection
                    connectionSection
                    tvSection
                    logSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 540, height: 640)
        .onAppear { loginPin = ps5.host?.consolePin ?? "" }
        .confirmationDialog("Esquecer o pareamento com \(ps5.consoleName)?", isPresented: $confirmForget) {
            Button("Esquecer", role: .destructive) { ps5.forget() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Não dá para desfazer: será preciso parear de novo, com um código novo do PS5.")
        }
    }

    private var consoleSection: some View {
        GroupBox("Console") {
            VStack(alignment: .leading, spacing: 6) {
                if let host = ps5.host {
                    Text("\(host.nickname) · \(host.lastAddress) · MAC \(host.mac)")
                    Text("id \(host.hostID) · sistema \(host.systemVersion ?? "?") · pareado em \(host.pairedAt.formatted(date: .numeric, time: .shortened))")
                        .font(.caption).foregroundColor(.secondary)
                    if let app = ps5.runningApp { Text("App aberto agora: \(app)").font(.caption) }
                } else {
                    Text("Nenhum console pareado.").foregroundColor(.secondary)
                }
                HStack {
                    Button(ps5.host == nil ? "Parear…" : "Parear de novo…") { repair() }
                    if ps5.host != nil {
                        Button("Esquecer", role: .destructive) { confirmForget = true }
                    }
                }
                Divider()
                Text("PIN de login do usuário do PS5 (só se o console pedir senha ao entrar)").font(.caption)
                HStack {
                    TextField("1234", text: $loginPin)
                        .textFieldStyle(.roundedBorder).frame(width: 90)
                        .onChange(of: loginPin) { _, value in loginPin = String(value.filter(\.isNumber).prefix(4)) }
                    Button("Salvar") { ps5.setLoginPin(loginPin) }
                        .disabled(ps5.host == nil || (!loginPin.isEmpty && loginPin.count != 4))
                }
            }
            .padding(4)
        }
    }

    private var connectionSection: some View {
        GroupBox("Conexão") {
            VStack(alignment: .leading, spacing: 8) {
                Text("A sessão abre no primeiro comando e é solta quando você para de usar. Enquanto ela está aberta, o vídeo dos apps de streaming fica escuro na TV.")
                    .font(.caption).foregroundColor(.secondary)
                Toggle("Assistindo (trate o app atual como vídeo mesmo sem o PS5 informar)", isOn: $ps5.watching)
                stepper("Soltar fora de apps de vídeo após", value: $ps5.policy.idleSeconds, range: 10...600, step: 10, unit: "s")
                stepper("Fora de apps de vídeo, soltar após um ✕ em", value: $ps5.policy.afterCrossSeconds, range: 2...120, step: 1, unit: "s")
                stepper("Em app de vídeo, soltar após", value: $ps5.policy.videoIdleSeconds, range: 3...120, step: 1, unit: "s")
                stepper("Em app de vídeo, soltar após um ✕ em", value: $ps5.policy.videoAfterPlaySeconds, range: 1...60, step: 1, unit: "s")
                stepper("Intervalo mínimo entre sessões (medido: 6 a 8 s)", value: $ps5.policy.minimumGapSeconds, range: 0...30, step: 1, unit: "s")
                HStack {
                    Text("Duração de um toque")
                    Spacer()
                    Stepper("\(ps5.policy.tapMilliseconds) ms", value: $ps5.policy.tapMilliseconds, in: 30...400, step: 10)
                }
                Divider()
                Toggle("Teclas pela TV (SIMPLINK), experimental", isOn: $ps5.cecEnabled)
                Text("Com vídeo tocando e sem sessão aberta, ✕, ○ e o direcional vão pela TV (HDMI-CEC), sem escurecer a imagem. Só funciona se a TV repassar ao PS5 as teclas que recebe pela rede: teste antes.")
                    .font(.caption).foregroundColor(.secondary)
                Button("Restaurar padrões") { ps5.policy = PS5Controller.Policy() }
            }
            .padding(4)
        }
    }

    private func stepper(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Stepper("\(Int(value.wrappedValue)) \(unit)", value: value, in: range, step: step)
        }
    }

    private var tvSection: some View {
        GroupBox("TV LG") {
            VStack(alignment: .leading, spacing: 6) {
                if LGTVClient.loadConfigFromDisk() != nil {
                    Text("\(tv.config.name ?? tv.config.model ?? "TV") · \(tv.config.host) · \(tvStateText)")
                    Text("Volume e mudo vêm do app Controle Remoto LG, pela rede. \"Ligar tudo\" acorda o PS5 e espera a TV ligar pelo HDMI; se não ligar, usa a TV Box (\(tv.canTurnOnTV ? "pareada" : "não pareada")).")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text("A TV ainda não foi configurada neste Mac (use o app Controle Remoto LG uma vez).")
                        .foregroundColor(.secondary)
                }
            }
            .padding(4)
        }
    }

    private var tvStateText: String {
        switch tv.powerState {
        case .on: return "ligada, volume \(tv.volumeLevel)\(tv.isMuted ? " (mudo)" : "")"
        case .off: return "desligada"
        case .turningOn: return "ligando"
        case .unknown: return "?"
        }
    }

    private var logSection: some View {
        GroupBox("Registro") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Toggle("Detalhado", isOn: $ps5.verboseLog)
                    Spacer()
                    Button("Copiar") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ps5.logLines.joined(separator: "\n"), forType: .string)
                    }
                }
                ScrollView {
                    Text(ps5.logLines.suffix(150).joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 160)
                .background(Color(white: 0.08))
            }
            .padding(4)
        }
    }
}
