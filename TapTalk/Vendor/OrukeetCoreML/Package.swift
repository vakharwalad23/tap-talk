// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OrukeetCoreML",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OrukeetCoreML", targets: ["OrukeetCoreML"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.5")
    ],
    targets: [
        .target(name: "OrukeetCoreML", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")])
    ]
)
