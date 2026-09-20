// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "orukeet-lab",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.5"),
    ],
    targets: [
        .executableTarget(
            name: "ttprof",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        ),
        .executableTarget(
            name: "ttreg",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        ),
        .executableTarget(name: "ttdecode"),
        .executableTarget(name: "ttwarm"),
    ]
)
