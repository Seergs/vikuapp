// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VikunjaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "VikunjaCore", targets: ["VikunjaCore"]),
    ],
    targets: [
        .target(name: "VikunjaCore"),
        .testTarget(name: "VikunjaCoreTests", dependencies: ["VikunjaCore"]),
    ],
)
