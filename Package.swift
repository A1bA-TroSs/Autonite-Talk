// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Autonite",
    // macOS is listed only so `swift test` can run AutoniteCore on a Mac; the app target is iOS-only.
    platforms: [.iOS("26.0"), .macOS(.v15)],
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
