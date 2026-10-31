// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Autonite",
    // macOS is listed only so `swift test` can run AutoniteCore on a Mac; the app target is iOS-only.
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [
        .library(name: "Autonite", targets: ["Autonite"]),
    ],
    dependencies: [
        // Speaker diarization for Pass 0 experiment 2. The prebuilt text-normalization binary is left out.
        // "TTS" stays on only because xtool packages FluidAudio's TTS resource bundle whether or not the
        // trait builds it, and fails when it is missing. Code Apache 2.0; Sortformer model under the NVIDIA Open Model License.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.0", traits: ["Diarizer", "TTS"]),
    ],
    targets: [
        .target(name: "AutoniteCore"),
        .target(
            name: "Autonite",
            dependencies: [
                "AutoniteCore",
                .product(name: "FluidAudio", package: "FluidAudio", condition: .when(platforms: [.iOS])),
            ]
        ),
        .testTarget(name: "AutoniteCoreTests", dependencies: ["AutoniteCore"]),
    ]
)
