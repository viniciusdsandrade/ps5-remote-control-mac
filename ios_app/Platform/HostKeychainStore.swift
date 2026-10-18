import Foundation
import Security

/// The pairing in the Keychain: this device only (`ThisDeviceOnly` keeps it out of iCloud Keychain and out of
/// backups restored on another device), readable after the first unlock so a session can start while the
/// phone is locked by a shortcut later on. The JSON is the same one the Mac keeps in its 0600 file.
struct KeychainHostStore: PSHostStoring {
    let service: String
    private let account = "host"

    private var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func load() -> PSHost? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return PSHost.decode(json: data)
    }

    func save(_ host: PSHost) throws {
        let data = try host.encodedJSON()
        let update = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw ChiakiError.failed("Keychain: erro \(update) ao atualizar o pareamento") }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw ChiakiError.failed("Keychain: erro \(status) ao guardar o pareamento") }
    }

    func forget() {
        SecItemDelete(base as CFDictionary)
    }
}
