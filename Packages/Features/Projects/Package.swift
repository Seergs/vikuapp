// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Projects",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Projects", targets: ["Projects"]),
    ],
    dependencies: [
        .package(path: "../../VikunjaCore"),
        .package(path: "../../VikuNavigation"),
        .package(path: "../../VikuDesignSystem"),
        .package(path: "../../VikuUI"),
        .package(path: "../Kanban"),
    ],
    targets: [
        .target(
            name: "Projects",
            dependencies: ["VikunjaCore", "VikuNavigation", "VikuDesignSystem", "VikuUI", "Kanban"],
            resources: [.process("Resources")],
        ),
        .testTarget(name: "ProjectsTests", dependencies: ["Projects"]),
    ],
)
