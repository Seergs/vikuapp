// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VikuAuth",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "VikuAuth", targets: ["VikuAuth"]),
    ],
    dependencies: [
        .package(path: "../VikunjaCore"),
        .package(url: "https://github.com/openid/AppAuth-iOS.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "VikuAuth",
            dependencies: [
                "VikunjaCore",
                .product(name: "AppAuth", package: "AppAuth-iOS"),
            ],
        ),
        .testTarget(name: "VikuAuthTests", dependencies: ["VikuAuth"]),
    ],
)
