import SwiftUI

/// Portrait: the remote for the thumb. Landscape: the whole DualSense. Pairing opens by itself the first time.
struct RootView: View {
    @ObservedObject var theater: HomeTheater
    @ObservedObject private var ps5: PS5Controller
    @ObservedObject private var tv: LGTVClient
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showPairing = false

    init(theater: HomeTheater) {
        self.theater = theater
        _ps5 = ObservedObject(wrappedValue: theater.ps5)
        _tv = ObservedObject(wrappedValue: theater.tv)
    }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if proxy.size.width > proxy.size.height {
                    FullPadView(ps5: ps5, tv: tv, showSettings: { showSettings = true })
                } else {
                    RemoteView(ps5: ps5, tv: tv, showSettings: { showSettings = true }, showPairing: { showPairing = true })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PadTheme.background.ignoresSafeArea())
        }
        .environmentObject(theater)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsScreen(ps5: ps5, tv: tv, repair: { showSettings = false; showPairing = true })
        }
        .sheet(isPresented: $showPairing) { PairingFlowView(ps5: ps5) }
        .onAppear { if !ps5.isPaired { showPairing = true } }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: Lifecycle.leaveForeground(ps5)
            case .active: ps5.resume()
            default: break
            }
        }
        .onChange(of: ps5.link) { _, link in if link == .connected { Haptics.connected() } }
        .overlay(alignment: .bottomLeading) { UITestProbe(ps5: ps5, theater: theater) }
    }
}

/// Shared pieces of the two layouts.
struct StatusHeader: View {
    @ObservedObject var ps5: PS5Controller
    @ObservedObject var tv: LGTVClient
    @EnvironmentObject var theater: HomeTheater
    var showSettings: () -> Void

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

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 10, height: 10).shadow(color: statusColor.opacity(0.7), radius: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(ps5.consoleName).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundColor(PadTheme.text)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(ps5.statusText).font(.system(size: 12)).foregroundColor(PadTheme.dim)
                }
            }
            Spacer()
            if ps5.videoBlocked {
                Label("app de vídeo", systemImage: "tv").font(.system(size: 12, weight: .semibold)).foregroundColor(.orange)
            } else if ps5.watching {
                Text("Assistindo").font(.system(size: 12, weight: .semibold)).foregroundColor(PadTheme.dim)
            }
            Menu {
                Button("Ligar o PS5") { ps5.wake() }.disabled(ps5.link == .ready || ps5.link == .connected)
                Button("Repouso") { ps5.requestStandby() }.disabled(ps5.link == .standby || ps5.link == .offline)
                Divider()
                Button("Ligar tudo (PS5 e TV)") { theater.turnOnAll() }
                Button("Desligar tudo") { theater.turnOffAll() }
            } label: {
                Image(systemName: "power").font(.system(size: 17, weight: .bold)).frame(width: 40, height: 40)
            }
            .disabled(!ps5.isPaired || theater.busy)
            .touchOnly()
            Button(action: showSettings) {
                Image(systemName: "gearshape").font(.system(size: 18)).frame(width: 40, height: 40)
            }
            .foregroundColor(PadTheme.text)
            .touchOnly()
        }
    }
}

struct StatusBanners: View {
    @ObservedObject var ps5: PS5Controller
    @EnvironmentObject var theater: HomeTheater
    var showSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let error = ps5.lastError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(error).font(.system(size: 12)).foregroundColor(PadTheme.dim)
                    Spacer()
                    Button { ps5.clearError() } label: { Image(systemName: "xmark").frame(width: 32, height: 32) }
                        .foregroundColor(PadTheme.dim).touchOnly()
                }
            }
            if !theater.step.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(theater.step).font(.system(size: 12)).foregroundColor(PadTheme.dim)
                    Spacer()
                }
            }
            if ps5.needsLoginPin {
                Button("O PS5 pede o PIN de login do usuário: informar em Ajustes", action: showSettings)
                    .buttonStyle(BarButtonStyle(tint: .orange, height: 40)).touchOnly()
            }
        }
    }
}
