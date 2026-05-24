// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AtlasCommonSwift",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(
            name: "AtlasCommonSwift",
            targets: ["AtlasCommonSwift"]
        ),
        .library(
            name: "AtlasCommonSwiftOTel",
            targets: ["AtlasCommonSwiftOTel"]
        ),
        .library(
            name: "AtlasCommonSwiftAnalytics",
            targets: ["AtlasCommonSwiftAnalytics"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.3.0"),
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift.git", from: "2.3.0"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", from: "3.58.0"),
    ],
    targets: [
        .target(
            name: "AtlasCommonSwift"
        ),
        .target(
            name: "AtlasCommonSwiftOTel",
            dependencies: [
                "AtlasCommonSwift",
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
                .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
                .product(name: "OpenTelemetryProtocolExporterHTTP", package: "opentelemetry-swift"),
            ]
        ),
        .target(
            name: "AtlasCommonSwiftAnalytics",
            dependencies: [
                "AtlasCommonSwift",
                .product(name: "PostHog", package: "posthog-ios"),
            ]
        ),
        .testTarget(
            name: "AtlasCommonSwiftTests",
            dependencies: ["AtlasCommonSwift"]
        ),
        .testTarget(
            name: "AtlasCommonSwiftOTelTests",
            dependencies: ["AtlasCommonSwiftOTel"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
