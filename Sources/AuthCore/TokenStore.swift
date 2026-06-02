import AtlasCommonSwift
import Foundation

/// Persists the JWT pair in the Keychain. Keys are namespaced so they don't
/// collide with other Keychain items (KeychainHelper keys on account only).
enum TokenStore {
    private static let accessKey = "atlas.auth.accessToken"
    private static let refreshKey = "atlas.auth.refreshToken"

    static func save(_ tokens: TokenResponse) {
        KeychainHelper.saveString(key: accessKey, value: tokens.accessToken)
        KeychainHelper.saveString(key: refreshKey, value: tokens.refreshToken)
    }

    static func loadAccess() -> String? {
        KeychainHelper.loadString(key: accessKey)
    }

    static func loadRefresh() -> String? {
        KeychainHelper.loadString(key: refreshKey)
    }

    static func clear() {
        KeychainHelper.delete(key: accessKey)
        KeychainHelper.delete(key: refreshKey)
    }
}
