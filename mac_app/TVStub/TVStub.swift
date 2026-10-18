import Foundation
import Combine

// Stand-in for the LG TV client of the sibling project `lg-roap-control`, which is not part of this
// repository. scripts/build_app.sh compiles this file when that project is not next to this one: the app
// then builds and works with the PS5, and the TV features (volume, mute, "Ligar tudo" through the TV)
// simply report that no TV is configured. Only the API the app uses is declared here.

enum TVKey: Int {
    case power = 1
    case up = 12, down = 13, left = 14, right = 15, ok = 20
    case back = 23
    case volumeUp = 24, volumeDown = 25, mute = 26
}

enum TVPowerState: Equatable {
    case unknown
    case on
    case off
    case turningOn
}

struct TVConfig: Codable {
    var host: String
    var model: String?
    var name: String?
}

@MainActor
final class LGTVClient: ObservableObject {
    @Published var config = TVConfig(host: "-", model: nil, name: nil)
    @Published var powerState: TVPowerState = .unknown
    @Published var isMuted = false
    @Published var volumeLevel = 0

    var canTurnOnTV: Bool { false }

    static func loadConfigFromDisk() -> TVConfig? { nil }

    func sendKey(_ key: TVKey) {}
    func refreshStatus() async {}
    func turnOn() {}
}
