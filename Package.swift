// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Autonite",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        // xtool builds the app from this library product (see xtool.yml).
        .library(name: "Autonite", targets: ["Autonite"]),
    ],
    targets: [
        // Foundation-only logic, so `swift test` runs on a Mac without a device.
        .target(name: "AutoniteCore"),
        .target(name: "Autonite", dependencies: ["AutoniteCore"]),
        .testTarget(name: "AutoniteCoreTests", dependencies: ["AutoniteCore"]),
    ]
)
