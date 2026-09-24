// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VikuUI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "VikuUI", targets: ["VikuUI"]),
    ],
    dependencies: [
        .package(path: "../VikunjaCore"),
        .package(path: "../VikuDesignSystem"),
    ],
    targets: [
        .target(name: "VikuUI", dependencies: ["VikunjaCore", "VikuDesignSystem"]),
        .testTarget(name: "VikuUITests", dependencies: ["VikuUI", "VikunjaCore"]),
    ],
)
