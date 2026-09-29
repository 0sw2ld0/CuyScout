// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CuyScout",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "cuyscout", targets: ["CuyScout"]),
        .executable(name: "cuyscout-mcp", targets: ["CuyScoutMCP"]),
        .executable(name: "cuyscout-app", targets: ["CuyScoutApp"]),
        .library(name: "CuyScoutCore", targets: ["CuyScoutCore"])
    ],
    targets: [
        .target(name: "CuyScoutCore"),
        .executableTarget(name: "CuyScout", dependencies: ["CuyScoutCore"]),
        .executableTarget(name: "CuyScoutMCP", dependencies: ["CuyScoutCore"]),
        .executableTarget(name: "CuyScoutApp", dependencies: ["CuyScoutCore"]),
        .testTarget(name: "CuyScoutCoreTests", dependencies: ["CuyScoutCore"])
    ]
)
