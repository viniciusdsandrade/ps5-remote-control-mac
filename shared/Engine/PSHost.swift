import Foundation

/// The paired PS5: what registration returned plus where it was last seen. The keys let anyone on the LAN
/// control the console, so they are kept in `PSHostStorage.current`: a 0600 file on the Mac
/// (~/.config/ps5_remote_control/host.json) and the Keychain, this device only, on the iPhone.
struct PSHost: Codable, Equatable {
    var hostID: String            // discovery "host-id", stable across IP changes
    var nickname: String          // console name, e.g. "PS5-123"
    var mac: String               // server MAC from registration, "aa:bb:cc:dd:ee:ff"
    var lastAddress: String       // last known IPv4 address
    var registKey: String         // rp_regist_key: ASCII hex, at most 8 chars
    var rpKeyHex: String          // rp_key (the "morning"), 16 bytes as hex
    var rpKeyType: UInt32
    var accountID: String         // PSN account id, base64 of 8 little-endian bytes
    var consolePin: String? = nil // 4-digit login passcode of the console user, if any
    var systemVersion: String? = nil
    var pairedAt: Date = Date()

    /// `PS5_CONFIG_DIR` points the app and the CLI at another folder (the self-test uses it so it can
    /// never touch the real pairing).
    static var fileURL: URL {
        if let dir = ProcessInfo.processInfo.environment["PS5_CONFIG_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir).appendingPathComponent("host.json")
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/ps5_remote_control/host.json")
    }

    static func load() -> PSHost? { PSHostStorage.current.load() }

    func save() throws { try PSHostStorage.current.save(self) }

    static func forget() { PSHostStorage.current.forget() }

    /// The JSON form both stores keep.
    func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(json data: Data) -> PSHost? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PSHost.self, from: data)
    }

    // MARK: Values in the form the library wants

    /// 16 bytes, NUL padded, for ChiakiConnectInfo.regist_key.
    var registKeyBytes: [UInt8] { Array(registKey.utf8) }

    var rpKeyBytes: [UInt8]? {
        guard let bytes = hexBytes(rpKeyHex), bytes.count == 16 else { return nil }
        return bytes
    }

    var accountIDBytes: [UInt8]? { PSNAccountID.decode(accountID) }

    /// The wake packet carries the regist key read as hex and sent as a decimal number.
    var wakeCredential: UInt64? { UInt64(registKey, radix: 16) }

    init(hostID: String, nickname: String, mac: String, lastAddress: String, registKey: String,
         rpKeyHex: String, rpKeyType: UInt32, accountID: String, consolePin: String? = nil,
         systemVersion: String? = nil) {
        self.hostID = hostID
        self.nickname = nickname
        self.mac = mac
        self.lastAddress = lastAddress
        self.registKey = registKey
        self.rpKeyHex = rpKeyHex
        self.rpKeyType = rpKeyType
        self.accountID = accountID
        self.consolePin = consolePin
        self.systemVersion = systemVersion
    }

    /// From a successful registration. `hostID` and `systemVersion` come from discovery when known.
    init(registered host: ChiakiRegisteredHost, address: String, accountID: String,
         hostID: String?, systemVersion: String?) {
        let mac = bytes(of: host.server_mac).map { String(format: "%02x", $0) }.joined(separator: ":")
        self.init(hostID: hostID ?? mac.replacingOccurrences(of: ":", with: "").uppercased(),
                  nickname: cString(host.server_nickname),
                  mac: mac,
                  lastAddress: address,
                  registKey: cString(host.rp_regist_key),
                  rpKeyHex: hexString(bytes(of: host.rp_key)),
                  rpKeyType: host.rp_key_type,
                  accountID: accountID,
                  consolePin: host.console_pin != 0 ? String(host.console_pin) : nil,
                  systemVersion: systemVersion)
    }
}

// MARK: - Where the pairing lives

/// Storage for the pairing. The Mac app and `ps5ctl` use the file store (the default); the iPhone app installs
/// a Keychain store before anything else runs.
protocol PSHostStoring {
    func load() -> PSHost?
    func save(_ host: PSHost) throws
    func forget()
}

enum PSHostStorage {
    /// Set once at launch, before any other thread reads it.
    nonisolated(unsafe) static var current: PSHostStoring = FileHostStore()
}

/// `PSHost.fileURL`, mode 0600 in a 0700 folder.
struct FileHostStore: PSHostStoring {
    func load() -> PSHost? {
        guard let data = try? Data(contentsOf: PSHost.fileURL) else { return nil }
        return PSHost.decode(json: data)
    }

    func save(_ host: PSHost) throws {
        let data = try host.encodedJSON()
        let directory = PSHost.fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: PSHost.fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: PSHost.fileURL.path)
    }

    func forget() {
        try? FileManager.default.removeItem(at: PSHost.fileURL)
    }
}
