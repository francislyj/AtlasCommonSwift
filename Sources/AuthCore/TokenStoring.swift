import Foundation

/// Persistence boundary for the JWT pair. Production uses `KeychainTokenStore`;
/// tests inject an in-memory double so they don't touch the real Keychain.
public protocol TokenStoring: Sendable {
    func loadAccess() -> String?
    func loadRefresh() -> String?
    func save(_ tokens: TokenResponse)
    func clear()
}
