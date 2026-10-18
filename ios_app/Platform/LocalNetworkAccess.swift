import Foundation
import Network

/// The iOS "Local Network" permission (TN3179). There is no API to ask for it or to read its state: the system
/// shows the alert on the first local network operation, and that first operation may be denied on the spot,
/// before the answer. So the app triggers the alert early (during pairing) and keeps retrying meanwhile.
enum LocalNetworkAccess {
    /// Connecting a UDP socket to an address of the local subnet triggers the alert without sending a packet.
    /// Best effort: the system gives no guarantee that it shows the alert (FB8711182).
    static func triggerPrompt() {
        for address in PSDiscovery.localSubnetAddresses().prefix(4) {
            let fd = socket(AF_INET, SOCK_DGRAM, 0)
            guard fd >= 0 else { continue }
            defer { close(fd) }
            var destination = sockaddr_in()
            destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            destination.sin_family = sa_family_t(AF_INET)
            destination.sin_port = UInt16(9).bigEndian   // discard service: nothing is sent anyway
            guard inet_pton(AF_INET, address, &destination.sin_addr) == 1 else { continue }
            _ = withUnsafePointer(to: &destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    enum Probe {
        case allowed        // the TCP attempt got an answer (open or refused): the permission is granted
        case denied         // the path says the local network is denied
        case undetermined   // no answer in time and no reason given
    }

    /// Tries a TCP connection to `host`:`port` with `NWConnection`, which reports `localNetworkDenied` while it
    /// waits when the permission was refused (and retries by itself if the user grants it later).
    static func probe(host: String, port: UInt16 = 9295, timeout: TimeInterval = 3) async -> Probe {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            let queue = DispatchQueue(label: "localnetwork.probe")
            let lock = NSLock()
            var finished = false
            func finish(_ result: Probe) {
                lock.lock(); defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume(returning: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(.allowed)
                case .failed:
                    finish(.allowed)   // refused or unreachable: the system let the attempt go out
                case .waiting:
                    if case .localNetworkDenied? = connection.currentPath?.unsatisfiedReason { finish(.denied) }
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(.undetermined) }
        }
    }
}
