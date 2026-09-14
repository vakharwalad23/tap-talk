// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ttbench",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.5"),
    ],
    targets: [
        .executableTarget(
            name: "ttbench",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        ),
    ]
)
