import Foundation

enum PSPowerState: String {
    case ready      // on
    case standby    // rest mode with the network kept up
    case unknown
}

struct PSDiscoveredHost {
    var address: String
    var state: PSPowerState
    var hostID: String?
    var hostName: String?
    var hostType: String?
    var systemVersion: String?
    var requestPort: UInt16
    var runningAppName: String?
    var runningAppTitleID: String?
    /// Seconds from the first probe to this answer; the sweep timing is measured with it.
    var answeredAfter: TimeInterval = 0

    var isPS5: Bool { hostType == "PS5" }

    /// "14100003" -> "14.10"
    var systemVersionText: String? {
        guard let v = systemVersion, v.count == 8, let major = Int(v.prefix(2)), let minor = Int(v.dropFirst(2).prefix(2)) else {
            return systemVersion
        }
        return "\(major).\(String(format: "%02d", minor))"
    }
}

/// How discovery looks for consoles. The Mac broadcasts. On iOS, sending broadcast needs a special entitlement
/// from Apple, so the iPhone app asks the saved address first and, if the console stays silent, probes every
/// address of the local subnets, one by one (unicast needs only the Local Network permission).
struct PSDiscoveryPolicy {
    /// Send the probe to 255.255.255.255.
    var broadcast = true
    /// Seconds of silence (no console that matches) before probing every address of the local subnets.
    /// nil: never; 0: from the first round.
    var sweepAfter: TimeInterval? = nil
    /// At most one sweep per this many seconds (background polling must not probe 254 addresses every few
    /// seconds). Searches the user asks for (`forceSweep`) ignore it.
    var sweepMinInterval: TimeInterval = 0
}

/// One-shot discovery: sends the SRCH packet (to the broadcast address, to a known address and, per the policy,
/// to the whole local subnet) for `timeout` seconds and returns every console that answered. Blocking; call it
/// off the main thread.
enum PSDiscovery {
    /// Set once at launch, before any other thread reads it.
    nonisolated(unsafe) static var policy = PSDiscoveryPolicy()

    private static let sweepLock = NSLock()
    nonisolated(unsafe) private static var lastSweepAt: Date?

    /// True when a sweep may start now; records it when it does.
    private static func claimSweep(force: Bool) -> Bool {
        sweepLock.lock(); defer { sweepLock.unlock() }
        if !force, let last = lastSweepAt, Date().timeIntervalSince(last) < policy.sweepMinInterval { return false }
        lastSweepAt = Date()
        return true
    }

    private final class Collector {
        let lock = NSLock()
        var hosts: [PSDiscoveredHost] = []
        var start = Date()
    }

    static let ps5Port: UInt16 = 9302

    /// `wantedHostID` is the console the caller is after (nil: any PS5); it decides whether the sweep is needed.
    static func scan(timeout: TimeInterval = 2.0, directHost: String? = nil, wantedHostID: String? = nil,
                     forceSweep: Bool = false, log: ChiakiLogger) throws -> [PSDiscoveredHost] {
        ChiakiCore.ensureInitialized()

        let discovery = UnsafeMutablePointer<ChiakiDiscovery>.allocate(capacity: 1)
        discovery.initialize(to: ChiakiDiscovery())
        defer { discovery.deinitialize(count: 1); discovery.deallocate() }
        try chiakiCheck(chiaki_discovery_init(discovery, log.pointer, sa_family_t(AF_INET)), "chiaki_discovery_init")
        defer { chiaki_discovery_fini(discovery) }

        let thread = UnsafeMutablePointer<ChiakiDiscoveryThread>.allocate(capacity: 1)
        thread.initialize(to: ChiakiDiscoveryThread())
        defer { thread.deinitialize(count: 1); thread.deallocate() }

        let collector = Collector()
        collector.start = Date()
        let user = Unmanaged.passUnretained(collector).toOpaque()
        try chiakiCheck(chiaki_discovery_thread_start(thread, discovery, { hostPointer, user in
            // Strings point into the receive thread's buffer: copy them now.
            guard let hostPointer, let user else { return }
            let host = hostPointer.pointee
            let state: PSPowerState
            switch host.state {
            case CHIAKI_DISCOVERY_HOST_STATE_READY: state = .ready
            case CHIAKI_DISCOVERY_HOST_STATE_STANDBY: state = .standby
            default: state = .unknown
            }
            var item = PSDiscoveredHost(address: copyCString(host.host_addr) ?? "?",
                                        state: state,
                                        hostID: copyCString(host.host_id),
                                        hostName: copyCString(host.host_name),
                                        hostType: copyCString(host.host_type),
                                        systemVersion: copyCString(host.system_version),
                                        requestPort: host.host_request_port,
                                        runningAppName: copyCString(host.running_app_name),
                                        runningAppTitleID: copyCString(host.running_app_titleid))
            let collector = Unmanaged<Collector>.fromOpaque(user).takeUnretainedValue()
            collector.lock.lock()
            item.answeredAfter = Date().timeIntervalSince(collector.start)
            collector.hosts.append(item)
            collector.lock.unlock()
        }, user), "chiaki_discovery_thread_start")

        var packet = ChiakiDiscoveryPacket()
        packet.cmd = CHIAKI_DISCOVERY_CMD_SRCH
        packet.user_credential = 0
        let version = strdup(CHIAKI_DISCOVERY_PROTOCOL_VERSION_PS5)
        defer { free(version) }
        packet.protocol_version = version

        var targets: [String] = policy.broadcast ? ["255.255.255.255"] : []
        if let directHost, !targets.contains(directHost) { targets.append(directHost) }
        var sweep: [String] = []

        let started = Date()
        let deadline = started.addingTimeInterval(timeout)
        repeat {
            if sweep.isEmpty, let after = policy.sweepAfter, Date().timeIntervalSince(started) >= after {
                collector.lock.lock()
                let answered = collector.hosts.contains { host in
                    isUsableAddress(host.address) && (wantedHostID.map { host.hostID == $0 } ?? host.isPS5)
                }
                collector.lock.unlock()
                if !answered, claimSweep(force: forceSweep) { sweep = localSubnetAddresses().filter { !targets.contains($0) } }
            }
            for target in targets + sweep { send(discovery, &packet, to: target, port: ps5Port) }
            Thread.sleep(forTimeInterval: min(0.5, max(0.05, deadline.timeIntervalSinceNow)))
        } while Date() < deadline

        chiaki_discovery_thread_stop(thread)

        collector.lock.lock()
        defer { collector.lock.unlock() }
        // The same console answers the broadcast and the direct packet: keep one entry per address.
        // Right after waking up, a console can answer before its network is configured, from 0.0.0.0:
        // that address must never be saved or used.
        var seen = Set<String>()
        return collector.hosts
            .filter { isUsableAddress($0.address) }
            .filter { seen.insert($0.hostID ?? $0.address).inserted }
    }

