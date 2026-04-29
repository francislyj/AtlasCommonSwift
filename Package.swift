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
    ],
    targets: [
        .target(
            name: "AtlasCommonSwift"
        ),
        .testTarget(
            name: "AtlasCommonSwiftTests",
            dependencies: ["AtlasCommonSwift"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
