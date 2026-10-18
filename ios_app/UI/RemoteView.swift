import SwiftUI

/// Portrait layout, for one hand: what streaming apps use (direction pad with ✕ in the middle, ○, PS, Início,
/// Options), the TV volume and "Assistir", all within reach of the thumb.
struct RemoteView: View {
    @ObservedObject var ps5: PS5Controller
    @ObservedObject var tv: LGTVClient
    @EnvironmentObject var theater: HomeTheater
    var showSettings: () -> Void
    var showPairing: () -> Void

    private var tvOn: Bool { tv.powerState == .on }

    var body: some View {
        VStack(spacing: 14) {
            StatusHeader(ps5: ps5, tv: tv, showSettings: showSettings)
            StatusBanners(ps5: ps5, showSettings: showSettings)
            pad
                .opacity(ps5.isPaired ? 1 : 0.35)
                .disabled(!ps5.isPaired)
            if !ps5.isPaired {
                Button("Parear com o PS5…", action: showPairing)
                    .buttonStyle(BarButtonStyle(tint: .white, fill: Color(red: 0.13, green: 0.45, blue: 0.85), height: 44))
                    .touchOnly()
            }
            Spacer(minLength: 0)
            tvBar
            Text("Gire o iPhone para o DualSense completo").font(.system(size: 11)).foregroundColor(PadTheme.dim)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var pad: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                PadKey(button: .l2, title: "L2", width: 70, height: 38, hint: "L2")
                PadKey(button: .l1, title: "L1", width: 70, height: 38, hint: "L1")
                Spacer()
                PadKey(button: .r1, title: "R1", width: 70, height: 38, hint: "R1")
                PadKey(button: .r2, title: "R2", width: 70, height: 38, hint: "R2")
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Color.clear.frame(width: 76, height: 76)
                    PadKey(button: .up, title: "▲", width: 76, height: 76, fontSize: 20, hint: "Cima")
                    Color.clear.frame(width: 76, height: 76)
                }
                GridRow {
                    PadKey(button: .left, title: "◀", width: 76, height: 76, fontSize: 20, hint: "Esquerda")
                    PadKey(button: .cross, title: "✕", tint: PadTheme.cross, width: 76, height: 76, circular: true, fontSize: 30, hint: "Confirmar")
                    PadKey(button: .right, title: "▶", width: 76, height: 76, fontSize: 20, hint: "Direita")
                }
                GridRow {
                    Color.clear.frame(width: 76, height: 76)
                    PadKey(button: .down, title: "▼", width: 76, height: 76, fontSize: 20, hint: "Baixo")
                    Color.clear.frame(width: 76, height: 76)
                }
            }
            HStack(spacing: 12) {
                PadKey(button: .circle, title: "○ Voltar", tint: PadTheme.circle, height: 52, fontSize: 16, hint: "Voltar")
                PadKey(button: .ps, title: "PS", height: 52, fontSize: 16, hint: "PS: toque abre a central; segurar vai ao início")
                Button { ps5.home() } label: { Text("Início").frame(maxWidth: .infinity) }
                    .buttonStyle(BarButtonStyle(height: 52)).touchOnly()
            }
            HStack(spacing: 10) {
                PadKey(button: .create, title: "Create", height: 44, fontSize: 13, hint: "Create")
                PadKey(button: .options, title: "Options", height: 44, fontSize: 13, hint: "Options")
                PadKey(button: .triangle, title: "△", tint: PadTheme.triangle, height: 44, fontSize: 20, hint: "Triângulo")
                PadKey(button: .square, title: "□", tint: PadTheme.square, height: 44, fontSize: 20, hint: "Quadrado")
            }
        }
    }

    private var tvBar: some View {
        HStack(spacing: 8) {
            Text("TV").font(.system(size: 12, weight: .bold)).foregroundColor(PadTheme.dim)
            Button("−") { theater.tvKey(.volumeDown) }.buttonStyle(BarButtonStyle(height: 44)).disabled(!tvOn).touchOnly()
            Button { theater.tvKey(.mute) } label: { Image(systemName: tv.isMuted ? "speaker.slash.fill" : "speaker.fill") }
                .buttonStyle(BarButtonStyle(tint: tv.isMuted ? .orange : PadTheme.text, height: 44)).disabled(!tvOn).touchOnly()
            Button("+") { theater.tvKey(.volumeUp) }.buttonStyle(BarButtonStyle(height: 44)).disabled(!tvOn).touchOnly()
            Spacer()
            Button { ps5.watch() } label: { Label("Assistir", systemImage: "play.fill") }
                .buttonStyle(BarButtonStyle(tint: .white, fill: Color(red: 0.13, green: 0.55, blue: 0.27), height: 44))
                .disabled(!ps5.isPaired).touchOnly()
        }
    }
}
