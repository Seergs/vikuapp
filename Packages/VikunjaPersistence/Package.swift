// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VikunjaPersistence",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "VikunjaPersistence", targets: ["VikunjaPersistence"]),
    ],
    dependencies: [
        .package(path: "../VikunjaCore"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    ],
    targets: [
        .target(
            name: "VikunjaPersistence",
            dependencies: [
                "VikunjaCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [.process("Resources")],
        ),
        .testTarget(name: "VikunjaPersistenceTests", dependencies: ["VikunjaPersistence"]),
    ],
)
