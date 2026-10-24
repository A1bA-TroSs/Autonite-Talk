import Foundation

/// Leave-one-out evaluation of `LevelAttributor` against hand labels.
///
/// The number that matters most is `otherAsUserRate`: a live cue fired on the other
/// person's words is the failure the handoff forbids.
public struct AttributionScore: Codable, Sendable, Equatable {
    public let labelled: Int
    /// Utterances where the gated predictor committed to user or other.
    public let committed: Int
    public let correct: Int
    /// Other-speaker utterances the gated predictor called `user`.
    public let otherAsUser: Int
    public let otherTotal: Int
    public let minimumConfidence: Double

    public var accuracyWhenCommitted: Double? { committed == 0 ? nil : Double(correct) / Double(committed) }
    public var coverage: Double? { labelled == 0 ? nil : Double(committed) / Double(labelled) }
    public var otherAsUserRate: Double? { otherTotal == 0 ? nil : Double(otherAsUser) / Double(otherTotal) }

    public init(utterances: [Utterance], minimumConfidence: Double = CueGate.defaultMinimumConfidence) {
        let labelled = utterances.filter { $0.groundTruth == .user || $0.groundTruth == .other }
        var committed = 0, correct = 0, otherAsUser = 0
        for (index, utterance) in labelled.enumerated() {
            var rest = labelled
            rest.remove(at: index)
            guard let attributor = LevelAttributor(labelled: rest) else { continue }
            let (label, confidence) = attributor.predict(levelDB: utterance.meanLevelDB)
            guard label != .unknown, confidence >= minimumConfidence else { continue }
            committed += 1
            if label == utterance.groundTruth { correct += 1 }
            if utterance.groundTruth == .other && label == .user { otherAsUser += 1 }
        }
        self.labelled = labelled.count
        self.committed = committed
        self.correct = correct
        self.otherAsUser = otherAsUser
        self.otherTotal = labelled.filter { $0.groundTruth == .other }.count
        self.minimumConfidence = minimumConfidence
    }
}
