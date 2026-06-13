import Foundation
import Testing
@testable import AtlasCommonSwift
@testable import AuthCore

private let testURL = URL(string: "https://auth.test")!

private struct DescribedError: LocalizedError {
    var errorDescription: String? { "described failure" }
}

private struct PlainError: Error {}

@MainActor
@Suite struct AuthControllerTests {

    private func makeController(
        store: InMemoryTokenStore = InMemoryTokenStore(),
        handler: @escaping @Sendable (URLRequest) -> (Int, Data) = { _ in (200, MockURLProtocol.tokenEnvelope(access: "a", refresh: "r")) }
    ) -> AuthController {
        let session = AuthSession(baseURL: testURL, session: MockURLProtocol.makeSession(handler), tokenStore: store)
        return AuthController(session: session, signInFailedMessage: "fallback")
    }

    @Test func runSuccessTogglesWorkingAndRefreshesAuth() async {
        let store = InMemoryTokenStore()
        let controller = makeController(store: store)

        await controller.run { try await controller.session.login(email: "a@b.com", password: "pw") }

        #expect(controller.isWorking == false)
        #expect(controller.isAuthenticated)
        #expect(controller.errorMessage == nil)
    }

    @Test func runSwallowsCancellation() async {
        let controller = makeController()
        await controller.run { throw AuthError.cancelled }
        #expect(controller.errorMessage == nil)
        #expect(controller.isAuthenticated == false)
    }

    @Test func runUsesErrorDescriptionWhenAvailable() async {
        let controller = makeController()
        await controller.run { throw DescribedError() }
        #expect(controller.errorMessage == "described failure")
    }

    @Test func runFallsBackForUndescribedError() async {
        let controller = makeController()
        await controller.run { throw PlainError() }
        #expect(controller.errorMessage == "fallback")
    }

    @Test func restoreReflectsSessionState() async {
        let controller = makeController(store: InMemoryTokenStore(access: "a", refresh: "r"))
        await controller.restore()
        #expect(controller.isAuthenticated)
    }

    @Test func loginFlowAuthenticates() async {
        let controller = makeController()
        await controller.login(email: "a@b.com", password: "pw")
        #expect(controller.isAuthenticated)
    }

    @Test func signOutClosesGate() async {
        let controller = makeController()
        await controller.login(email: "a@b.com", password: "pw")
        #expect(controller.isAuthenticated)

        await controller.signOut()
        #expect(controller.isAuthenticated == false)
    }
}
