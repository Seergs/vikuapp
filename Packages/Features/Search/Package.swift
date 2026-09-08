// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Search",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Search", targets: ["Search"]),
    ],
    dependencies: [
        .package(path: "../../VikunjaCore"),
        .package(path: "../../VikuNavigation"),
        .package(path: "../../VikuDesignSystem"),
    ],
    targets: [
        .target(name: "Search", dependencies: ["VikunjaCore", "VikuNavigation", "VikuDesignSystem"]),
        .testTarget(name: "SearchTests", dependencies: ["Search"]),
    ],
)
