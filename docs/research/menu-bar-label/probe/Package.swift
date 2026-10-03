// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LabelProbe",
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(
            name: "LabelProbe",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        )
    ]
)
