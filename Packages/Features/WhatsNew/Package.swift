// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhatsNew",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WhatsNew", targets: ["WhatsNew"]),
    ],
    dependencies: [
        .package(path: "../../VikunjaCore"),
        .package(path: "../../VikuDesignSystem"),
    ],
    targets: [
        .target(
            name: "WhatsNew",
            dependencies: ["VikunjaCore", "VikuDesignSystem"],
            resources: [.process("Resources")],
        ),
        .testTarget(name: "WhatsNewTests", dependencies: ["WhatsNew"]),
    ],
)
