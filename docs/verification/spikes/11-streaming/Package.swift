// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "spike11",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "spike11",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
