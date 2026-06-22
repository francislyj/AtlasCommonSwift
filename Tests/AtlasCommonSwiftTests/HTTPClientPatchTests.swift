import Foundation
import Testing
@testable import AtlasCommonSwift

/// Verifies the PATCH verb reaches the wire as method "PATCH" and the response
/// envelope decodes. Mirrors the AuthCoreTests MockURLProtocol approach but kept
/// self-contained in this target.
@Suite struct HTTPClientPatchTests {
    private final class PatchMockProtocol: URLProtocol {
        struct Box: @unchecked Sendable {
            let lock = NSLock()
            var methods: [String: String] = [:]
            var counter = 0
        }
        nonisolated(unsafe) static var box = Box()

        static func makeSession() -> (URLSession, String) {
            box.lock.lock(); defer { box.lock.unlock() }
            box.counter += 1
            let id = "patch-\(box.counter)"
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [PatchMockProtocol.self]
            config.httpAdditionalHeaders = ["X-Mock-ID": id]
            return (URLSession(configuration: config), id)
        }

        static func capturedMethod(_ id: String) -> String? {
            box.lock.lock(); defer { box.lock.unlock() }
            return box.methods[id]
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}

        override func startLoading() {
            let id = request.value(forHTTPHeaderField: "X-Mock-ID") ?? ""
            PatchMockProtocol.box.lock.lock()
            PatchMockProtocol.box.methods[id] = request.httpMethod
            PatchMockProtocol.box.lock.unlock()

            let body = Data(#"{"code":0,"message":"ok","data":{"state":"green"}}"#.utf8)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private struct ReviewBody: Encodable, Sendable { let action: String }
    private struct ChunkLike: Decodable, Sendable { let state: String }

    @Test func patchSendsPatchMethodAndDecodesResponse() async throws {
        let (session, id) = PatchMockProtocol.makeSession()
        let client = HTTPClient(baseURL: URL(string: "https://example.test")!, session: session)

        let result: ChunkLike = try await client.patch(
            "/v1/chunks/1/review", body: ReviewBody(action: "got_it")
        )

        #expect(result.state == "green")
        #expect(PatchMockProtocol.capturedMethod(id) == "PATCH")
    }
}
