// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Magwell",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Magwell", targets: ["Magwell"]),
        .library(name: "MagwellKit", targets: ["MagwellKit"]),
    ],
    dependencies: [
        // Auto-update. Ships as an XCFramework; build.sh copies it into Contents/Frameworks.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Everything lives in the library so the test target can reach it. The executable is
        // a thin shell — testing an executable target directly is fragile across toolchains.
        .target(
            name: "MagwellKit",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/MagwellKit",
            linkerSettings: [
                // Sparkle.framework is embedded in the bundle, not installed system-wide.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .executableTarget(name: "Magwell", dependencies: ["MagwellKit"], path: "Sources/Magwell"),
        .testTarget(name: "MagwellKitTests", dependencies: ["MagwellKit"], path: "Tests/MagwellKitTests"),
    ]
)
