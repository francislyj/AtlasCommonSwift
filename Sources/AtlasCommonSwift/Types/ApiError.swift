import Foundation

public enum ApiError: Error, Sendable {
    case network(any Error)
    case decoding(any Error)
    case business(code: Int, message: String)
    case unauthorized
    case unknown
}
