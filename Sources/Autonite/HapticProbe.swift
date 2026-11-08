#if os(iOS)
import CoreHaptics
import UIKit

/// The single short pulse a live cue will use, so Pass 0 tests the real pattern.
@MainActor
final class HapticProbe {
    static var isSupported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    private var engine: CHHapticEngine?

    /// Starts the haptic engine ahead of time, so the first cue doesn't wait for it.
    func prepare() {
        guard Self.isSupported, engine == nil else { return }
        let engine = try? CHHapticEngine()
        engine?.playsHapticsOnly = true
        engine?.resetHandler = { [weak engine] in try? engine?.start() }
        try? engine?.start()
        self.engine = engine
    }

    func pulse() {
        guard Self.isSupported else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        do {
            let engine = try self.engine ?? CHHapticEngine()
            engine.playsHapticsOnly = true
            try engine.start()
            self.engine = engine
            // A "woong" buzz, not a single tap: a tap was too easy to miss on a table (Danny, 2026-11-01).
            // It starts at full strength with a sharp edge, so it is felt the instant it fires; a slow
            // swell added about half a second before it was noticed (Danny, 2026-11-02).
            let edge = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7),
                ],
                relativeTime: 0
            )
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
                ],
                relativeTime: 0,
                duration: 0.5
            )
            let swell = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    .init(relativeTime: 0, value: 1.0),
                    .init(relativeTime: 0.2, value: 0.8),
                    .init(relativeTime: 0.35, value: 1.0),
                    .init(relativeTime: 0.5, value: 0.5),
                ],
                relativeTime: 0
            )
            let player = try engine.makePlayer(with: CHHapticPattern(events: [edge, event], parameterCurves: [swell]))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }
}
#endif
