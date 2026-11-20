// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TapTalkUpdates",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TapTalkUpdates", targets: ["TapTalkUpdates"])
    ],
    targets: [
        .target(
            name: "TapTalkUpdates",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "TapTalkUpdatesTests",
            dependencies: ["TapTalkUpdates"],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
    ]
)
