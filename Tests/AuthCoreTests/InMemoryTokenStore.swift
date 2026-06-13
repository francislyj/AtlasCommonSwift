import Foundation
@testable import AuthCore

/// In-memory `TokenStoring` for tests. A reference type guarded by a lock so
/// writes made inside the `AuthSession` actor are observable from the test body.
final class InMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var access: String?
    private var refresh: String?

    init(access: String? = nil, refresh: String? = nil) {
        self.access = access
        self.refresh = refresh
    }

    func loadAccess() -> String? {
        lock.lock(); defer { lock.unlock() }
        return access
    }

    func loadRefresh() -> String? {
        lock.lock(); defer { lock.unlock() }
        return refresh
    }

    func save(_ tokens: TokenResponse) {
        lock.lock(); defer { lock.unlock() }
        access = tokens.accessToken
        refresh = tokens.refreshToken
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        access = nil
        refresh = nil
    }
}
