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
    /// Voice attribution only: cosine similarity of a slot-Me piece's voiceprint to the enrolment.
    public var voiceMatch: Double?
    /// Whisper's second listen of this piece, once done (loop autunite-reach): its words, whether
    /// they differ from Apple's beyond spacing and punctuation, and how many harsh words only one
    /// of the two heard. The flag and counts survive `scripts/redact_report.py`; the words don't.
    public var whisperText: String?
    public var whisperDiffers: Bool?
    public var whisperOnlyHarsh: Int?
    public var appleOnlyHarsh: Int?
    /// Whisper's reading didn't read as the same speech as Apple's (`SecondReading.resembles`), so
    /// its words count for nothing here, the same guard the cue card and the recap use. Nil in
    /// reports saved before this.
    public var whisperSetAside: Bool?

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
        attributionDelay: Double? = nil,
        voiceMatch: Double? = nil
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
        self.voiceMatch = voiceMatch
    }

    /// Records Whisper's second listen of this piece next to Apple's words.
    ///
    /// The lab counts Whisper's words the way the cue card and the recap use them. A reading that
    /// doesn't read as the same speech keeps its text for the lab view but is set aside: it counts
    /// no harsh words either way, so a phrase Whisper made up can't inflate the report. A harsh word
    /// only Whisper heard also needs a sure read (`SecondReading.isSure`), as in the recap.
    public mutating func recordSecondListen(_ whisper: String, sure: Bool = true, words: PersonalWords = PersonalWords()) {
        let comparison = SecondReading.compare(apple: text, whisper: whisper, words: words)
        let sameSpeech = SecondReading.resembles(apple: text, whisper: whisper)
        whisperText = whisper
        whisperDiffers = comparison.differs
        whisperSetAside = !sameSpeech
        whisperOnlyHarsh = sameSpeech && sure ? comparison.onlyWhisper.count : 0
        appleOnlyHarsh = sameSpeech ? comparison.onlyApple.count : 0
    }
}
