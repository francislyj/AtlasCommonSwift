import Foundation

public enum ApiError: Error, Sendable {
    case network(any Error)
    case decoding(any Error)
    case business(code: Int, message: String)
    case unauthorized
    case unknown
}

extension ApiError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .network(let e): "Network error: \(e.localizedDescription)"
        case .decoding(let e): "Failed to parse response: \(e.localizedDescription)"
        case .business(_, let message): message
        case .unauthorized: "Unauthorized"
        case .unknown: "Unknown error"
        }
    }
}
