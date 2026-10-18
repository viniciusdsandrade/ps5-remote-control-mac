import SwiftUI

struct SettingsScreen: View {
    @ObservedObject var ps5: PS5Controller
    @ObservedObject var tv: LGTVClient
    var repair: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var loginPin = ""
    @State private var confirmForget = false

    var body: some View {
        NavigationStack {
            Form {
                consoleSection
                connectionSection
                Section("TV") {
                    Text("A TV LG e a TV Box entram numa etapa seguinte: volume, mudo, \"Ligar tudo\" e as teclas pela TV.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Rede") {
                    NavigationLink("Diagnóstico de rede") { DiagnosticView() }.touchOnly()
                }
                logSection
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fechar") { dismiss() }.touchOnly() } }
        }
        .allowsKeyboardEntry()
        .onAppear { loginPin = ps5.host?.consolePin ?? "" }
        .confirmationDialog("Esquecer o pareamento com \(ps5.consoleName)?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Esquecer", role: .destructive) { ps5.forget() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Não dá para desfazer: será preciso parear de novo, com um código novo do PS5.")
        }
    }

    private var consoleSection: some View {
        Section("Console") {
            if let host = ps5.host {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(host.nickname) · \(host.lastAddress)")
                    Text("sistema \(host.systemVersion ?? "?") · pareado em \(host.pairedAt.formatted(date: .numeric, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Nenhum console pareado.").foregroundStyle(.secondary)
            }
            Button(ps5.host == nil ? "Parear…" : "Parear de novo…", action: repair).touchOnly()
            if ps5.host != nil {
                Button("Esquecer", role: .destructive) { confirmForget = true }.touchOnly()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("PIN de login do usuário do PS5 (só se o console pedir senha ao entrar)").font(.caption)
                HStack {
                    TextField("1234", text: $loginPin)
                        .keyboardType(.numberPad)
                        .onChange(of: loginPin) { _, value in loginPin = String(value.filter(\.isNumber).prefix(4)) }
                    Button("Salvar") { ps5.setLoginPin(loginPin) }
                        .disabled(ps5.host == nil || (!loginPin.isEmpty && loginPin.count != 4))
                        .touchOnly()
                }
            }
        }
    }

    private var connectionSection: some View {
        Section {
            Toggle("Assistindo (trata o app atual como vídeo)", isOn: $ps5.watching)
            stepper("Soltar fora de apps de vídeo após", value: $ps5.policy.idleSeconds, range: 10...600, step: 10)
            stepper("Fora de apps de vídeo, após um ✕", value: $ps5.policy.afterCrossSeconds, range: 2...120, step: 1)
            stepper("Em app de vídeo, soltar após", value: $ps5.policy.videoIdleSeconds, range: 3...120, step: 1)
            stepper("Em app de vídeo, após um ✕", value: $ps5.policy.videoAfterPlaySeconds, range: 1...60, step: 1)
            stepper("Intervalo mínimo entre sessões", value: $ps5.policy.minimumGapSeconds, range: 0...30, step: 1)
            Stepper("Duração de um toque: \(ps5.policy.tapMilliseconds) ms", value: $ps5.policy.tapMilliseconds, in: 30...400, step: 10)
            Button("Restaurar padrões") { ps5.policy = PS5Controller.Policy() }.touchOnly()
        } header: {
            Text("Conexão")
        } footer: {
            Text("A sessão abre no primeiro toque e é solta quando você para de usar ou sai do app. Enquanto ela está aberta, o vídeo dos apps de streaming fica escuro na TV.")
        }
    }

    private func stepper(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        Stepper("\(title): \(Int(value.wrappedValue)) s", value: value, in: range, step: step)
    }

    private var logSection: some View {
        Section("Registro") {
            Toggle("Detalhado", isOn: $ps5.verboseLog)
            Button("Copiar") { UIPasteboard.general.string = ps5.logLines.joined(separator: "\n") }.touchOnly()
            Text(ps5.logLines.suffix(80).joined(separator: "\n"))
                .font(.system(size: 10, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}
