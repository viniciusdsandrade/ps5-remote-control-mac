import SwiftUI

// Look: the dark titanium remote of "Controle Remoto LG", with the DualSense symbol colours.

enum PadTheme {
    static let background = LinearGradient(colors: [Color(white: 0.14), Color(white: 0.10)], startPoint: .top, endPoint: .bottom)
    static let key = Color(white: 0.20)
    static let keyDown = Color(white: 0.36)
    static let border = Color(white: 0.28)
    static let text = Color(white: 0.95)
    static let dim = Color(white: 0.62)
    static let triangle = Color(red: 0.30, green: 0.80, blue: 0.55)
    static let square = Color(red: 0.95, green: 0.52, blue: 0.74)
    static let circle = Color(red: 0.96, green: 0.42, blue: 0.42)
    static let cross = Color(red: 0.48, green: 0.66, blue: 0.97)
}

/// A pad key with real press and release (mouse down and up), so holding works like on the controller.
struct PadKey: View {
    @EnvironmentObject var theater: HomeTheater
    let button: PSButton
    var title: String
    var tint: Color = PadTheme.text
    var width: CGFloat? = nil
    var height: CGFloat = 40
    var circular = false
    var fontSize: CGFloat = 14
    var hint: String = ""
    @State private var mouseDown = false

    private var isDown: Bool { mouseDown || theater.ps5.pressed.contains(button) }
    private var shape: AnyShape { circular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 10)) }

    var body: some View {
        Text(title)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .foregroundColor(tint)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .background(shape.fill(isDown ? PadTheme.keyDown : PadTheme.key)
                .shadow(color: .black.opacity(isDown ? 0.1 : 0.35), radius: 2, x: 0, y: 1.5))
            .overlay(shape.stroke(isDown ? Color.white.opacity(0.35) : PadTheme.border, lineWidth: 1))
            .scaleEffect(isDown ? 0.94 : 1)
            .animation(.easeInOut(duration: 0.08), value: isDown)
            .contentShape(shape)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !mouseDown {
                        mouseDown = true
                        theater.keyDown(button)
                    }
                }
                .onEnded { _ in
                    if mouseDown {
                        mouseDown = false
                        theater.keyUp(button)
                    }
                })
            .help(hint.isEmpty ? button.rawValue : hint)
            .focusable(false)   // mouse only: no keyboard focus, so Space/Return can't press it
    }
}

struct DPadView: View {
    var body: some View {
        VStack(spacing: 4) {
            PadKey(button: .up, title: "▲", width: 44, height: 44, hint: "Cima")
            HStack(spacing: 4) {
                PadKey(button: .left, title: "◀", width: 44, height: 44, hint: "Esquerda")
                Circle().fill(Color(white: 0.17)).frame(width: 44, height: 44)
                PadKey(button: .right, title: "▶", width: 44, height: 44, hint: "Direita")
            }
            PadKey(button: .down, title: "▼", width: 44, height: 44, hint: "Baixo")
        }
    }
}

struct FaceButtonsView: View {
    var body: some View {
        VStack(spacing: 4) {
            PadKey(button: .triangle, title: "△", tint: PadTheme.triangle, width: 44, height: 44, circular: true, fontSize: 20, hint: "Triângulo")
            HStack(spacing: 4) {
                PadKey(button: .square, title: "□", tint: PadTheme.square, width: 44, height: 44, circular: true, fontSize: 20, hint: "Quadrado")
                Circle().fill(Color.clear).frame(width: 44, height: 44)
                PadKey(button: .circle, title: "○", tint: PadTheme.circle, width: 44, height: 44, circular: true, fontSize: 20, hint: "Círculo: voltar")
            }
            PadKey(button: .cross, title: "✕", tint: PadTheme.cross, width: 44, height: 44, circular: true, fontSize: 20, hint: "Xis: confirmar")
        }
    }
}

/// Analog stick: drag to move, release to centre, click for L3/R3.
struct StickView: View {
    @EnvironmentObject var theater: HomeTheater
    enum Side { case left, right }
    let side: Side
    @State private var offset: CGSize = .zero
    private let radius: CGFloat = 26

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.16))
                .overlay(Circle().stroke(PadTheme.border, lineWidth: 1))
            Circle().fill(Color(white: 0.30))
                .overlay(Circle().stroke(Color(white: 0.45), lineWidth: 1))
                .frame(width: 30, height: 30)
                .offset(offset)
        }
        .frame(width: 2 * radius + 24, height: 2 * radius + 24)
        .contentShape(Circle())
        .simultaneousGesture(TapGesture().onEnded {
            theater.ps5.tap(side == .left ? .l3 : .r3)
        })
        .gesture(DragGesture(minimumDistance: 3)
            .onChanged { value in
                var dx = value.translation.width
                var dy = value.translation.height
                let length = sqrt(dx * dx + dy * dy)
                if length > radius { dx *= radius / length; dy *= radius / length }
                offset = CGSize(width: dx, height: dy)
                let x = PadState.axis(Double(dx / radius))
                let y = PadState.axis(Double(dy / radius))
                if side == .left { theater.ps5.setLeftStick(x: x, y: y) } else { theater.ps5.setRightStick(x: x, y: y) }
            }
            .onEnded { _ in
                offset = .zero
                if side == .left { theater.ps5.setLeftStick(x: 0, y: 0) } else { theater.ps5.setRightStick(x: 0, y: 0) }
            })
        .help(side == .left ? "Analógico esquerdo (clique = L3)" : "Analógico direito (clique = R3)")
        .focusable(false)
    }
}

/// Plain clickable button for the bars (not a pad key).
struct BarButtonStyle: ButtonStyle {
    var tint: Color = PadTheme.text
    var fill: Color = PadTheme.key
    var height: CGFloat = 32

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 8).fill(configuration.isPressed ? fill.opacity(0.65) : fill))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(PadTheme.border, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
    }
}
