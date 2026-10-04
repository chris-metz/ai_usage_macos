// swift-tools-version: 6.2
import PackageDescription

/// Every target: Swift 6 language mode (full data-race checking) and
/// main-actor isolation by default. Only background work opts out.
let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),
]

let package = Package(
    name: "Pacemark",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "Pacemark", targets: ["Pacemark"]),
    ],
    targets: [
        .executableTarget(
            name: "Pacemark",
            dependencies: ["PacemarkKit", "PacemarkClaude"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "PacemarkKit",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "PacemarkClaude",
            dependencies: ["PacemarkKit"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "PacemarkKitTests",
            dependencies: ["PacemarkKit"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "PacemarkClaudeTests",
            dependencies: ["PacemarkClaude"],
            resources: [.copy("Fixtures")],
            swiftSettings: swiftSettings
        ),
    ]
)
