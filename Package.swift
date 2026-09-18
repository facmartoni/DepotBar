// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DepotBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DepotBar",
            path: "Sources/DepotBar"
        )
    ]
)
