// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Bar27Core",
    platforms: [.macOS("27.0")],
    products: [.library(name: "Bar27Core", targets: ["Bar27Core"])],
    targets: [
        .target(name: "Bar27Core"),
        .testTarget(name: "Bar27CoreTests", dependencies: ["Bar27Core"]),
    ]
)
