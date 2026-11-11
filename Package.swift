// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotchCompressor",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "NotchCompressor", targets: ["NotchCompressor"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.1.0"),
    ],
    targets: [
        .target(name: "NotchCompressorCore"),
        .executableTarget(
            name: "NotchCompressor",
            dependencies: [
                "NotchCompressorCore", .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "NotchCompressorCoreTests", dependencies: ["NotchCompressorCore"]),
    ]
)
