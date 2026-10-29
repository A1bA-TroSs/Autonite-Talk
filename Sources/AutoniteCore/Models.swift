import Foundation

/// First-release speech modes. UI language is chosen separately.
public enum SpeechLanguage: String, Codable, CaseIterable, Sendable {
    case english
    case korean

    public var localeIdentifier: String {
        switch self {
        case .english: "en-US"
        case .korean: "ko-KR"
        }
    }

    public var displayName: String {
        switch self {
        case .english: "English"
        case .korean: "한국어"
        }
    }
}

/// How a session guessed who spoke.
public enum AttributionMethod: String, Codable, Sendable {
    /// Input level, scored leave-one-out against the hand tags.
    case level
    /// Diarizer plus an enrolled voice; predictions are fixed when made and scored as they stand.
    case voice
}

public enum SpeakerLabel: String, Codable, CaseIterable, Sendable {
    case user
    case other
    case unknown
}

/// One finalized transcription segment, with the evidence Pass 0 needs.
public struct Utterance: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    /// Seconds from the start of capture.
    public let start: Double
    public let end: Double
    public let text: String
    /// Wall-clock delay between the end of the spoken audio and the final result arriving.
    public let latency: Double
    /// Mean input level over the segment, in dBFS. Nil when no level samples overlap it.
    public let meanLevelDB: Double?
    public var predicted: SpeakerLabel
    public var predictionConfidence: Double
    /// Who actually spoke, labelled by hand during or after the session.
    public var groundTruth: SpeakerLabel?
    /// Voice attribution only: the diarizer slot, whether two voices overlapped, and the
    /// wall-clock delay from the end of the speech until the piece was attributed.
    public var voiceSlot: Int?
    public var overlapped: Bool?
    public var attributionDelay: Double?

    public init(
        id: UUID = UUID(),
        start: Double,
        end: Double,
        text: String,
        latency: Double,
        meanLevelDB: Double?,
        predicted: SpeakerLabel = .unknown,
        predictionConfidence: Double = 0,
        groundTruth: SpeakerLabel? = nil,
        voiceSlot: Int? = nil,
        overlapped: Bool? = nil,
        attributionDelay: Double? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.latency = latency
        self.meanLevelDB = meanLevelDB
        self.predicted = predicted
        self.predictionConfidence = predictionConfidence
        self.groundTruth = groundTruth
        self.voiceSlot = voiceSlot
        self.overlapped = overlapped
        self.attributionDelay = attributionDelay
    }
}
