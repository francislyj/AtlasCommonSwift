import Foundation

public actor HTTPClient {
    private let baseURL: URL
    private let tokenProvider: (@Sendable () async -> String?)?
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(
        baseURL: URL,
        tokenProvider: (@Sendable () async -> String?)? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder = JSONEncoder()
    }

    public func get<T: Decodable & Sendable>(
        _ path: String,
        query: [String: String]? = nil
    ) async throws -> T {
        try await request(path, method: .get, query: query)
    }

    public func post<T: Decodable & Sendable>(
        _ path: String,
        body: (any Encodable & Sendable)? = nil
    ) async throws -> T {
        try await request(path, method: .post, body: body)
    }

    public func put<T: Decodable & Sendable>(
        _ path: String,
        body: (any Encodable & Sendable)? = nil
    ) async throws -> T {
        try await request(path, method: .put, body: body)
    }

    public func delete<T: Decodable & Sendable>(
        _ path: String
    ) async throws -> T {
        try await request(path, method: .delete)
    }

    private func request<T: Decodable & Sendable>(
        _ path: String,
        method: HTTPMethod,
        query: [String: String]? = nil,
        body: (any Encodable & Sendable)? = nil
    ) async throws -> T {
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw ApiError.business(code: -1, message: "Invalid URL: \(path)")
        }
        if let query, !query.isEmpty {
            urlComponents.queryItems = query.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = urlComponents.url else {
            throw ApiError.business(code: -1, message: "Invalid URL: \(path)")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = await tokenProvider?() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            urlRequest.httpBody = try encoder.encode(body)
        }

        let data: Data
        do {
            let (responseData, _) = try await session.data(for: urlRequest)
            data = responseData
        } catch {
            throw ApiError.network(error)
        }

        let apiResponse: ApiResponse<T>
        do {
            apiResponse = try decoder.decode(ApiResponse<T>.self, from: data)
        } catch {
            throw ApiError.decoding(error)
        }

        if apiResponse.code == ErrorCode.unauthorized.rawValue {
            throw ApiError.unauthorized
        }

        guard apiResponse.isSuccess else {
            throw ApiError.business(code: apiResponse.code, message: apiResponse.message)
        }

        guard let result = apiResponse.data else {
            throw ApiError.business(code: apiResponse.code, message: "Response data is nil")
        }

        return result
    }
}
