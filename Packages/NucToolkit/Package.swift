// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NucToolkit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "NucPhysKit", targets: ["NucPhysKit"]),
        .library(name: "ToolkitUI", targets: ["ToolkitUI"]),
    ],
    targets: [
        // Pure physics: masses, reactions, kinematics. No UI dependencies.
        .target(
            name: "NucPhysKit",
            resources: [.process("Resources")]
        ),
        // All SwiftUI screens. The iOS app target is a thin @main wrapper around this.
        .target(
            name: "ToolkitUI",
            dependencies: ["NucPhysKit"]
        ),
        .testTarget(
            name: "NucPhysKitTests",
            dependencies: ["NucPhysKit"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "ToolkitUITests", dependencies: ["ToolkitUI", "NucPhysKit"]),
    ]
)
