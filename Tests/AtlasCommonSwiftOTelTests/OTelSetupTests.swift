import Foundation
import Testing
@testable import AtlasCommonSwift
@testable import AtlasCommonSwiftOTel

@Suite(.serialized) struct OTelSetupTests {
    @Test func configDisabledDoesNotInstallLogBridge() {
        OTelSetup.shutdown()
        let config = OTelConfig(
            enabled: false,
            endpoint: URL(string: "https://localhost:4318")!,
            serviceName: "test"
        )
        OTelSetup.configure(config)
        #expect(Log._otelEmit == nil)
    }

    @Test func configEnabledInstallsLogBridge() {
        OTelSetup.shutdown()
        let config = OTelConfig(
            endpoint: URL(string: "https://localhost:4318")!,
            serviceName: "test"
        )
        OTelSetup.configure(config)
        #expect(Log._otelEmit != nil)

        let hook = Log._otelEmit!
        hook(.info, "test message")
        OTelSetup.shutdown()
        #expect(Log._otelEmit == nil)
    }
}
