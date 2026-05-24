import Foundation
import AtlasCommonSwift
#if os(iOS)
import UIKit
#endif

public enum LogUploader: Sendable {
    public struct LogEntry: Sendable {
        public let timestamp: Date
        public let level: String
        public let message: String
        public let category: String

        public init(timestamp: Date, level: String, message: String, category: String) {
            self.timestamp = timestamp
            self.level = level
            self.message = message
            self.category = category
        }
    }

    public enum UploadError: LocalizedError, Sendable {
        case notConfigured
        case pushFailed(statusCode: Int)

        public var errorDescription: String? {
            switch self {
            case .notConfigured: "LogUploader not configured"
            case .pushFailed(let code): "Log upload failed (HTTP \(code))"
            }
        }
    }

    nonisolated(unsafe) private static var config: OTelConfig?
    nonisolated(unsafe) private static var context: [String: String] = [:]

    public static func configure(_ config: OTelConfig) {
        self.config = config
    }

    public static func setContext(_ attributes: [String: String]) {
        self.context = attributes
    }

    public static func upload(entries: [LogEntry]) async throws {
        guard let config, config.enabled else { throw UploadError.notConfigured }

        let logRecords: [[String: Any]] = entries.map { entry in
            let nanos = String(Int(entry.timestamp.timeIntervalSince1970 * 1_000_000_000))
            let (cleanMessage, traceId) = extractTraceId(from: entry.message)

            var attributes: [[String: Any]] = [
                makeAttribute(key: "category", stringValue: entry.category),
                makeAttribute(key: "severity_number", intValue: severityNumber(for: entry.level)),
            ]
            if let traceId {
                attributes.append(makeAttribute(key: "trace_id", stringValue: traceId))
            }

            return [
                "timeUnixNano": nanos,
                "severityText": entry.level,
                "body": ["stringValue": cleanMessage],
                "attributes": attributes,
            ] as [String: Any]
        }

        let body: [String: Any] = [
            "resourceLogs": [[
                "resource": ["attributes": resourceAttributes(config)],
                "scopeLogs": [["logRecords": logRecords]],
            ]],
        ]

        let url = config.endpoint.appendingPathComponent("v1/logs")
        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in config.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            Log.error("LogUploader push failed: HTTP \(code), body=\(responseBody)", category: "LogUploader")
            throw UploadError.pushFailed(statusCode: code)
        }
    }

    private static let traceIdRegex = try! NSRegularExpression(pattern: #"\[trace:([a-f0-9]+)\] "#)

    private static func extractTraceId(from message: String) -> (String, String?) {
        let nsRange = NSRange(message.startIndex..., in: message)
        guard let match = traceIdRegex.firstMatch(in: message, range: nsRange) else {
            return (message, nil)
        }
        let traceId = String(message[Range(match.range(at: 1), in: message)!])
        let clean = message.replacingCharacters(in: Range(match.range, in: message)!, with: "")
        return (clean, traceId)
    }

    private static func severityNumber(for level: String) -> Int {
        switch level {
        case "DEBUG": 5
        case "INFO", "NOTICE": 9
        case "WARNING": 13
        case "ERROR": 17
        case "FAULT": 21
        default: 0
        }
    }

    private static func makeAttribute(key: String, stringValue: String) -> [String: Any] {
        ["key": key, "value": ["stringValue": stringValue]]
    }

    private static func makeAttribute(key: String, intValue: Int) -> [String: Any] {
        ["key": key, "value": ["intValue": intValue]]
    }

    private static func resourceAttributes(_ config: OTelConfig) -> [[String: Any]] {
        var attrs: [[String: Any]] = [
            makeAttribute(key: "service.name", stringValue: config.serviceName),
            makeAttribute(key: "service.version", stringValue: config.serviceVersion),
            makeAttribute(key: "deployment.environment", stringValue: config.environment),
            makeAttribute(key: "source", stringValue: "manual-upload"),
        ]

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        attrs.append(makeAttribute(key: "app.version", stringValue: appVersion))

        for (key, value) in context {
            attrs.append(makeAttribute(key: key, stringValue: value))
        }

        #if os(iOS)
        let device = UIDevice.current
        attrs.append(makeAttribute(key: "os.name", stringValue: "iOS"))
        attrs.append(makeAttribute(key: "os.version", stringValue: device.systemVersion))
        attrs.append(makeAttribute(key: "device.model", stringValue: device.model))
        #endif

        return attrs
    }
}
