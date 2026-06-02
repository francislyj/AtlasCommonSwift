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
    private var accessToken: String?
    private var refreshToken: String?

    /// - Parameter baseURL: the backend base URL (same host the app's API uses).
    public init(baseURL: URL, session: URLSession = .shared) {
        self.client = HTTPClient(baseURL: baseURL, session: session)
        // Restore from Keychain so a relaunch stays signed in.
        self.accessToken = TokenStore.loadAccess()
        self.refreshToken = TokenStore.loadRefresh()
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

    /// Clears tokens from memory and Keychain.
    public func signOut() {
        accessToken = nil
        refreshToken = nil
        TokenStore.clear()
    }

    private func store(_ tokens: TokenResponse) {
        accessToken = tokens.accessToken
        refreshToken = tokens.refreshToken
        TokenStore.save(tokens)
    }
}
