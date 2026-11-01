#if os(iOS)
import CoreHaptics
import UIKit

/// The single short pulse a live cue will use, so Pass 0 tests the real pattern.
@MainActor
final class HapticProbe {
    static var isSupported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    private var engine: CHHapticEngine?

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
            // A rising "woong" buzz, not a single tap: a tap was too easy to miss on a table (Danny, 2026-11-01).
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
                ],
                relativeTime: 0,
                duration: 0.6
            )
            let swell = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    .init(relativeTime: 0, value: 0.4),
                    .init(relativeTime: 0.35, value: 1.0),
                    .init(relativeTime: 0.6, value: 0.7),
                ],
                relativeTime: 0
            )
            let player = try engine.makePlayer(with: CHHapticPattern(events: [event], parameterCurves: [swell]))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }
}
#endif
