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
        .library(
            name: "AuthCore",
            targets: ["AuthCore"]
        ),
        .library(
            name: "AtlasCommonSwiftAuthApple",
            targets: ["AtlasCommonSwiftAuthApple"]
        ),
        .library(
            name: "AtlasCommonSwiftAuthGoogle",
            targets: ["AtlasCommonSwiftAuthGoogle"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.3.0"),
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift.git", from: "2.3.0"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", from: "3.58.0"),
        .package(url: "https://github.com/google/GoogleSignIn-iOS.git", from: "8.0.0"),
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
        .target(
            name: "AuthCore",
            dependencies: ["AtlasCommonSwift"]
        ),
        .target(
            name: "AtlasCommonSwiftAuthApple",
            dependencies: ["AtlasCommonSwift", "AuthCore"]
        ),
        .target(
            name: "AtlasCommonSwiftAuthGoogle",
            dependencies: [
                "AtlasCommonSwift",
                "AuthCore",
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
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
        .testTarget(
            name: "AuthCoreTests",
            dependencies: ["AuthCore", "AtlasCommonSwift"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
