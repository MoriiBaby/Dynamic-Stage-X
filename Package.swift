// swift-tools-version: 5.5
import PackageDescription

let package = Package(
    name: "DynamicStageXCore",
    platforms: [.iOS(.v15)],
    products: [.library(name: "DynamicStageXCore", targets: ["DynamicStageXCore"])],
    targets: [
        .target(name: "DynamicStageXCore", path: "Sources/Core", exclude: ["API.md"]),
        .testTarget(
            name: "DynamicStageXCoreTests",
            dependencies: ["DynamicStageXCore"],
            path: "Tests/Core",
            exclude: ["verify_source_contract.py"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
