import Testing
@testable import AuthCore

@Suite struct TokenStoringTests {
    @Test func inMemoryStoreRoundTrips() {
        let store = InMemoryTokenStore()
        #expect(store.loadAccess() == nil)
        #expect(store.loadRefresh() == nil)

        store.save(TokenResponse(accessToken: "a1", refreshToken: "r1", expiresIn: 3600))
        #expect(store.loadAccess() == "a1")
        #expect(store.loadRefresh() == "r1")

        store.clear()
        #expect(store.loadAccess() == nil)
        #expect(store.loadRefresh() == nil)
    }

    @Test func inMemoryStoreSeedsFromInit() {
        let store = InMemoryTokenStore(access: "seed-a", refresh: "seed-r")
        #expect(store.loadAccess() == "seed-a")
        #expect(store.loadRefresh() == "seed-r")
    }
}
