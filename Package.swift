// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "foundation-deepseek",
    platforms: [.iOS(.v27), .macOS(.v27), .visionOS(.v27), .watchOS(.v27), .macCatalyst(.v27)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "foundation-deepseek",
            targets: ["FoundationDeepSeek"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/MacPaw/OpenAI", branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "FoundationDeepSeek",
            dependencies: [.product(name: "OpenAI", package: "OpenAI")],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "FoundationDeepSeekTests",
            dependencies: ["FoundationDeepSeek"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ],
    swiftLanguageModes: [.v6]
)
