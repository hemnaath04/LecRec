// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Lectern",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Lectern",
            path: "Sources/Lectern",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
