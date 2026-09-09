// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalendarFeature",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CalendarFeature", targets: ["CalendarFeature"]),
    ],
    dependencies: [
        .package(path: "../../VikunjaCore"),
        .package(path: "../../VikuNavigation"),
        .package(path: "../../VikuDesignSystem"),
        .package(path: "../../VikuUI"),
    ],
    targets: [
        .target(name: "CalendarFeature", dependencies: ["VikunjaCore", "VikuNavigation", "VikuDesignSystem", "VikuUI"]),
        .testTarget(name: "CalendarFeatureTests", dependencies: ["CalendarFeature"]),
    ],
)
