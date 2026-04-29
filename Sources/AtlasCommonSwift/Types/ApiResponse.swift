import Foundation

public struct ApiResponse<T: Decodable & Sendable>: Decodable, Sendable {
    public let code: Int
    public let message: String
    public let data: T?

    public var isSuccess: Bool {
        code == ErrorCode.success.rawValue
    }
}

public enum ErrorCode: Int, Sendable {
    case success = 0
    case internalError = 10000
    case unauthorized = 10001
}
