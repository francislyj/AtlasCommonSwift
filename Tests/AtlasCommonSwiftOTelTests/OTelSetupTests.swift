import Foundation
import Testing
@testable import AtlasCommonSwiftOTel

@Test func configDisabledSkipsSetup() {
    let config = OTelConfig(
        enabled: false,
        endpoint: URL(string: "https://localhost:4318")!,
        serviceName: "test"
    )
    OTelSetup.configure(config)
}