    /// Finds one console: the one with that host-id when it is known (never another console, even if
    /// it is the only one that answers), otherwise the first PS5 that answers (the pairing flow).
    static func find(hostID: String?, lastAddress: String?, timeout: TimeInterval = 2.0, forceSweep: Bool = false,
                     log: ChiakiLogger) throws -> PSDiscoveredHost? {
        let hosts = try scan(timeout: timeout, directHost: lastAddress, wantedHostID: hostID, forceSweep: forceSweep, log: log)
        if let hostID { return hosts.first(where: { $0.hostID == hostID }) }
        return hosts.first(where: { $0.isPS5 })
    }

    /// Every other IPv4 address of the subnets this device is on: one per broadcast-capable interface (Wi-Fi,
    /// Ethernet; never cellular, VPN or loopback), at most a /24 around its own address. No interface is
    /// picked by name: on iOS `en0` is not always the Wi-Fi.
    static func localSubnetAddresses() -> [String] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(first) }
        let required = UInt32(IFF_UP | IFF_RUNNING | IFF_BROADCAST)
        var result: [String] = []
        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = interface.pointee
            guard entry.ifa_flags & required == required, entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let addressPointer = entry.ifa_addr, addressPointer.pointee.sa_family == sa_family_t(AF_INET),
                  let maskPointer = entry.ifa_netmask else { continue }
            let own = addressPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            var mask = maskPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            if own >> 16 == 0xA9FE { continue }           // 169.254/16: link-local, no router
            if mask < 0xFFFF_FF00 { mask = 0xFFFF_FF00 }   // never more than a /24
            let network = own & mask, broadcast = network | ~mask
            guard broadcast - network >= 2 else { continue }
            for candidate in (network + 1)..<broadcast where candidate != own {
                let text = "\(candidate >> 24).\((candidate >> 16) & 255).\((candidate >> 8) & 255).\(candidate & 255)"
                if !result.contains(text) { result.append(text) }
            }
        }
        return result
    }

    private static func send(_ discovery: UnsafeMutablePointer<ChiakiDiscovery>, _ packet: inout ChiakiDiscoveryPacket,
                             to host: String, port: UInt16) {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return }
        _ = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                chiaki_discovery_send(discovery, &packet, generic, MemoryLayout<sockaddr_in>.size)
            }
        }
    }
}

/// Wakes a PS5 from rest mode. Only works when rest mode keeps the network up (see the plan, section 10).
enum PSWake {
    static func wake(address: String, host: PSHost, log: ChiakiLogger) throws {
        ChiakiCore.ensureInitialized()
        guard let credential = host.wakeCredential else {
            throw ChiakiError.failed("chave de pareamento inválida para acordar o console: \(host.registKey)")
        }
        try chiakiCheck(chiaki_discovery_wakeup(log.pointer, nil, address, credential, true), "chiaki_discovery_wakeup")
    }
}

/// A unicast IPv4 address a session can connect to (not 0.0.0.0, not broadcast, not unparsable).
func isUsableAddress(_ address: String) -> Bool {
    var parsed = in_addr()
    guard inet_pton(AF_INET, address, &parsed) == 1 else { return false }
    return address != "0.0.0.0" && address != "255.255.255.255"
}

private func copyCString(_ pointer: UnsafePointer<CChar>?) -> String? {
    pointer.map { String(cString: $0) }
}
