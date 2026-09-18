// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LecRec",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LecRec",
            path: "Sources/LecRec",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
