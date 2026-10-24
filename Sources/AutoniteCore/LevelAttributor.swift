import Foundation

/// Baseline speaker attribution: the phone sits nearer the user, so the user may be louder.
///
/// This is the cheapest possible predictor, kept as the bar a real model (for example
/// a speaker-embedding diarizer) has to beat. It abstains when the two voices are not
/// separated by at least `minimumGapDB`, or when an utterance falls in the middle band.
public struct LevelAttributor: Sendable, Equatable {
    public let userMeanDB: Double
    public let otherMeanDB: Double
    public let minimumGapDB: Double

    public init?(labelled: [Utterance], minimumGapDB: Double = 3) {
        func mean(_ label: SpeakerLabel) -> Double? {
            let levels = labelled.compactMap { $0.groundTruth == label ? $0.meanLevelDB : nil }
            return levels.isEmpty ? nil : levels.reduce(0, +) / Double(levels.count)
        }
        guard let user = mean(.user), let other = mean(.other) else { return nil }
        userMeanDB = user
        otherMeanDB = other
        self.minimumGapDB = minimumGapDB
    }

    /// Returns a label and a confidence in 0...1. Confidence is distance from the midpoint
    /// as a fraction of half the gap, so 1 means at or beyond one speaker's mean.
    public func predict(levelDB: Double?) -> (SpeakerLabel, Double) {
        guard let levelDB else { return (.unknown, 0) }
        let gap = abs(userMeanDB - otherMeanDB)
        guard gap >= minimumGapDB else { return (.unknown, 0) }
        let midpoint = (userMeanDB + otherMeanDB) / 2
        let confidence = min(abs(levelDB - midpoint) / (gap / 2), 1)
        let userIsLouder = userMeanDB > otherMeanDB
        let louderThanMid = levelDB > midpoint
        return (louderThanMid == userIsLouder ? .user : .other, confidence)
    }
}
