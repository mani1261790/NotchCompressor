// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotchCompressor",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchCompressor", targets: ["NotchCompressor"]),
        .executable(name: "NotchImageWorker", targets: ["NotchImageWorker"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.1.0"),
    ],
    targets: [
        .target(name: "NotchCompressorCore", resources: [.process("Resources")]),
        .executableTarget(
            name: "NotchCompressor",
            dependencies: [
                "NotchCompressorCore", .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "NotchImageWorker", dependencies: ["NotchCompressorCore"]),
        .testTarget(name: "NotchCompressorCoreTests", dependencies: ["NotchCompressorCore"]),
    ]
)
