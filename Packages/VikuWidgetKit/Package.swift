// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VikuWidgetKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "VikuWidgetKit", targets: ["VikuWidgetKit"]),
    ],
    dependencies: [
        .package(path: "../VikunjaCore"),
        .package(path: "../VikunjaNetworking"),
        .package(path: "../VikuAuth"),
        .package(path: "../VikuDesignSystem"),
        .package(path: "../VikuNavigation"),
        .package(path: "../VikunjaPersistence"),
    ],
    targets: [
        .target(
            name: "VikuWidgetKit",
            dependencies: [
                "VikunjaCore", "VikunjaNetworking", "VikuAuth", "VikuDesignSystem", "VikuNavigation",
                "VikunjaPersistence",
            ],
            resources: [.process("Resources")],
        ),
        .testTarget(
            name: "VikuWidgetKitTests",
            dependencies: ["VikuWidgetKit", "VikunjaPersistence"],
        ),
    ],
)
