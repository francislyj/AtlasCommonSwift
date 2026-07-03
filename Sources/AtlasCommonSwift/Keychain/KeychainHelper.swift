import Foundation
import Security

public enum KeychainHelper {
    @discardableResult
    public static func save(key: String, data: Data) -> Bool {
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            // Persist across relaunches without needing the device unlocked at the
            // moment of access. The Keychain default (kSecAttrAccessibleWhenUnlocked)
            // makes the item unreadable while the device is locked — a token read on
            // a background/locked-device launch then returns nil and the app treats
            // the user as signed out. AfterFirstUnlock keeps it readable for the
            // rest of the boot session while still encrypted-at-rest before first
            // unlock. Auth tokens are exactly this "persist, read anytime after
            // first unlock" case.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    public static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    public static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]

        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    @discardableResult
    public static func saveString(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return save(key: key, data: data)
    }

    public static func loadString(key: String) -> String? {
        guard let data = load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
