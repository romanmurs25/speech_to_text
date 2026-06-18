// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LiveOverlayTranslator",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LiveOverlayTranslatorCore", targets: ["LiveOverlayTranslatorCore"]),
        .executable(name: "LiveOverlayTranslator", targets: ["LiveOverlayTranslator"])
    ],
    targets: [
        .target(
            name: "LiveOverlayTranslatorCore",
            path: "Sources/LiveOverlayTranslatorCore"
        ),
        .executableTarget(
            name: "LiveOverlayTranslator",
            dependencies: ["LiveOverlayTranslatorCore"],
            path: "Sources/LiveOverlayTranslator"
        ),
        .testTarget(
            name: "LiveOverlayTranslatorTests",
            dependencies: ["LiveOverlayTranslatorCore"],
            path: "Tests/LiveOverlayTranslatorTests"
        )
    ]
)
