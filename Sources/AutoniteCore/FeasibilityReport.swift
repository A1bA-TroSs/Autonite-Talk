import Foundation

/// Everything Pass 0 has to report (CLAUDE_CODE_HANDOFF.md, end of the feasibility pass).
public struct FeasibilityReport: Codable, Sendable {
    public struct LocaleCheck: Codable, Sendable, Equatable {
        public let language: SpeechLanguage
        public let resolvedIdentifier: String?
        public let supported: Bool
        public let installedBeforeRun: Bool
        public let checkedAt: Date

        public init(language: SpeechLanguage, resolvedIdentifier: String?, supported: Bool, installedBeforeRun: Bool, checkedAt: Date = Date()) {
            self.language = language
            self.resolvedIdentifier = resolvedIdentifier
            self.supported = supported
            self.installedBeforeRun = installedBeforeRun
            self.checkedAt = checkedAt
        }
    }

    public struct SessionRecord: Codable, Sendable {
        public let language: SpeechLanguage
        public let startedAt: Date
        public let duration: Double
        public let audioSessionMode: String
        public let utterances: [Utterance]
        public let interruptions: Int
        public let failures: [String]
        public let attributionMethod: AttributionMethod?

        public var latency: LatencyStats { LatencyStats(samples: utterances.map(\.latency)) }
        public var attribution: AttributionScore { AttributionScore(utterances: utterances, method: attributionMethod ?? .level) }

        public init(language: SpeechLanguage, startedAt: Date, duration: Double, audioSessionMode: String, utterances: [Utterance], interruptions: Int, failures: [String], attributionMethod: AttributionMethod = .level) {
            self.language = language
            self.startedAt = startedAt
            self.duration = duration
            self.audioSessionMode = audioSessionMode
            self.utterances = utterances
            self.interruptions = interruptions
            self.failures = failures
            self.attributionMethod = attributionMethod
        }
    }

    public enum Placement: String, Codable, CaseIterable, Sendable {
        case inHand = "in hand"
        case tableFaceUp = "table, face up"
        case tableWithCase = "table, face up, in case"
    }

    public struct HapticTrial: Codable, Sendable, Equatable {
        public let placement: Placement
        public let duringRecording: Bool
        public let felt: Bool
        public let at: Date

        public init(placement: Placement, duringRecording: Bool, felt: Bool, at: Date = Date()) {
            self.placement = placement
            self.duringRecording = duringRecording
            self.felt = felt
            self.at = at
        }
    }

    public var deviceModel: String
    public var osVersion: String
    public var transcriberAvailable: Bool
    public var locales: [LocaleCheck] = []
    public var sessions: [SessionRecord] = []
    public var hapticTrials: [HapticTrial] = []
    public var hapticsSupported: Bool
    public var notes: String = ""

    public init(deviceModel: String, osVersion: String, transcriberAvailable: Bool, hapticsSupported: Bool) {
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.transcriberAvailable = transcriberAvailable
        self.hapticsSupported = hapticsSupported
    }

    public func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
