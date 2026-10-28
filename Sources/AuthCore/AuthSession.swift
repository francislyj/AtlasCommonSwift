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
    private var generation: UInt64 = 0
    private var refreshTask: Task<String, Error>?

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
        let epoch = beginAuthentication()
        let tokens: TokenResponse = try await client.post("/v1/auth/\(provider)", body: body)
        try completeAuthentication(tokens, epoch: epoch)
    }

    /// Rotates the refresh token into a new pair. Throws `.notAuthenticated`
    /// when signed out.
    @discardableResult
    public func refresh() async throws -> String {
        if let task = refreshTask { return try await task.value }
        guard let current = refreshToken else { throw AuthError.notAuthenticated }
        let epoch = generation
        let task = Task { [client] in
            let tokens: TokenResponse = try await client.post(
                "/v1/auth/refresh", body: ["refresh_token": current]
            )
            try Task.checkCancellation()
            guard epoch == self.generation else { throw CancellationError() }
            self.store(tokens)
            return tokens.accessToken
        }
        refreshTask = task
        defer { if generation == epoch { refreshTask = nil } }
        return try await task.value
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
        let epoch = beginAuthentication()
        let tokens: TokenResponse = try await client.post(
            "/v1/auth/register/confirm",
            body: ["email": email, "code": code]
        )
        try completeAuthentication(tokens, epoch: epoch)
    }

    /// Email/password login; stores the issued JWT pair.
    public func login(email: String, password: String) async throws {
        let epoch = beginAuthentication()
        let tokens: TokenResponse = try await client.post(
            "/v1/auth/login",
            body: ["email": email, "password": password]
        )
        try completeAuthentication(tokens, epoch: epoch)
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
        let previousRefresh = refreshToken
        generation &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        accessToken = nil
        refreshToken = nil
        tokenStore.clear()
        // Local logout is immediate even offline. The server enforces absolute
        // session expiry; this best-effort request revokes the current session.
        if let previousRefresh {
            Task { [client] in
                try? await client.postExpectingNoData("/v1/auth/logout", body: ["refresh_token": previousRefresh])
            }
        }
    }

    /// Runs an authenticated request; on `ApiError.unauthorized` it refreshes the
    /// token once and retries. Invalid credentials propagate as `.unauthorized`;
    /// temporary network failures retain their original error for retry UI.
    ///
    /// `operation` is intentionally not `@Sendable` so it inherits the caller's
    /// isolation (required under MainActor-default concurrency, where request
    /// bodies may be MainActor-isolated).
    public func withRetry<T: Sendable>(_ operation: () async throws -> T) async throws -> T {
        let epoch = generation
        let originalAccess = accessToken
        do {
            let result = try await operation()
            guard epoch == generation else { throw CancellationError() }
            return result
        } catch ApiError.unauthorized {
            guard epoch == generation else { throw CancellationError() }
            // Another request may already have refreshed while this one was
            // awaiting its 401. Reuse that result instead of rotating again.
            if accessToken == originalAccess {
                do { _ = try await refresh() }
                catch {
                    guard epoch == generation else { throw CancellationError() }
                    if error is CancellationError { throw error }
                    if case ApiError.unauthorized = error { throw ApiError.unauthorized }
                    if case AuthError.notAuthenticated = error { throw ApiError.unauthorized }
                    throw error // a temporary network failure is not a logout
                }
            }
            guard epoch == generation else { throw CancellationError() }
            let result = try await operation()
            guard epoch == generation else { throw CancellationError() }
            return result
        }
    }

    private func beginAuthentication() -> UInt64 {
        generation &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        return generation
    }

    private func completeAuthentication(_ tokens: TokenResponse, epoch: UInt64) throws {
        guard epoch == generation else { throw CancellationError() }
        // Also invalidate requests started during the login await, while the
        // previous account's tokens were still present.
        generation &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        store(tokens)
    }

    private func store(_ tokens: TokenResponse) {
        accessToken = tokens.accessToken
        refreshToken = tokens.refreshToken
        tokenStore.save(tokens)
    }
}
