// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VikunjaNetworking",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "VikunjaNetworking", targets: ["VikunjaNetworking"]),
    ],
    dependencies: [
        .package(path: "../VikunjaCore"),
    ],
    targets: [
        .target(name: "VikunjaNetworking", dependencies: ["VikunjaCore"]),
        .testTarget(
            name: "VikunjaNetworkingTests",
            dependencies: ["VikunjaNetworking"],
            resources: [.process("Fixtures")],
        ),
    ],
)
