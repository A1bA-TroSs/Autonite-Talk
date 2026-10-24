import Foundation

/// The attribution half of the live-cue gate. A cue may only fire on words confidently
/// attributed to the user; everything else stays quiet (INTENTIONAL.md §4).
public enum CueGate {
    public static let defaultMinimumConfidence = 0.6

    public enum Decision: Equatable, Sendable {
        case deliver
        case suppress(reason: String)
    }

    public static func evaluate(
        _ utterance: Utterance,
        minimumConfidence: Double = defaultMinimumConfidence
    ) -> Decision {
        switch utterance.predicted {
        case .unknown:
            return .suppress(reason: "speaker unknown")
        case .other:
            return .suppress(reason: "attributed to the other speaker")
        case .user:
            guard utterance.predictionConfidence >= minimumConfidence else {
                return .suppress(reason: "attribution confidence below \(minimumConfidence)")
            }
            return .deliver
        }
    }
}
