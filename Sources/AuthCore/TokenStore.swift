import AtlasCommonSwift
import Foundation

/// Persists the JWT pair in the Keychain. Keys are namespaced so they don't
/// collide with other Keychain items (KeychainHelper keys on account only).
struct KeychainTokenStore: TokenStoring {
    private let accessKey = "atlas.auth.accessToken"
    private let refreshKey = "atlas.auth.refreshToken"

    func loadAccess() -> String? {
        KeychainHelper.loadString(key: accessKey)
    }

    func loadRefresh() -> String? {
        KeychainHelper.loadString(key: refreshKey)
    }

    func save(_ tokens: TokenResponse) {
        KeychainHelper.saveString(key: accessKey, value: tokens.accessToken)
        KeychainHelper.saveString(key: refreshKey, value: tokens.refreshToken)
    }

    func clear() {
        KeychainHelper.delete(key: accessKey)
        KeychainHelper.delete(key: refreshKey)
    }
}
