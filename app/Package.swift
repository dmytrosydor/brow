// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Brow",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Brow", path: "Sources/Brow")
    ]
)
