import Foundation

/// JWT pair returned by the backend `/v1/auth/*` endpoints. Mirrors the Go
/// `dto.TokenResponse`. Decoded via the shared snake_case strategy.
public struct TokenResponse: Decodable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresIn: Int64

    public init(accessToken: String, refreshToken: String, expiresIn: Int64) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
    }
}
