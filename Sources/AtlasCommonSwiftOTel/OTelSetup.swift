import Foundation
import AtlasCommonSwift
import OpenTelemetryApi
import OpenTelemetrySdk
import OpenTelemetryProtocolExporterCommon
import OpenTelemetryProtocolExporterHttp
#if os(iOS)
import UIKit
#endif

public enum OTelSetup: Sendable {
    nonisolated(unsafe) private static var tracerProvider: TracerProviderSdk?
    nonisolated(unsafe) private static var loggerProvider: LoggerProviderSdk?
    nonisolated(unsafe) private static var logBatchProcessor: BatchLogRecordProcessor?

    public static func configure(_ config: OTelConfig) {
        guard config.enabled else { return }

        tracerProvider?.forceFlush()
        logBatchProcessor?.forceFlush()

        let headers: [(String, String)]? = config.headers.isEmpty ? nil : config.headers.map { ($0.key, $0.value) }
        let resource = makeResource(config)

        let traceExporter = OtlpHttpTraceExporter(
            endpoint: config.endpoint.appendingPathComponent("v1/traces"),
            config: OtlpConfiguration(headers: headers)
        )

        let sampler = Samplers.parentBased(
            root: Samplers.traceIdRatio(ratio: config.sampleRate)
        )

        let traceProvider = TracerProviderBuilder()
            .add(spanProcessor: BatchSpanProcessor(spanExporter: traceExporter))
            .with(resource: resource)
            .with(sampler: sampler)
            .build()

        OpenTelemetry.registerTracerProvider(tracerProvider: traceProvider)
        tracerProvider = traceProvider

        let logExporter = OtlpHttpLogExporter(
            endpoint: config.endpoint.appendingPathComponent("v1/logs"),
            config: OtlpConfiguration(headers: headers)
        )

        let processor = BatchLogRecordProcessor(logRecordExporter: logExporter)

        let logProvider = LoggerProviderBuilder()
            .with(resource: resource)
            .with(processors: [processor])
            .build()

        OpenTelemetry.registerLoggerProvider(loggerProvider: logProvider)
        loggerProvider = logProvider
        logBatchProcessor = processor

        nonisolated(unsafe) let logger = logProvider.loggerBuilder(instrumentationScopeName: "AtlasCommonSwift").build()

        Log._otelEmit = { level, message in
            guard level == .warning || level == .error else { return }
            let severity: Severity = switch level {
            case .debug: .debug
            case .info: .info
            case .warning: .warn
            case .error: .error
            }
            logger.logRecordBuilder()
                .setSeverity(severity)
                .setBody(.string(message))
                .emit()
        }
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

        logBatchProcessor?.forceFlush()
        loggerProvider = nil
        logBatchProcessor = nil
        Log._otelEmit = nil
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
