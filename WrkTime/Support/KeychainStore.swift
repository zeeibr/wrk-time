import Foundation
import Security

/// The one place a secret is allowed to live.
///
/// The Claude API key is the user's own, billed to the user's own account, and
/// it is called directly from the device — there is no backend to hold it (see
/// HANDOFF §2). That makes *where* it rests the whole of the security story:
///
/// - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` keeps it encrypted at rest,
///   never in an iCloud or iTunes backup, and never synced to another device.
///   That is also why the key cannot appear in this app's own export file —
///   see `Archive`, which does not carry it.
/// - Never `UserDefaults`, which is an unencrypted plist.
/// - Never a build setting, an `.xcconfig`, or anything else that ends up
///   inside the shipped binary. A key baked into a build is extractable from
///   that build by anyone holding it.
/// - Never logged. There is no `print` of a key anywhere in this type, and
///   there should not be one anywhere else.
///
/// A key that leaks costs money rather than privacy, so the useful mitigation
/// is a spend limit on the key in the Anthropic console plus a key dedicated to
/// this app, so it can be rotated without breaking anything else.
enum KeychainStore {
    /// Scoped to the app's own bundle so a rename cannot collide with anything.
    private static let service = "com.zee.almanac.secrets"

    enum Key: String {
        case claudeAPIKey = "claude-api-key"
    }

    static func save(_ value: String, for key: Key) {
        let data = Data(value.utf8)
        // Delete first: SecItemUpdate would need a separate path, and an
        // overwrite is what the caller always means.
        remove(key)
        guard !value.isEmpty else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    static func remove(_ key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func has(_ key: Key) -> Bool { read(key) != nil }
}
