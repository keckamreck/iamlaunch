// swift-tools-version:5.9
import PackageDescription

var products: [Product] = [
    .library(name: "PresenceCore", targets: ["PresenceCore"]),
]

var targets: [Target] = [
    .target(name: "PresenceCore"),
    .testTarget(name: "PresenceCoreTests", dependencies: ["PresenceCore"]),
]

// The SwiftUI app only builds on macOS. PresenceCore and its tests build on
// Linux too, so the protocol and catalog logic can be tested without a Mac.
#if os(macOS)
products.append(.executable(name: "PlayStatus", targets: ["PlayStatus"]))
targets.append(.executableTarget(name: "PlayStatus", dependencies: ["PresenceCore"]))
#endif

let package = Package(
    name: "PlayStatus",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets
)
