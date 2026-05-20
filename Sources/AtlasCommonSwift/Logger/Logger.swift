import os
import Foundation

public enum Log {
    public enum Level: Sendable {
        case debug, info, warning, error
    }

    nonisolated(unsafe) package static var _otelEmit: (@Sendable (Level, String) -> Void)?

    private static let logger = os.Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "AtlasCommonSwift",
        category: "default"
    )

    public static func debug(_ message: String) {
        logger.debug("\(message)")
        _otelEmit?(.debug, message)
    }

    public static func info(_ message: String) {
        logger.info("\(message)")
        _otelEmit?(.info, message)
    }

    public static func warning(_ message: String) {
        logger.warning("\(message)")
        _otelEmit?(.warning, message)
    }

    public static func error(_ message: String) {
        logger.error("\(message)")
        _otelEmit?(.error, message)
    }
}
