// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TapTalkAudio",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TapTalkAudio", targets: ["TapTalkAudio"])
    ],
    targets: [
        .target(name: "RingAtomics"),
        .target(
            name: "TapTalkAudio",
            dependencies: ["RingAtomics"],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "TapTalkAudioTests",
            dependencies: ["TapTalkAudio"],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
    ]
)
