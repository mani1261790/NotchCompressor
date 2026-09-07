// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotchCompressor",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "NotchCompressor", targets: ["NotchCompressor"])],
    targets: [
        .target(name: "NotchCompressorCore"),
        .executableTarget(name: "NotchCompressor", dependencies: ["NotchCompressorCore"]),
        .testTarget(name: "NotchCompressorCoreTests", dependencies: ["NotchCompressorCore"])
    ]
)
