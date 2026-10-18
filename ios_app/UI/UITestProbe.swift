import SwiftUI

/// Test mode only (launch argument -ps5-uitest): shows how many commands the controller and the theater accepted,
/// so a UI test can prove that keys never become commands and that a touch does. Invisible otherwise.
enum UITestMode {
    static var isOn: Bool { CommandLine.arguments.contains("-ps5-uitest") || CommandLine.arguments.contains("-ps5-selftest-input") }

    /// A made-up pairing kept in memory, so the app opens the remote screen without touching the Keychain (an
    /// unsigned Simulator build has no Keychain access) and, above all, never the real pairing.
    static func installSyntheticPairing() {
        let host = PSHost(hostID: "AABBCCDDEEFF", nickname: "PS5-123", mac: "aa:bb:cc:dd:ee:ff",
                          lastAddress: "192.0.2.18", registKey: "0000000a",
                          rpKeyHex: "00000000000000000000000000000000", rpKeyType: 0, accountID: "AAAAAAAAAAA=")
        PSHostStorage.current = MemoryHostStore(host: host)
    }
}

final class MemoryHostStore: PSHostStoring {
    private var host: PSHost?
    init(host: PSHost?) { self.host = host }
    func load() -> PSHost? { host }
    func save(_ host: PSHost) throws { self.host = host }
    func forget() { host = nil }
}

struct UITestProbe: View {
    @ObservedObject var ps5: PS5Controller
    @ObservedObject var theater: HomeTheater

    var body: some View {
        if UITestMode.isOn {
            // The counters are plain properties (not @Published), so the probe rereads them on a timer.
            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                VStack(alignment: .leading, spacing: 0) {
                    Text("ps5=\(ps5.acceptedCommands)").accessibilityIdentifier("probe.ps5")
                    Text("tv=\(theater.tvCommands)").accessibilityIdentifier("probe.tv")
                    Text("dropped=\(GuardedApplication.droppedPresses)").accessibilityIdentifier("probe.dropped")
                    Text("presses=\(GuardedApplication.eventsSeen[.presses] ?? 0) touches=\(GuardedApplication.eventsSeen[.touches] ?? 0)")
                        .accessibilityIdentifier("probe.events")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .padding(4)
            }
            .allowsHitTesting(false)
        }
    }
}
