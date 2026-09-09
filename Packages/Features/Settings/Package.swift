// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Settings",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Settings", targets: ["Settings"]),
    ],
    dependencies: [
        .package(path: "../../VikunjaCore"),
        .package(path: "../../VikuNavigation"),
        .package(path: "../../VikuDesignSystem"),
        .package(path: "../../VikuUI"),
    ],
    targets: [
        .target(name: "Settings", dependencies: ["VikunjaCore", "VikuNavigation", "VikuDesignSystem", "VikuUI"]),
        .testTarget(name: "SettingsTests", dependencies: ["Settings"]),
    ],
)
