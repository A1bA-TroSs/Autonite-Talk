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
        // On-device Whisper (WhisperKit, MIT) for a second listen to the user's own speech. Its Core ML
        // models download on first use from Hugging Face (argmaxinc/whisperkit-coreml, free), only
        // after the user turns it on in Settings. Pinned to the v1.1.1 release commit: its library
        // targets build with library-evolution flags, which SwiftPM accepts from a revision-pinned
        // dependency but not from a version-pinned one.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", revision: "1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4"),
    ],
    targets: [
        .target(name: "AutoniteCore"),
        .target(
            name: "Autonite",
            dependencies: [
                "AutoniteCore",
                .product(name: "FluidAudio", package: "FluidAudio", condition: .when(platforms: [.iOS])),
                .product(name: "WhisperKit", package: "argmax-oss-swift", condition: .when(platforms: [.iOS])),
            ]
        ),
        .testTarget(name: "AutoniteCoreTests", dependencies: ["AutoniteCore"]),
    ]
)
