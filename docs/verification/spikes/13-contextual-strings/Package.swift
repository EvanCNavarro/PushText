// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "spike13",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "spike13",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
