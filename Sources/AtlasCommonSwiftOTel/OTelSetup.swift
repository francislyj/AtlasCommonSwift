import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import OpenTelemetryProtocolExporterCommon
import OpenTelemetryProtocolExporterHttp
#if os(iOS)
import UIKit
#endif

public enum OTelSetup: Sendable {
    nonisolated(unsafe) private static var tracerProvider: TracerProviderSdk?

    public static func configure(_ config: OTelConfig) {
        guard config.enabled else { return }

        tracerProvider?.forceFlush()

        let headers: [(String, String)]? = config.headers.isEmpty ? nil : config.headers.map { ($0.key, $0.value) }
        let resource = makeResource(config)

        let exporter = OtlpHttpTraceExporter(
            endpoint: config.endpoint.appendingPathComponent("v1/traces"),
            config: OtlpConfiguration(headers: headers)
        )

        let sampler = Samplers.parentBased(
            root: Samplers.traceIdRatio(ratio: config.sampleRate)
        )

        let provider = TracerProviderBuilder()
            .add(spanProcessor: BatchSpanProcessor(spanExporter: exporter))
            .with(resource: resource)
            .with(sampler: sampler)
            .build()

        OpenTelemetry.registerTracerProvider(tracerProvider: provider)
        tracerProvider = provider
    }

    public static func tracer(name: String = "AtlasCommonSwift") -> any Tracer {
        OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: name,
            instrumentationVersion: nil
        )
    }

    public static func shutdown() {
        tracerProvider?.forceFlush()
        tracerProvider = nil
    }

    private static func makeResource(_ config: OTelConfig) -> Resource {
        var attributes: [String: AttributeValue] = [
            "service.name": .string(config.serviceName),
            "service.version": .string(config.serviceVersion),
            "deployment.environment": .string(config.environment),
        ]

        #if os(iOS)
        let device = UIDevice.current
        attributes["os.name"] = .string("iOS")
        attributes["os.version"] = .string(device.systemVersion)
        attributes["device.model"] = .string(device.model)
        #endif

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        attributes["app.version"] = .string(appVersion)

        return Resource(attributes: attributes)
    }
}
