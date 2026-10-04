// swift-tools-version:5.9
import PackageDescription

var targets: [Target] = [
    // Everything the panel decides without a screen. Foundation only, so it
    // builds and tests on Linux too.
    .target(name: "AgentUsageCore"),
    .testTarget(name: "AgentUsageCoreTests", dependencies: ["AgentUsageCore"]),
]

#if os(macOS)
// The menu bar app itself: AppKit and SwiftUI. build-app.sh wraps it into
// "Agent Usage.app" with the icons, fonts and collectors from Resources/.
targets.append(.executableTarget(name: "AgentUsage", dependencies: ["AgentUsageCore"]))
#endif

let package = Package(
    name: "AgentUsage",
    platforms: [.macOS(.v13)],
    targets: targets
)
