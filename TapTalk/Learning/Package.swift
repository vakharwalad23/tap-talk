// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TapTalkLearning",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TapTalkLearning", targets: ["TapTalkLearning"])
    ],
    targets: [
        .target(
            name: "TapTalkLearning",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "TapTalkLearningTests",
            dependencies: ["TapTalkLearning"],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
    ]
)
