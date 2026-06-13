import AtlasCommonSwift
import Foundation

/// AuthSession is the single source of truth for the current user's tokens.
///
/// It is an `actor` because it holds mutable token state accessed concurrently
/// from request paths and UI callbacks. It owns an unauthenticated `HTTPClient`
/// pointed at the auth endpoints (token issuance must not require a token), and
/// exposes `tokenProvider` — a `@Sendable` closure the app's main API client
/// passes to its own `HTTPClient`/`InstrumentedHTTPClient` so every request
/// carries the current access token.
public actor AuthSession {
    private let client: HTTPClient
    private let tokenStore: TokenStoring
    private var accessToken: String?
    private var refreshToken: String?

    /// - Parameters:
    ///   - baseURL: the backend base URL (same host the app's API uses).
    ///   - session: URLSession used for auth endpoints (override in tests).
    ///   - tokenStore: persistence for the JWT pair; defaults to the Keychain.
    public init(
        baseURL: URL,
        session: URLSession = .shared,
        tokenStore: TokenStoring? = nil
    ) {
        let store = tokenStore ?? KeychainTokenStore()
        self.client = HTTPClient(baseURL: baseURL, session: session)
        self.tokenStore = store
        // Restore from the store so a relaunch stays signed in.
        self.accessToken = store.loadAccess()
        self.refreshToken = store.loadRefresh()
    }

    /// True if a refresh token is present (i.e. previously signed in).
    public var isAuthenticated: Bool { refreshToken != nil }

    /// A `@Sendable` closure for the app's API client `tokenProvider`. Returns
    /// the current access token (or nil when signed out).
    public nonisolated var tokenProvider: @Sendable () async -> String? {
        { [weak self] in await self?.currentAccessToken() }
    }

    private func currentAccessToken() -> String? { accessToken }

    /// Exchanges a verified provider token for a JWT pair at `/v1/auth/{provider}`.
    /// `bodyKey` is the JSON field the backend expects ("identity_token" for
    /// Apple, "id_token" for Google).
    public func signIn(provider: String, token: String, bodyKey: String) async throws {
        let body = [bodyKey: token]
        let tokens: TokenResponse = try await client.post("/v1/auth/\(provider)", body: body)
        store(tokens)
    }

    /// Rotates the refresh token into a new pair. Throws `.notAuthenticated`
    /// when signed out.
    @discardableResult
    public func refresh() async throws -> String {
        guard let current = refreshToken else { throw AuthError.notAuthenticated }
        let tokens: TokenResponse = try await client.post(
            "/v1/auth/refresh",
            body: ["refresh_token": current]
        )
        store(tokens)
        return tokens.accessToken
    }

    /// Starts email/password registration: backend emails a 6-digit code.
    public func registerStart(email: String, password: String) async throws {
        try await client.postExpectingNoData(
            "/v1/auth/register/start",
            body: ["email": email, "password": password]
        )
    }

    /// Confirms registration with the emailed code; stores the issued JWT pair.
    public func registerConfirm(email: String, code: String) async throws {
        let tokens: TokenResponse = try await client.post(
            "/v1/auth/register/confirm",
            body: ["email": email, "code": code]
        )
        store(tokens)
    }

    /// Email/password login; stores the issued JWT pair.
    public func login(email: String, password: String) async throws {
        let tokens: TokenResponse = try await client.post(
            "/v1/auth/login",
            body: ["email": email, "password": password]
        )
        store(tokens)
    }

    /// Starts a password reset: backend emails a 6-digit code.
    public func resetStart(email: String) async throws {
        try await client.postExpectingNoData("/v1/auth/reset/start", body: ["email": email])
    }

    /// Completes a password reset with the emailed code + new password.
    public func resetConfirm(email: String, code: String, newPassword: String) async throws {
        try await client.postExpectingNoData(
            "/v1/auth/reset/confirm",
            body: ["email": email, "code": code, "new_password": newPassword]
        )
    }

    /// Clears tokens from memory and Keychain.
    public func signOut() {
        accessToken = nil
        refreshToken = nil
        tokenStore.clear()
    }

    /// Runs an authenticated request; on `ApiError.unauthorized` it refreshes the
    /// token once and retries. A second 401 (or a failed refresh) propagates as
    /// `.unauthorized` so the caller can drive the user back to the login gate.
    ///
    /// `operation` is intentionally not `@Sendable` so it inherits the caller's
    /// isolation (required under MainActor-default concurrency, where request
    /// bodies may be MainActor-isolated).
    public func withRetry<T: Sendable>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch ApiError.unauthorized {
            do {
                _ = try await refresh()
            } catch {
                throw ApiError.unauthorized
            }
            return try await operation()
        }
    }

    private func store(_ tokens: TokenResponse) {
        accessToken = tokens.accessToken
        refreshToken = tokens.refreshToken
        tokenStore.save(tokens)
    }
}
