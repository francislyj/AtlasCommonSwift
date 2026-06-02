import AuthenticationServices
import AuthCore
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Drives the native Sign in with Apple flow and exchanges the resulting
/// identity token with the backend via `AuthSession`.
///
/// `@MainActor` because it touches `ASAuthorizationController` and provides the
/// presentation anchor, both of which are main-thread bound.
@MainActor
public final class AppleSignInController: NSObject {
    private let session: AuthSession
    private var continuation: CheckedContinuation<String, Error>?

    public init(session: AuthSession) {
        self.session = session
    }

    /// Presents the Apple sheet, verifies with the backend, and stores the
    /// resulting JWT pair. Throws `AuthError` on cancellation/failure.
    public func signIn() async throws {
        let identityToken = try await requestIdentityToken()
        try await session.signIn(
            provider: "apple",
            token: identityToken,
            bodyKey: "identity_token"
        )
    }

    private func requestIdentityToken() async throws -> String {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
}

extension AppleSignInController: ASAuthorizationControllerDelegate {
    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let token = String(data: tokenData, encoding: .utf8)
        else {
            continuation?.resume(throwing: AuthError.missingIdentityToken)
            continuation = nil
            return
        }
        continuation?.resume(returning: token)
        continuation = nil
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            continuation?.resume(throwing: AuthError.cancelled)
        } else {
            continuation?.resume(throwing: AuthError.provider(error))
        }
        continuation = nil
    }
}

extension AppleSignInController: ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if canImport(UIKit)
        // Prefer the active foreground window, but fall back to any existing
        // window so the sheet still presents during scene transitions (when no
        // scene is .foregroundActive). A bare ASPresentationAnchor() would be
        // off-screen and silently drop the presentation, hanging the flow.
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let scene = windowScenes.first { $0.activationState == .foregroundActive }
            ?? windowScenes.first
        let window = scene?.keyWindow ?? scene?.windows.first
        return window ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
