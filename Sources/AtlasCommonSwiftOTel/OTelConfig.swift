import Foundation

public struct OTelConfig: Sendable {
    public let enabled: Bool
    public let endpoint: URL
    public let headers: [String: String]
    public let serviceName: String
    public let serviceVersion: String
    public let environment: String
    public let sampleRate: Double

    public init(
        enabled: Bool = true,
        endpoint: URL,
        headers: [String: String] = [:],
        serviceName: String,
        serviceVersion: String = "0.0.0",
        environment: String = "development",
        sampleRate: Double = 1.0
    ) {
        self.enabled = enabled
        self.endpoint = endpoint
        self.headers = headers
        self.serviceName = serviceName
        self.serviceVersion = serviceVersion
        self.environment = environment
        self.sampleRate = sampleRate
    }
}
