// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Onboarding",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Onboarding", targets: ["Onboarding"]),
    ],
    dependencies: [
        .package(path: "../../VikunjaCore"),
        .package(path: "../../VikuDesignSystem"),
    ],
    targets: [
        .target(
            name: "Onboarding",
            dependencies: ["VikunjaCore", "VikuDesignSystem"],
            resources: [.process("Resources")],
        ),
        .testTarget(name: "OnboardingTests", dependencies: ["Onboarding"]),
    ],
)
