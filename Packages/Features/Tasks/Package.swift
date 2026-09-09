// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tasks",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Tasks", targets: ["Tasks"]),
    ],
    dependencies: [
        .package(path: "../../VikunjaCore"),
        .package(path: "../../VikuDesignSystem"),
        .package(path: "../../VikuNavigation"),
        .package(path: "../../VikuUI"),
    ],
    targets: [
        .target(name: "Tasks", dependencies: ["VikunjaCore", "VikuDesignSystem", "VikuNavigation", "VikuUI"]),
        .testTarget(name: "TasksTests", dependencies: ["Tasks"]),
    ],
)
