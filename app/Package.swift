// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Brow",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "BrowShared", path: "Sources/BrowShared"),
        .executableTarget(name: "Brow", dependencies: ["BrowShared"], path: "Sources/Brow"),
        .executableTarget(name: "brow-hook", dependencies: ["BrowShared"], path: "Sources/brow-hook"),
    ]
)
