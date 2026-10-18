import Foundation

/// A DualSense button as the library names it. Create is the SHARE bit; there is no Mute bit.
enum PSButton: String, CaseIterable {
    case cross, circle, square, triangle
    case up, down, left, right
    case l1, r1, l2, r2, l3, r3
    case options, create, touchpad, ps

    var bit: UInt32 {
        switch self {
        case .cross: return CHIAKI_CONTROLLER_BUTTON_CROSS.rawValue
        case .circle: return CHIAKI_CONTROLLER_BUTTON_MOON.rawValue
        case .square: return CHIAKI_CONTROLLER_BUTTON_BOX.rawValue
        case .triangle: return CHIAKI_CONTROLLER_BUTTON_PYRAMID.rawValue
        case .up: return CHIAKI_CONTROLLER_BUTTON_DPAD_UP.rawValue
        case .down: return CHIAKI_CONTROLLER_BUTTON_DPAD_DOWN.rawValue
        case .left: return CHIAKI_CONTROLLER_BUTTON_DPAD_LEFT.rawValue
        case .right: return CHIAKI_CONTROLLER_BUTTON_DPAD_RIGHT.rawValue
        case .l1: return CHIAKI_CONTROLLER_BUTTON_L1.rawValue
        case .r1: return CHIAKI_CONTROLLER_BUTTON_R1.rawValue
        case .l2: return CHIAKI_CONTROLLER_ANALOG_BUTTON_L2.rawValue
        case .r2: return CHIAKI_CONTROLLER_ANALOG_BUTTON_R2.rawValue
        case .l3: return CHIAKI_CONTROLLER_BUTTON_L3.rawValue
        case .r3: return CHIAKI_CONTROLLER_BUTTON_R3.rawValue
        case .options: return CHIAKI_CONTROLLER_BUTTON_OPTIONS.rawValue
        case .create: return CHIAKI_CONTROLLER_BUTTON_SHARE.rawValue
        case .touchpad: return CHIAKI_CONTROLLER_BUTTON_TOUCHPAD.rawValue
        case .ps: return CHIAKI_CONTROLLER_BUTTON_PS.rawValue
        }
    }

    /// Accepts the library names plus everyday aliases ("x", "o", "ok", "back", "share"...).
    static func parse(_ text: String) -> PSButton? {
        let key = text.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
        switch key {
        case "x", "cross", "ok", "enter", "select": return .cross
        case "o", "circle", "moon", "back", "voltar": return .circle
        case "square", "box", "quadrado": return .square
        case "triangle", "pyramid", "triangulo": return .triangle
        case "up", "cima", "dpadup": return .up
        case "down", "baixo", "dpaddown": return .down
        case "left", "esquerda", "dpadleft": return .left
        case "right", "direita", "dpadright": return .right
        case "l1": return .l1
        case "r1": return .r1
        case "l2": return .l2
        case "r2": return .r2
        case "l3": return .l3
        case "r3": return .r3
        case "options", "opcoes", "menu": return .options
        case "create", "share", "criar": return .create
        case "touchpad", "touch", "pad": return .touchpad
        case "ps", "home", "inicio": return .ps
        default: return nil
        }
    }
}

/// The controller state the session sends: buttons, triggers, sticks and touches.
struct PadState {
    var raw: ChiakiControllerState

    init() {
        raw = ChiakiControllerState()
        chiaki_controller_state_set_idle(&raw)
    }

    static let idle = PadState()

    mutating func press(_ button: PSButton) {
        raw.buttons |= button.bit
        if button == .l2 { raw.l2_state = 255 }
        if button == .r2 { raw.r2_state = 255 }
    }

    mutating func release(_ button: PSButton) {
        raw.buttons &= ~button.bit
        if button == .l2 { raw.l2_state = 0 }
        if button == .r2 { raw.r2_state = 0 }
    }

    func pressing(_ button: PSButton) -> PadState {
        var copy = self
        copy.press(button)
        return copy
    }

    /// Partial trigger pull, 0...255. Sets the analog button bit for anything above zero.
    mutating func setTrigger(_ button: PSButton, _ value: UInt8) {
        guard button == .l2 || button == .r2 else { return }
        if button == .l2 { raw.l2_state = value } else { raw.r2_state = value }
        if value > 0 { raw.buttons |= button.bit } else { raw.buttons &= ~button.bit }
    }

    /// Sticks in the library's int16 range; up is negative y.
    mutating func setLeftStick(x: Int16, y: Int16) {
        raw.left_x = x
        raw.left_y = y
    }

    mutating func setRightStick(x: Int16, y: Int16) {
        raw.right_x = x
        raw.right_y = y
    }

    /// Normalised -1...1 helper for UI code.
    static func axis(_ value: Double) -> Int16 {
        Int16(max(-1, min(1, value)) * 32767)
    }
}
