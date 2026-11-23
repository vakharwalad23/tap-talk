// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TapTalkHotkeys",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TapTalkHotkeys", targets: ["TapTalkHotkeys"])
    ],
    targets: [
        .target(
            name: "TapTalkHotkeys",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "TapTalkHotkeysTests",
            dependencies: ["TapTalkHotkeys"],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
    ]
)
