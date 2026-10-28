import Foundation
import Testing
@testable import AtlasCommonSwift
@testable import AuthCore

private actor Gate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private actor Barrier {
    private var count = 0
    private let total: Int
    private let gate = Gate()
    init(_ total: Int) { self.total = total }
    func arrive() async {
        count += 1
        if count == total { await gate.open() }
        await gate.wait()
    }
}

private actor RequestCount {
    private(set) var value = 0
    func increment() { value += 1 }
}

@Suite(.timeLimit(.minutes(1))) struct AuthSessionConcurrencyTests {
    private let url = URL(string: "https://auth.test")!

    @Test func refreshInFlightCannotRestoreSignedOutSession() async throws {
        let started = Gate(), release = Gate()
        let store = InMemoryTokenStore(access: "old", refresh: "old-r")
        let transport = MockURLProtocol.makeSession { request in
            if request.url?.path == "/v1/auth/refresh" {
                await started.open()
                await release.wait()
            }
            return (200, MockURLProtocol.tokenEnvelope(access: "late", refresh: "late-r"))
        }
        let session = AuthSession(baseURL: url, session: transport, tokenStore: store)
        let refreshing = Task { try await session.refresh() }
        await started.wait()
        await session.signOut()
        await release.open()
        if case .success = await refreshing.result { Issue.record("stale refresh succeeded") }
        #expect(await session.isAuthenticated == false)
        #expect(store.loadAccess() == nil)
        #expect(store.loadRefresh() == nil)
    }

    @Test func simultaneousUnauthorizedRequestsShareOneRefresh() async throws {
        let barrier = Barrier(16), requests = RequestCount()
        let transport = MockURLProtocol.makeSession { _ in
            await requests.increment()
            return (200, MockURLProtocol.tokenEnvelope(access: "fresh", refresh: "fresh-r"))
        }
        let session = AuthSession(baseURL: url, session: transport, tokenStore: InMemoryTokenStore(access: "old", refresh: "old-r"))
        try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    try await session.withRetry {
                        if await session.tokenProvider() == "old" {
                            await barrier.arrive()
                            throw ApiError.unauthorized
                        }
                        return "ok"
                    }
                }
            }
            for try await value in group { #expect(value == "ok") }
        }
        #expect(await requests.value == 1)
        #expect(await session.tokenProvider() == "fresh")
    }

    @Test func previousAccountSuccessfulResponseIsDiscarded() async throws {
        let started = Gate(), release = Gate()
        let transport = MockURLProtocol.makeSession { _ in
            (200, MockURLProtocol.tokenEnvelope(access: "account-b", refresh: "b-r"))
        }
        let session = AuthSession(baseURL: url, session: transport, tokenStore: InMemoryTokenStore(access: "account-a", refresh: "a-r"))
        let oldRequest = Task {
            try await session.withRetry {
                await started.open()
                await release.wait()
                return "private-a"
            }
        }
        await started.wait()
        try await session.login(email: "b@example.test", password: "password")
        await release.open()
        await #expect(throws: CancellationError.self) { try await oldRequest.value }
        #expect(await session.tokenProvider() == "account-b")
    }

    @Test func delayedLoginCannotUndoSignOut() async throws {
        let started = Gate(), release = Gate()
        let transport = MockURLProtocol.makeSession { _ in
            await started.open()
            await release.wait()
            return (200, MockURLProtocol.tokenEnvelope(access: "late", refresh: "late-r"))
        }
        let store = InMemoryTokenStore()
        let session = AuthSession(baseURL: url, session: transport, tokenStore: store)
        let login = Task { try await session.login(email: "a@example.test", password: "password") }
        await started.wait()
        await session.signOut()
        await release.open()
        await #expect(throws: CancellationError.self) { try await login.value }
        #expect(store.loadRefresh() == nil)
    }

    @Test func requestStartedDuringAccountSwitchIsAlsoDiscarded() async throws {
        let loginStarted = Gate(), loginRelease = Gate()
        let requestStarted = Gate(), requestRelease = Gate()
        let transport = MockURLProtocol.makeSession { _ in
            await loginStarted.open()
            await loginRelease.wait()
            return (200, MockURLProtocol.tokenEnvelope(access: "b", refresh: "b-r"))
        }
        let session = AuthSession(baseURL: url, session: transport, tokenStore: InMemoryTokenStore(access: "a", refresh: "a-r"))
        let login = Task { try await session.login(email: "b@example.test", password: "password") }
        await loginStarted.wait()
        let request = Task {
            try await session.withRetry {
                await requestStarted.open()
                await requestRelease.wait()
                return "private-a"
            }
        }
        await requestStarted.wait()
        await loginRelease.open()
        try await login.value
        await requestRelease.open()
        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(await session.tokenProvider() == "b")
    }

    @Test func refreshStartedDuringLoginDoesNotBlockNewAccountRefresh() async throws {
        let loginStarted = Gate(), loginRelease = Gate()
        let refreshStarted = Gate(), refreshRelease = Gate()
        let refreshRequests = RequestCount()
        let transport = MockURLProtocol.makeSession { request in
            if request.url?.path == "/v1/auth/login" {
                await loginStarted.open()
                await loginRelease.wait()
                return (200, MockURLProtocol.tokenEnvelope(access: "b", refresh: "b-r"))
            }
            await refreshRequests.increment()
            if await refreshRequests.value == 1 {
                await refreshStarted.open()
                await refreshRelease.wait()
                return (200, MockURLProtocol.tokenEnvelope(access: "stale-a", refresh: "stale-a-r"))
            }
            return (200, MockURLProtocol.tokenEnvelope(access: "fresh-b", refresh: "fresh-b-r"))
        }
        let store = InMemoryTokenStore(access: "a", refresh: "a-r")
        let session = AuthSession(baseURL: url, session: transport, tokenStore: store)
        let login = Task { try await session.login(email: "b@example.test", password: "password") }
        await loginStarted.wait()
        let oldRefresh = Task { try await session.refresh() }
        await refreshStarted.wait()
        await loginRelease.open()
        try await login.value
        await refreshRelease.open()
        if case .success = await oldRefresh.result { Issue.record("old account refresh succeeded") }
        #expect(store.loadAccess() == "b")
        #expect(store.loadRefresh() == "b-r")

        let refreshed = try await session.refresh()
        #expect(refreshed == "fresh-b")
        #expect(await refreshRequests.value == 2)
        #expect(await session.tokenProvider() == "fresh-b")
        #expect(store.loadRefresh() == "fresh-b-r")
    }
}
