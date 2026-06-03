import Combine
import Foundation

/// Reusable auth view-state machine for SwiftUI apps. Owns the published gate
/// state and the run/restore/signOut plumbing; products subclass it to add
/// provider-specific sign-in methods (which live in the AuthApple/AuthGoogle
/// products, kept out of AuthCore to preserve the zero-provider-dependency split).
///
/// Subclass usage:
/// ```swift
/// final class AuthState: AuthController {
///     func signInWithApple() async { await run { try await self.apple.signIn() } }
/// }
/// ```
@MainActor
open class AuthController: ObservableObject {
    @Published public private(set) var isAuthenticated = false
    @Published public private(set) var isWorking = false
    @Published public var errorMessage: String?

    public let session: AuthSession
    private let signInFailedMessage: String

    /// - Parameters:
    ///   - session: the shared token source.
    ///   - signInFailedMessage: localized fallback shown when a sign-in flow
    ///     fails with a non-cancellation error that has no `errorDescription`.
    public init(session: AuthSession, signInFailedMessage: String = "Sign-in failed, please try again.") {
        self.session = session
        self.signInFailedMessage = signInFailedMessage
    }

    /// Restores authentication state from the Keychain at launch.
    public func restore() async {
        isAuthenticated = await session.isAuthenticated
    }

    /// Clears tokens and flips the gate closed.
    public func signOut() async {
        await session.signOut()
        isAuthenticated = false
    }

    public func registerStart(email: String, password: String) async {
        await run { try await self.session.registerStart(email: email, password: password) }
    }
    public func registerConfirm(email: String, code: String) async {
        await run { try await self.session.registerConfirm(email: email, code: code) }
    }
    public func login(email: String, password: String) async {
        await run { try await self.session.login(email: email, password: password) }
    }
    public func resetStart(email: String) async {
        await run { try await self.session.resetStart(email: email) }
    }
    public func resetConfirm(email: String, code: String, newPassword: String) async {
        await run { try await self.session.resetConfirm(email: email, code: code, newPassword: newPassword) }
    }

    /// Runs a sign-in flow with `isWorking` toggling, swallowing
    /// `AuthError.cancelled`, mapping other errors to `errorMessage`, and
    /// refreshing `isAuthenticated` afterward. Public so product subclasses can
    /// wrap their provider-specific flows.
    public func run(_ flow: @MainActor () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await flow()
            isAuthenticated = await session.isAuthenticated
        } catch AuthError.cancelled {
            // User backed out — not an error worth surfacing.
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? signInFailedMessage
        }
    }
}
