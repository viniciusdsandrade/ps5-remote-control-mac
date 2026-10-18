import SwiftUI

struct PS5RemoteView: View {
    @EnvironmentObject var theater: HomeTheater
    @ObservedObject var ps5: PS5Controller
    @ObservedObject var tv: LGTVClient
    @State private var showSettings = false
    @State private var showPairing = false

    var body: some View {
        VStack(spacing: 12) {
            header
            if let error = ps5.lastError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(error).font(.system(size: 11)).foregroundColor(PadTheme.dim)
                    Spacer()
                    Button { ps5.clearError() } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                        .buttonStyle(.plain).foregroundColor(PadTheme.dim)
                }
            }
            if !theater.step.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(theater.step).font(.system(size: 11)).foregroundColor(PadTheme.dim)
                    Spacer()
                }
            }
            if ps5.needsLoginPin {
                Button("O PS5 pede o PIN de login do usuário: informar em Ajustes") { showSettings = true }
                    .buttonStyle(BarButtonStyle(tint: .orange))
            }

            pad
                .opacity(ps5.isPaired ? 1 : 0.35)
                .disabled(!ps5.isPaired)

            if !ps5.isPaired {
                Button("Parear com o PS5…") { showPairing = true }
                    .buttonStyle(BarButtonStyle(tint: .white, fill: Color(red: 0.13, green: 0.45, blue: 0.85), height: 36))
            }

            Divider().overlay(PadTheme.border)
            bottomBar
        }
        .padding(14)
        .frame(width: 440)
        .background(PadTheme.background)
        .focusable(false)   // mouse only (see InputGuard): nothing here takes keyboard focus
        .sheet(isPresented: $showSettings) {
            SettingsView(ps5: ps5, tv: tv, repair: { showSettings = false; showPairing = true })
        }
        .sheet(isPresented: $showPairing) {
            PairingView(ps5: ps5)
        }
        .onAppear { if !ps5.isPaired { showPairing = true } }
    }

    // MARK: Header

    private var statusColor: Color {
        switch ps5.link {
        case .connected: return .green
        case .connecting, .waking, .cooldown: return .yellow
        case .ready: return Color(red: 0.35, green: 0.65, blue: 1.0)
        case .standby: return .orange
        case .inUse: return .red
        case .noHost, .unknown, .offline: return .gray
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 10, height: 10)
                .shadow(color: statusColor.opacity(0.7), radius: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(ps5.consoleName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(PadTheme.text)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(ps5.statusText)
                        .font(.system(size: 11))
                        .foregroundColor(PadTheme.dim)
                }
            }
            Spacer()
            if ps5.videoBlocked {
                Label("app de vídeo", systemImage: "tv")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)
                    .help("O PS5 informou que o que está na tela não pode ser transmitido (app de streaming). Com a sessão aberta a imagem da TV fica escura; o app solta a sessão sozinho.")
            } else if let app = ps5.runningApp {
                Text(app)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(PadTheme.dim)
                    .lineLimit(1)
                    .frame(maxWidth: 120)
            } else if ps5.watching {
                Text("Assistindo").font(.system(size: 11, weight: .semibold)).foregroundColor(PadTheme.dim)
            }
            Menu {
                Button("Ligar o PS5") { ps5.wake() }
                    .disabled(ps5.link == .ready || ps5.link == .connected)
                Button("Repouso") { ps5.requestStandby() }
                    .disabled(ps5.link == .standby || ps5.link == .offline)
                Divider()
                Button("Ligar tudo (PS5 e TV)") { theater.turnOnAll() }
                Button("Desligar tudo") { theater.turnOffAll() }
            } label: {
                Image(systemName: "power").font(.system(size: 13, weight: .bold))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
            .disabled(!ps5.isPaired || theater.busy)
            .help("Energia")
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .foregroundColor(PadTheme.text)
            .help("Ajustes")
        }
    }

    // MARK: Pad

    private var pad: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                PadKey(button: .l2, title: "L2", width: 64, height: 30, hint: "L2")
                PadKey(button: .l1, title: "L1", width: 64, height: 30, hint: "L1")
                Spacer()
                PadKey(button: .r1, title: "R1", width: 64, height: 30, hint: "R1")
                PadKey(button: .r2, title: "R2", width: 64, height: 30, hint: "R2")
            }
            HStack(spacing: 8) {
                PadKey(button: .create, title: "Create", width: 70, height: 30, fontSize: 11, hint: "Create")
                PadKey(button: .touchpad, title: "touchpad", height: 44, fontSize: 11, hint: "Clique no touchpad")
                PadKey(button: .options, title: "Options", width: 70, height: 30, fontSize: 11, hint: "Options")
            }
            HStack(alignment: .center) {
                DPadView()
                Spacer()
                FaceButtonsView()
            }
            .padding(.horizontal, 6)
            HStack(alignment: .center, spacing: 10) {
                StickView(side: .left)
                Spacer()
                PadKey(button: .ps, title: "PS", width: 56, height: 40, fontSize: 13, hint: "PS: toque abre a central; segurar vai ao início")
                Button { ps5.home() } label: { Text("Início") }
                    .buttonStyle(BarButtonStyle(height: 40))
                    .help("Tela inicial: PS segurado por 1,5 s")
                Spacer()
                StickView(side: .right)
            }
        }
    }

    // MARK: Bottom bar

    private var tvOn: Bool { tv.powerState == .on }

    private var bottomBar: some View {
        HStack(spacing: 6) {
            Text("TV").font(.system(size: 11, weight: .bold)).foregroundColor(PadTheme.dim)
            Button("−") { theater.tvKey(.volumeDown) }.buttonStyle(BarButtonStyle()).disabled(!tvOn).help("Volume −")
            Button { theater.tvKey(.mute) } label: { Image(systemName: tv.isMuted ? "speaker.slash.fill" : "speaker.fill") }
                .buttonStyle(BarButtonStyle(tint: tv.isMuted ? .orange : PadTheme.text)).disabled(!tvOn).help("Mudo")
            Button("+") { theater.tvKey(.volumeUp) }.buttonStyle(BarButtonStyle()).disabled(!tvOn).help("Volume +")
            Spacer()
            Button { ps5.watch() } label: { Label("Assistir", systemImage: "play.fill") }
                .buttonStyle(BarButtonStyle(tint: .white, fill: Color(red: 0.13, green: 0.55, blue: 0.27)))
                .disabled(!ps5.isPaired)
                .help("✕ e solta a sessão: a imagem da TV volta em segundos")
        }
    }
}
