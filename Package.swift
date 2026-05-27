// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "caip",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "caip",
            path: "Sources/caip"
        )
    ]
)
