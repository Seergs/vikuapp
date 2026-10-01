// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kanban",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Kanban", targets: ["Kanban"]),
    ],
    dependencies: [
        .package(path: "../../VikunjaCore"),
        .package(path: "../../VikuNavigation"),
        .package(path: "../../VikuDesignSystem"),
        .package(path: "../../VikuUI"),
    ],
    targets: [
        .target(name: "Kanban", dependencies: ["VikunjaCore", "VikuNavigation", "VikuDesignSystem", "VikuUI"]),
        .testTarget(name: "KanbanTests", dependencies: ["Kanban"]),
    ],
)
