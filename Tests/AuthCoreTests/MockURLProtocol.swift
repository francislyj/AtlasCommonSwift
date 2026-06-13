import Foundation

/// URLProtocol that serves canned responses, so `AuthSession`'s HTTPClient never
/// hits the network. Handlers are registered per-session and routed by a unique
/// `X-Mock-ID` header, so parallel tests (swift-testing's default) never share or
/// stomp on each other's handler.
final class MockURLProtocol: URLProtocol {
    private struct Registry: @unchecked Sendable {
        let lock = NSLock()
        var handlers: [String: @Sendable (URLRequest) -> (Int, Data)] = [:]
        var counter = 0
    }
    nonisolated(unsafe) private static var registry = Registry()

    private static func register(_ handler: @escaping @Sendable (URLRequest) -> (Int, Data)) -> String {
        registry.lock.lock(); defer { registry.lock.unlock() }
        registry.counter += 1
        let id = "mock-\(registry.counter)"
        registry.handlers[id] = handler
        return id
    }

    private static func handler(for id: String) -> (@Sendable (URLRequest) -> (Int, Data))? {
        registry.lock.lock(); defer { registry.lock.unlock() }
        return registry.handlers[id]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-Mock-ID") ?? ""
        guard let handler = MockURLProtocol.handler(for: id) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// A URLSession wired to this protocol, serving the given handler. Each call
    /// gets its own id so concurrent tests never interfere.
    static func makeSession(_ handler: @escaping @Sendable (URLRequest) -> (Int, Data)) -> URLSession {
        let id = register(handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Mock-ID": id]
        return URLSession(configuration: config)
    }

    /// An envelope `{code,message,data}` body.
    static func envelope(code: Int, message: String = "ok", dataJSON: String = "null") -> Data {
        Data(#"{"code":\#(code),"message":"\#(message)","data":\#(dataJSON)}"#.utf8)
    }

    /// A success envelope wrapping a TokenResponse.
    static func tokenEnvelope(access: String, refresh: String, expiresIn: Int = 3600) -> Data {
        let data = #"{"access_token":"\#(access)","refresh_token":"\#(refresh)","expires_in":\#(expiresIn)}"#
        return envelope(code: 0, dataJSON: data)
    }
}
