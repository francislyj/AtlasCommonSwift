import Foundation
import GoogleSignIn

/// App-level entry points for Google Sign-In setup and OAuth redirect handling.
/// Exposed here so consuming apps don't import the GoogleSignIn SDK directly.
public enum GoogleAuth {
    /// Sets the OAuth client ID. Call once at launch before any sign-in.
    @MainActor
    public static func configure(clientID: String) {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    /// Forwards an incoming OAuth redirect URL to the SDK. Wire to
    /// SwiftUI's `.onOpenURL`. Returns true if the SDK handled it.
    @MainActor
    @discardableResult
    public static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
}
