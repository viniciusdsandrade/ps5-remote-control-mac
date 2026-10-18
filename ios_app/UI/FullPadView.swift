import SwiftUI

/// Landscape layout: the whole DualSense (shoulders, Create and Options, touchpad click, both sticks).
struct FullPadView: View {
    @ObservedObject var ps5: PS5Controller
    @ObservedObject var tv: LGTVClient
    var showSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            StatusHeader(ps5: ps5, tv: tv, showSettings: showSettings)
            StatusBanners(ps5: ps5, showSettings: showSettings)
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        PadKey(button: .l2, title: "L2", width: 64, height: 36, hint: "L2")
                        PadKey(button: .l1, title: "L1", width: 64, height: 36, hint: "L1")
                    }
                    DPadView()
                    StickView(side: .left)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        PadKey(button: .create, title: "Create", width: 76, height: 36, fontSize: 12, hint: "Create")
                        PadKey(button: .options, title: "Options", width: 76, height: 36, fontSize: 12, hint: "Options")
                    }
                    PadKey(button: .touchpad, title: "touchpad", height: 70, fontSize: 12, hint: "Clique no touchpad")
                    HStack(spacing: 10) {
                        PadKey(button: .ps, title: "PS", width: 60, height: 44, fontSize: 14, hint: "PS")
                        Button { ps5.home() } label: { Text("Início") }
                            .buttonStyle(BarButtonStyle(height: 44)).touchOnly()
                    }
                }
                .frame(maxWidth: 260)
                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        PadKey(button: .r1, title: "R1", width: 64, height: 36, hint: "R1")
                        PadKey(button: .r2, title: "R2", width: 64, height: 36, hint: "R2")
                    }
                    FaceButtonsView()
                    StickView(side: .right)
                }
                .frame(maxWidth: .infinity)
            }
            .opacity(ps5.isPaired ? 1 : 0.35)
            .disabled(!ps5.isPaired)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
}
