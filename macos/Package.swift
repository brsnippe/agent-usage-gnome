// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AgentUsage",
    platforms: [.macOS(.v13)],
    targets: [
        // Everything the panel decides without a screen. Foundation only, so
        // it builds and tests on Linux too.
        .target(name: "AgentUsageCore"),
        .testTarget(name: "AgentUsageCoreTests", dependencies: ["AgentUsageCore"]),
    ]
)
