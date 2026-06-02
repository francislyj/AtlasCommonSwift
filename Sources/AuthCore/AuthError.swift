import Foundation

/// Errors surfaced by the auth flow, distinct from transport-level `ApiError`.
public enum AuthError: Error, Sendable {
    /// The provider flow was cancelled by the user.
    case cancelled
    /// The provider returned no usable identity/ID token.
    case missingIdentityToken
    /// No stored credentials (e.g. refresh attempted while signed out).
    case notAuthenticated
    /// The underlying provider SDK or system framework failed.
    case provider(any Error)
}
