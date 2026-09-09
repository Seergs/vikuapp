// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VikuNavigation",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "VikuNavigation", targets: ["VikuNavigation"]),
    ],
    dependencies: [
        .package(path: "../VikunjaCore"),
    ],
    targets: [
        .target(name: "VikuNavigation", dependencies: ["VikunjaCore"]),
        .testTarget(name: "VikuNavigationTests", dependencies: ["VikuNavigation"]),
    ],
)
