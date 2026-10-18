import Foundation
import Security

/// Tokens remain in the device Keychain, never in UserDefaults or source code.
enum SecureStore {
    private static let service = "ru.pubchat.app.session"
    private static let accessKey = "access-token"
    private static let refreshKey = "refresh-cookie"
    private static let deviceKey = "device-id"

    static var accessToken: String? { read(accessKey) }
    static var refreshCookie: String? { read(refreshKey) }

    static var deviceID: String {
        if let existing = read(deviceKey), UUID(uuidString: existing) != nil {
            return existing
        }
        let created = UUID().uuidString.lowercased()
        save(created, for: deviceKey)
        return created
    }

    static func saveSession(accessToken: String, refreshCookie: String) {
        save(accessToken, for: accessKey)
        save(refreshCookie, for: refreshKey)
    }

    static func clearSession() {
        delete(accessKey)
        delete(refreshKey)
        // Keep the installation ID stable across logins and logouts.
    }

    private static func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    private static func read(_ key: String) -> String? {
        var parameters = query(key)
        parameters[kSecReturnData as String] = true
        parameters[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(parameters as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func save(_ value: String, for key: String) {
        let keyQuery = query(key)
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            keyQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var insertion = keyQuery
            insertion[kSecValueData as String] = data
            insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let status = SecItemAdd(insertion as CFDictionary, nil)
            assert(status == errSecSuccess, "Unable to write secure session storage")
        } else {
            assert(updateStatus == errSecSuccess, "Unable to update secure session storage")
        }
    }

    private static func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}
