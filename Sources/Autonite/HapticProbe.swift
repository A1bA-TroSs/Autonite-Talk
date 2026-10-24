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
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6),
                ],
                relativeTime: 0
            )
            let player = try engine.makePlayer(with: CHHapticPattern(events: [event], parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }
}
