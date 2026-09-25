// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VikuDesignSystem",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "VikuDesignSystem", targets: ["VikuDesignSystem"]),
    ],
    dependencies: [
        .package(path: "../VikunjaCore"),
    ],
    targets: [
        .target(
            name: "VikuDesignSystem",
            dependencies: ["VikunjaCore"],
            resources: [.process("Resources")],
        ),
        .testTarget(name: "VikuDesignSystemTests", dependencies: ["VikuDesignSystem"]),
    ],
)
