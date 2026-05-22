import os
import Foundation

public enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "AtlasCommonSwift"
    nonisolated(unsafe) private static var loggers: [String: os.Logger] = [:]

    private static func logger(category: String) -> os.Logger {
        if let cached = loggers[category] { return cached }
        let l = os.Logger(subsystem: subsystem, category: category)
        loggers[category] = l
        return l
    }

    public static func debug(_ message: String, category: String = "default") {
        logger(category: category).debug("\(message)")
    }

    public static func info(_ message: String, category: String = "default") {
        logger(category: category).info("\(message)")
    }

    public static func warning(_ message: String, category: String = "default") {
        logger(category: category).warning("\(message)")
    }

    public static func error(_ message: String, category: String = "default") {
        logger(category: category).error("\(message)")
    }
}
