import Foundation
import AtlasCommonSwift
import PostHog

public enum Analytics: Sendable {
    public struct Config: Sendable {
        public let enabled: Bool
        public let projectToken: String
        public let host: String

        public init(enabled: Bool = true, projectToken: String, host: String = "https://us.i.posthog.com") {
            self.enabled = enabled
            self.projectToken = projectToken
            self.host = host
        }
    }

    nonisolated(unsafe) private static var isConfigured = false

    public static func configure(_ config: Config) {
        guard config.enabled, !isConfigured else { return }

        let phConfig = PostHogConfig(projectToken: config.projectToken, host: config.host)
        phConfig.captureApplicationLifecycleEvents = true
        phConfig.captureScreenViews = true
        #if DEBUG
        phConfig.debug = true
        #endif
        PostHogSDK.shared.setup(phConfig)

        isConfigured = true
        Log.info("Analytics configured", category: "Analytics")
    }

    public static func identify(_ userId: String, properties: [String: Any]? = nil) {
        guard isConfigured else { return }
        PostHogSDK.shared.identify(userId, userProperties: properties)
    }

    public static func capture(_ event: String, properties: [String: Any]? = nil) {
        guard isConfigured else { return }
        PostHogSDK.shared.capture(event, properties: properties)
    }

    public static func screen(_ name: String, properties: [String: Any]? = nil) {
        guard isConfigured else { return }
        PostHogSDK.shared.screen(name, properties: properties)
    }

    public static func reset() {
        guard isConfigured else { return }
        PostHogSDK.shared.reset()
    }
}
