import os
import Foundation

public enum Log {
    private static let logger = os.Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "AtlasCommonSwift",
        category: "default"
    )

    public static func debug(_ message: String) {
        logger.debug("\(message)")
    }

    public static func info(_ message: String) {
        logger.info("\(message)")
    }

    public static func warning(_ message: String) {
        logger.warning("\(message)")
    }

    public static func error(_ message: String) {
        logger.error("\(message)")
    }
}
