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
        /// Whisper's late re-reads can still fill in `whisperText` after the record is saved.
        public var utterances: [Utterance]
        public let interruptions: Int
        public let failures: [String]
        public let attributionMethod: AttributionMethod?
        /// Each early-cue decision (nil in reports from before round 3).
        public let earlyCues: [EarlyCueRecord]?

        public var latency: LatencyStats { LatencyStats(samples: utterances.map(\.latency)) }
        public var secondListen: SecondListenSummary { SecondListenSummary(utterances: utterances) }
        public var earlyCueSummary: EarlyCueSummary { EarlyCueSummary(records: earlyCues ?? []) }
        public var attribution: AttributionScore { AttributionScore(utterances: utterances, method: attributionMethod ?? .level) }

        public init(language: SpeechLanguage, startedAt: Date, duration: Double, audioSessionMode: String, utterances: [Utterance], interruptions: Int, failures: [String], attributionMethod: AttributionMethod = .level, earlyCues: [EarlyCueRecord]? = nil) {
            self.language = language
            self.startedAt = startedAt
            self.duration = duration
            self.audioSessionMode = audioSessionMode
            self.utterances = utterances
            self.interruptions = interruptions
            self.failures = failures
            self.attributionMethod = attributionMethod
            self.earlyCues = earlyCues
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

/// What Whisper's second listen did over a session's pieces (rubric C1: does it catch what Apple
/// missed?). It reads only the flags and counts, so it works on a redacted report too.
public struct SecondListenSummary: Equatable, Sendable {
    /// Pieces Whisper re-read.
    public let reRead: Int
    /// Of those, pieces where Whisper's words differ from Apple's.
    public let heardDifferently: Int
    /// Harsh words only Whisper heard (shown in the recap, never cued) and only Apple heard.
    public let onlyWhisperHarsh: Int
    public let onlyAppleHarsh: Int

    public init(reRead: Int, heardDifferently: Int, onlyWhisperHarsh: Int, onlyAppleHarsh: Int) {
        self.reRead = reRead
        self.heardDifferently = heardDifferently
        self.onlyWhisperHarsh = onlyWhisperHarsh
        self.onlyAppleHarsh = onlyAppleHarsh
    }

    public init(utterances: [Utterance]) {
        let read = utterances.filter { $0.whisperDiffers != nil }
        self.init(
            reRead: read.count,
            heardDifferently: read.filter { $0.whisperDiffers == true }.count,
            onlyWhisperHarsh: read.reduce(0) { $0 + ($1.whisperOnlyHarsh ?? 0) },
            onlyAppleHarsh: read.reduce(0) { $0 + ($1.appleOnlyHarsh ?? 0) }
        )
    }
}

/// One early-cue decision (rubric C1: does the cue land mid-sentence, and how long does the voice
/// gate hold it?). Times are capture seconds. It holds no words, so a redacted report keeps it.
public struct EarlyCueRecord: Codable, Equatable, Sendable {
    /// When the mismatch first showed up in the recogniser's in-progress text.
    public let heardAt: Double
    /// When it was cued or dropped.
    public let decidedAt: Double
    public let cued: Bool
    /// Why it was dropped (`EarlyCueGate`), when it was.
    public let reason: String?
    /// The end of the final line it belonged to, once that line arrived.
    public var lineEnd: Double?
    /// Letters in the in-progress text when the mismatch first showed up. A count, not the words,
    /// so the report holds no speech.
    public let heardLetters: Int?
    /// When the newest of those words ended, by the final line's word times.
    public var saidAt: Double?
    /// How far the diarizer's newest frame was behind the microphone when this was decided. A
    /// diarizer that falls behind on the phone makes the gate drop cues for want of a fresh check.
    public let diarizerLag: Double?

    public init(heardAt: Double, decidedAt: Double, cued: Bool, reason: String?, lineEnd: Double? = nil,
                heardLetters: Int? = nil, saidAt: Double? = nil, diarizerLag: Double? = nil) {
        self.heardAt = heardAt
        self.decidedAt = decidedAt
        self.cued = cued
        self.reason = reason
        self.lineEnd = lineEnd
        self.heardLetters = heardLetters
        self.saidAt = saidAt
        self.diarizerLag = diarizerLag
    }

    /// Seconds the voice gate held the cue after the words showed up.
    public var wait: Double { decidedAt - heardAt }
    /// Seconds before the end of its line that the cue fired; negative when it fired after.
    public var lead: Double? { cued ? lineEnd.map { $0 - decidedAt } : nil }
    /// Seconds from the end of the flagged word to the in-progress text that showed it: the
    /// recogniser's share of the delay.
    public var textLag: Double? { saidAt.map { heardAt - $0 } }
    /// Seconds from the end of the flagged word to the cue, for a cue that fired.
    public var wordToCue: Double? { cued ? saidAt.map { decidedAt - $0 } : nil }

    /// Fills in the line's end and, from its word times, when the flagged words were said.
    public mutating func place(lineEnd: Double, words: [WordSpan]) {
        self.lineEnd = lineEnd
        if let heardLetters { saidAt = Self.saidAt(letters: heardLetters, in: words) }
    }

    /// Letters and digits in `text`. Spaces and punctuation are left out, because the final line
    /// often punctuates what the in-progress text didn't.
    public static func letters(in text: String) -> Int {
        text.filter { $0.isLetter || $0.isNumber }.count
    }

    /// When the word that brings a line to `letters` letters ended; nil when the line is shorter,
    /// because then the in-progress text can't be placed in it.
    public static func saidAt(letters: Int, in words: [WordSpan]) -> Double? {
        guard letters > 0 else { return nil }
        var count = 0
        for word in words {
            count += Self.letters(in: word.text)
            if count >= letters { return word.end }
        }
        return nil
    }
}

public struct EarlyCueSummary: Equatable, Sendable {
    public let cued: Int
    public let dropped: Int
    /// Median and slowest hold by the voice gate, over the cues that fired.
    public let medianWait: Double?
    public let maximumWait: Double?
    /// Median of how long before the end of its line a cue fired.
    public let medianLead: Double?
    /// Median seconds from the end of the flagged word to the text that showed it (every record
    /// placed in its line), and to the cue (the cues that fired).
    public let medianTextLag: Double?
    public let medianWordToCue: Double?
    /// Median of how far the diarizer was behind the microphone at each decision.
    public let medianDiarizerLag: Double?
    /// How many were dropped for each reason.
    public let dropReasons: [String: Int]

    public init(records: [EarlyCueRecord]) {
        let fired = records.filter(\.cued)
        cued = fired.count
        dropped = records.count - fired.count
        let waits = fired.map(\.wait).sorted()
        medianWait = Self.median(waits)
        maximumWait = waits.last
        medianLead = Self.median(fired.compactMap(\.lead).sorted())
        medianTextLag = Self.median(records.compactMap(\.textLag).sorted())
        medianWordToCue = Self.median(fired.compactMap(\.wordToCue).sorted())
        medianDiarizerLag = Self.median(records.compactMap(\.diarizerLag).sorted())
        dropReasons = records.filter { !$0.cued }.reduce(into: [:]) { counts, record in
            counts[record.reason ?? "unknown", default: 0] += 1
        }
    }

    public struct DropReason: Equatable, Sendable, Identifiable {
        public let reason: String
        public let count: Int
        public var id: String { reason }
    }

    /// The drop reasons, most common first.
    public var sortedDropReasons: [DropReason] {
        dropReasons.map { DropReason(reason: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.reason < $1.reason }
    }

    private static func median(_ sorted: [Double]) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }
}
