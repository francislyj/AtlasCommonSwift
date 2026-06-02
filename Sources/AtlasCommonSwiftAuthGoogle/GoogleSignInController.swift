import AuthCore
import Foundation
import GoogleSignIn
#if canImport(UIKit)
import UIKit
#endif

/// Drives the Google Sign-In flow and exchanges the resulting ID token with the
/// backend via `AuthSession`.
///
/// `@MainActor` because GoogleSignIn requires a presenting view controller and
/// must be invoked from the main thread.
@MainActor
public final class GoogleSignInController {
    private let session: AuthSession

    public init(session: AuthSession) {
        self.session = session
    }

    /// Presents the Google flow, verifies the ID token with the backend, and
    /// stores the resulting JWT pair. Throws `AuthError` on cancellation/failure.
    public func signIn() async throws {
        let idToken = try await requestIDToken()
        try await session.signIn(
            provider: "google",
            token: idToken,
            bodyKey: "id_token"
        )
    }

    private func requestIDToken() async throws -> String {
        #if canImport(UIKit)
        guard let presenter = Self.topViewController() else {
            throw AuthError.provider(GoogleSignInError.noPresenter)
        }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthError.missingIdentityToken
            }
            return idToken
        } catch let error as GIDSignInError where error.code == .canceled {
            throw AuthError.cancelled
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.provider(error)
        }
        #else
        throw AuthError.provider(GoogleSignInError.unsupportedPlatform)
        #endif
    }

    #if canImport(UIKit)
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
    #endif
}

enum GoogleSignInError: Error {
    case noPresenter
    case unsupportedPlatform
}
