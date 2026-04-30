import Foundation
import AtlasCommonSwift
import OpenTelemetryApi

public actor InstrumentedHTTPClient {
    private let inner: HTTPClient
    private let tracer: any Tracer

    public init(
        baseURL: URL,
        tokenProvider: (@Sendable () async -> String?)? = nil,
        session: URLSession = .shared,
        tracerName: String = "http.client"
    ) {
        self.inner = HTTPClient(baseURL: baseURL, tokenProvider: tokenProvider, session: session)
        self.tracer = OTelSetup.tracer(name: tracerName)
    }

    public func get<T: Decodable & Sendable>(
        _ path: String,
        query: [String: String]? = nil
    ) async throws -> T {
        try await traced("GET", path: path) { headers in
            try await self.inner.get(path, query: query, additionalHeaders: headers)
        }
    }

    public func post<T: Decodable & Sendable>(
        _ path: String,
        body: (any Encodable & Sendable)? = nil
    ) async throws -> T {
        try await traced("POST", path: path) { headers in
            try await self.inner.post(path, body: body, additionalHeaders: headers)
        }
    }

    public func put<T: Decodable & Sendable>(
        _ path: String,
        body: (any Encodable & Sendable)? = nil
    ) async throws -> T {
        try await traced("PUT", path: path) { headers in
            try await self.inner.put(path, body: body, additionalHeaders: headers)
        }
    }

    public func delete<T: Decodable & Sendable>(
        _ path: String
    ) async throws -> T {
        try await traced("DELETE", path: path) { headers in
            try await self.inner.delete(path, additionalHeaders: headers)
        }
    }

    private func traced<T>(
        _ method: String,
        path: String,
        operation: @Sendable ([String: String]) async throws -> T
    ) async rethrows -> T {
        let span = tracer.spanBuilder(spanName: "\(method) \(path)")
            .setSpanKind(spanKind: .client)
            .setAttribute(key: "http.request.method", value: method)
            .setAttribute(key: "url.path", value: path)
            .startSpan()
        defer { span.end() }

        let traceId = span.context.traceId.hexString
        let spanId = span.context.spanId.hexString
        let headers = ["traceparent": "00-\(traceId)-\(spanId)-01"]

        do {
            let result = try await operation(headers)
            span.status = .ok
            return result
        } catch {
            let message = error.localizedDescription
            span.status = .error(description: message)
            span.addEvent(
                name: "exception",
                attributes: ["exception.message": .string(message)]
            )
            throw error
        }
    }
}
