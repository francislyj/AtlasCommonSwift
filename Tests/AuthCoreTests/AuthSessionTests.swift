import Foundation
import Testing
@testable import AtlasCommonSwift
@testable import AuthCore

private let testURL = URL(string: "https://auth.test")!

/// Thread-safe call counter for handlers that must vary by invocation.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
}

private func tokenSession(access: String, refresh: String) -> URLSession {
    MockURLProtocol.makeSession { _ in (200, MockURLProtocol.tokenEnvelope(access: access, refresh: refresh)) }
}

@Suite struct AuthSessionTests {

    // MARK: sign-in flows

    @Test func loginStoresTokensAndAuthenticates() async throws {
        let store = InMemoryTokenStore()
        let session = AuthSession(baseURL: testURL, session: tokenSession(access: "acc", refresh: "ref"), tokenStore: store)

        try await session.login(email: "a@b.com", password: "pw")

        #expect(await session.isAuthenticated)
        #expect(store.loadAccess() == "acc")
        #expect(store.loadRefresh() == "ref")
        #expect(await session.tokenProvider() == "acc")
    }

    @Test func registerConfirmStoresTokens() async throws {
        let store = InMemoryTokenStore()
        let session = AuthSession(baseURL: testURL, session: tokenSession(access: "ra", refresh: "rr"), tokenStore: store)

        try await session.registerConfirm(email: "a@b.com", code: "123456")

        #expect(await session.tokenProvider() == "ra")
        #expect(store.loadRefresh() == "rr")
    }

    @Test func signInWithProviderStoresTokens() async throws {
        let store = InMemoryTokenStore()
        let session = AuthSession(baseURL: testURL, session: tokenSession(access: "pa", refresh: "pr"), tokenStore: store)

        try await session.signIn(provider: "apple", token: "identity", bodyKey: "identity_token")

        #expect(await session.isAuthenticated)
        #expect(store.loadAccess() == "pa")
    }

    // MARK: refresh

    @Test func refreshRotatesTokens() async throws {
        let store = InMemoryTokenStore(access: "old-acc", refresh: "old-ref")
        let session = AuthSession(baseURL: testURL, session: tokenSession(access: "new-acc", refresh: "new-ref"), tokenStore: store)

        let returned = try await session.refresh()

        #expect(returned == "new-acc")
        #expect(store.loadAccess() == "new-acc")
        #expect(store.loadRefresh() == "new-ref")
    }

    @Test func refreshWhenSignedOutThrowsNotAuthenticated() async {
        let session = AuthSession(baseURL: testURL, session: tokenSession(access: "x", refresh: "y"), tokenStore: InMemoryTokenStore())

        await #expect(throws: AuthError.self) {
            try await session.refresh()
        }
    }

    // MARK: signOut + restore

    @Test func signOutClearsEverything() async throws {
        let store = InMemoryTokenStore()
        let session = AuthSession(baseURL: testURL, session: tokenSession(access: "acc", refresh: "ref"), tokenStore: store)
        try await session.login(email: "a@b.com", password: "pw")

        await session.signOut()

        #expect(await session.isAuthenticated == false)
        #expect(await session.tokenProvider() == nil)
        #expect(store.loadAccess() == nil)
        #expect(store.loadRefresh() == nil)
    }

    @Test func initRestoresFromStore() async {
        let store = InMemoryTokenStore(access: "restored-a", refresh: "restored-r")
        let session = AuthSession(baseURL: testURL, session: tokenSession(access: "x", refresh: "y"), tokenStore: store)

        #expect(await session.isAuthenticated)
        #expect(await session.tokenProvider() == "restored-a")
    }

    // MARK: withRetry

    @Test func withRetryReturnsWithoutRefreshOnSuccess() async throws {
        let session = AuthSession(baseURL: testURL, session: tokenSession(access: "x", refresh: "y"), tokenStore: InMemoryTokenStore())

        let result = try await session.withRetry { 42 }
        #expect(result == 42)
    }

    @Test func withRetryRefreshesOnceThenRetries() async throws {
        // refresh endpoint returns new tokens; the operation throws .unauthorized
        // on its first call, succeeds on the retry.
        let store = InMemoryTokenStore(access: "old", refresh: "old-r")
        let session = AuthSession(baseURL: testURL, session: tokenSession(access: "fresh", refresh: "fresh-r"), tokenStore: store)

        let counter = Counter()
        let result = try await session.withRetry { () -> String in
            if counter.next() == 1 { throw ApiError.unauthorized }
            return "ok"
        }

        #expect(result == "ok")
        #expect(store.loadAccess() == "fresh")  // refresh ran
    }

    @Test func withRetryFailedRefreshThrowsUnauthorized() async {
        // operation always 401; refresh fails because no refresh token stored.
        let session = AuthSession(baseURL: testURL, session: tokenSession(access: "x", refresh: "y"), tokenStore: InMemoryTokenStore())

        await #expect(throws: ApiError.self) {
            try await session.withRetry { throw ApiError.unauthorized }
        }
    }

    @Test func withRetrySecondUnauthorizedPropagates() async {
        // valid refresh token so refresh succeeds, but operation 401s both times.
        let store = InMemoryTokenStore(access: "old", refresh: "old-r")
        let session = AuthSession(baseURL: testURL, session: tokenSession(access: "fresh", refresh: "fresh-r"), tokenStore: store)

        await #expect(throws: ApiError.self) {
            try await session.withRetry { throw ApiError.unauthorized }
        }
    }

    // MARK: no-data endpoints

    @Test func resetStartSucceedsOnZeroEnvelope() async throws {
        let session = AuthSession(
            baseURL: testURL,
            session: MockURLProtocol.makeSession { _ in (200, MockURLProtocol.envelope(code: 0)) },
            tokenStore: InMemoryTokenStore()
        )
        try await session.resetStart(email: "a@b.com")
    }

    @Test func resetStartThrowsBusinessOnErrorEnvelope() async {
        let session = AuthSession(
            baseURL: testURL,
            session: MockURLProtocol.makeSession { _ in (200, MockURLProtocol.envelope(code: 10002, message: "bad")) },
            tokenStore: InMemoryTokenStore()
        )

        await #expect(throws: ApiError.self) {
            try await session.resetStart(email: "a@b.com")
        }
    }
}
