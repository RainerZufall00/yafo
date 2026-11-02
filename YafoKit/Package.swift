// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "YafoKit",
    defaultLocalization: "en",
    platforms: [.iOS("27.0"), .macOS("26.0")],
    products: [
        .library(name: "YafoKit", targets: ["YafoKit"])
    ],
    targets: [
        .target(
            name: "YafoKit",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "YafoKitTests",
            dependencies: ["YafoKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        )
    ]
)
