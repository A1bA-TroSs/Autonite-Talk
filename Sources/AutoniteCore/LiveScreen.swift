import Foundation

/// First-run onboarding (SPEC P7). Biometric consent for the voice profile is separate from
/// permission to record a conversation, and enrolment cannot record before biometric consent.
public struct Onboarding: Equatable, Sendable {
    public private(set) var enrollment = EnrollmentFlow()
    public private(set) var recordingAllowed = false

    public init() {}

    public var biometricConsent: Bool { enrollment.consented }
    /// Enrolment audio may be captured only in a reading step after biometric consent.
    public var mayRecordEnrolment: Bool {
        guard enrollment.consented else { return false }
        switch enrollment.step {
        case .sentence, .extraSentence, .freeSpeech, .phraseCheck: return true
        default: return false
        }
    }

    public mutating func answerBiometricConsent(_ agreed: Bool) { enrollment.answerConsent(agreed) }
    /// The microphone permission for conversations; it never implies biometric consent.
    public mutating func allowRecording(_ allowed: Bool) { recordingAllowed = allowed }
    public mutating func update(_ change: (inout EnrollmentFlow) -> Void) { change(&enrollment) }
}

/// What the cue card shows, in DESIGN.md's order (SPEC AC13).
public struct Cue: Equatable, Sendable {
    public internal(set) var phrase: String
    public let possibleReading: String
    public let whyHere: String
    public internal(set) var tryNext: String
    public let categories: [ReadingCategory]
    /// Flagged moments this card stands for since it was last closed: hits close together share one
    /// card and one buzz (research 2026-11-16 §3).
    public internal(set) var count = 1
    /// Apple's words, kept when Whisper's second listen changed the quote.
    public internal(set) var firstHeard: String?
    /// Whisper has re-read the words on the card.
    public internal(set) var checkedAgain = false
    /// A short learner tip, shown when the app is in English and the speech is Korean.
    public internal(set) var note: String?
}

public enum CueComposer {
    /// Builds the card for a phrase with at least one mismatch. Register comes first when both apply.
    /// The explanation is in the app's language; the next line is in the speech language, since it
    /// is a sentence to say (INTENTIONAL §7: UI and speech language are chosen separately).
    public static func compose(phrase: String, readings: PhraseReadings, language: SpeechLanguage, uiLanguage: SpeechLanguage? = nil) -> Cue? {
        let ui = uiLanguage ?? language
        let mismatches = readings.mismatches
        guard let first = mismatches.first else { return nil }
        let reading: CopyKey = first == .register ? .readingRegisterCasual : .readingWordChoiceHarsh
        let why: CopyKey = first == .register ? .whyRegisterPolite : .whyWordChoiceGentle
        let next = first == .register
            ? (language == .korean ? politeVersion(of: phrase) : nil) ?? Copy.text(.nextRegisterFallback, language)
            : Copy.text(.nextWordChoice, language)
        var cue = Cue(phrase: phrase, possibleReading: Copy.text(reading, ui), whyHere: Copy.text(why, ui),
                      tryNext: next, categories: mismatches)
        if first == .register, language == .korean, ui == .english {
            cue.note = Copy.text(.learnerRegisterNote, .english)
        }
        return cue
    }

    /// The last sentence with a 반말 ending swapped for 해요체, when the ending is a common one.
    static let politeEndings: [(String, String)] = [
        ("거야", "거예요"), ("이야", "이에요"), ("잖아", "잖아요"), ("거든", "거든요"), ("할게", "할게요"),
        ("했어", "했어요"), ("없어", "없어요"), ("있어", "있어요"), ("아니야", "아니에요"), ("싶어", "싶어요"),
        ("했지", "했죠"), ("어때", "어때요"), ("줄래", "주실래요"), ("먹자", "드실래요"),
    ]

    static func politeVersion(of phrase: String) -> String? {
        let sentence = KoreanRegisterReader.sentences(in: phrase).last(where: { KoreanRegisterReader.register(ofSentence: $0) == .casual })
        guard let sentence else { return nil }
        for (casual, polite) in politeEndings where sentence.hasSuffix(casual) {
            return String(sentence.dropLast(casual.count)) + polite + "."
        }
        return nil
    }
}

/// The live screen's states (SPEC AC13): idle before recording, listening, a cue waiting or open,
/// and stopped. Only one cue at a time; a newer one supersedes it.
public struct LiveScreen: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case listening
        case cueWaiting(Cue)
        case cueOpen(Cue)
        case stopped
    }

    /// A cue the user marked inaccurate, kept on the phone so misreadings can be counted.
    public struct InaccurateMark: Codable, Equatable, Sendable {
        public let phrase: String
        public let categories: [ReadingCategory]
        public let markedAt: Date

        public init(phrase: String, categories: [ReadingCategory], markedAt: Date = Date()) {
            self.phrase = phrase
            self.categories = categories
            self.markedAt = markedAt
        }
    }

    public private(set) var phase: Phase = .idle
    /// Needle position: 0 at rest, 1 at the amber segment.
    public private(set) var needle = 0.0
    public private(set) var marks: [InaccurateMark] = []

    public init() {}

    public mutating func start() {
        phase = .listening
        needle = 0
    }

    /// Takes a pipeline outcome. Returns true when the card changed and the needle slammed; the
    /// caller decides whether a buzz plays (`CuePacer`).
    ///
    /// `sameMoment` is the final line of words an early cue already flagged: it replaces the card's
    /// words without counting a new hit, and does nothing if the user already closed that card.
    @discardableResult
    public mutating func receive(_ outcome: ReadingPipeline.Outcome, phrase: String, language: SpeechLanguage,
                                 uiLanguage: SpeechLanguage? = nil, sameMoment: Bool = false) -> Bool {
        guard phase != .idle, phase != .stopped else { return false }
        guard case .read(let readings, true) = outcome,
              var cue = CueComposer.compose(phrase: phrase, readings: readings, language: language, uiLanguage: uiLanguage) else { return false }
        let previous = currentCue
        if sameMoment, previous == nil { return false }
        if let previous { cue.count = sameMoment ? previous.count : previous.count + 1 }
        show(cue)
        needle = 1
        return true
    }

    /// The card on screen or waiting to be opened.
    public var currentCue: Cue? {
        switch phase {
        case .cueWaiting(let cue), .cueOpen(let cue): cue
        default: nil
        }
    }

    /// Whisper's second listen of the words on the card. The quote becomes Whisper's words and
    /// Apple's are kept when they differ; for a register cue the next line is rebuilt from the
    /// corrected words. The reasons stay as Apple's reading found them: Whisper corrects text and
    /// never adds a cue or a category.
    public mutating func applySecondListen(_ text: String, language: SpeechLanguage) {
        guard var cue = currentCue else { return }
        if SecondReading.squash(text) != SecondReading.squash(cue.phrase) {
            cue.firstHeard = cue.firstHeard ?? cue.phrase
            cue.phrase = text
        }
        cue.checkedAgain = true
        if cue.categories.first == .register, language == .korean, let polite = CueComposer.politeVersion(of: text) {
            cue.tryNext = polite
        }
        show(cue)
    }

    /// Keeps an open card open, so a newer hit doesn't close the sheet the user is reading.
    private mutating func show(_ cue: Cue) {
        if case .cueOpen = phase { phase = .cueOpen(cue) } else { phase = .cueWaiting(cue) }
    }

    /// The meter rests again after a moment; the cue stays available.
    public mutating func settleNeedle() { needle = 0 }

    public mutating func openCue() {
        if case .cueWaiting(let cue) = phase { phase = .cueOpen(cue) }
    }

    public mutating func dismissCue() {
        switch phase {
        case .cueWaiting, .cueOpen: phase = .listening
        default: break
        }
    }

    public mutating func markInaccurate(at date: Date = Date()) {
        switch phase {
        case .cueWaiting(let cue), .cueOpen(let cue):
            marks.append(InaccurateMark(phrase: cue.phrase, categories: cue.categories, markedAt: date))
            phase = .listening
        default: break
        }
    }

    public mutating func stop() {
        phase = .stopped
        needle = 0
    }
}

/// Geometry for the round meter (DESIGN.md and the UI reference): thick ring segments all the
/// way round, fine ticks only on the upper arc. Angles are in degrees, 0 = east, increasing
/// clockwise as on screen, so the upper half is 180...360. The needle rests pointing straight up
/// and swings right toward amber on a cue.
public enum MeterGeometry {
    /// The upper arc that carries ticks.
    public static let tickRange = 200.0...340.0
    /// The needle rests straight up, twitches a little with the voice, and slams to the right end
    /// of the ticked arc on a cue (Danny, 2026-11-02).
    public static let needleRange = 270.0...340.0
    public static let segmentCount = 10

    public static func needleAngle(_ position: Double) -> Double {
        needleRange.lowerBound + (needleRange.upperBound - needleRange.lowerBound) * min(max(position, 0), 1)
    }

    public static func tickAngles(count: Int = 29) -> [Double] {
        guard count > 1 else { return [tickRange.lowerBound] }
        let step = (tickRange.upperBound - tickRange.lowerBound) / Double(count - 1)
        return (0..<count).map { tickRange.lowerBound + Double($0) * step }
    }

    /// Start angles of the ring segments around the whole circle, including the lower arc.
    /// Offset so one segment is centred straight up, under the resting needle.
    public static func segmentAngles() -> [Double] {
        let span = 360 / Double(segmentCount)
        return (0..<segmentCount).map { (270 - span / 2 + Double($0) * span).truncatingRemainder(dividingBy: 360) }
    }

    /// The segment the needle points into, by start angle.
    public static func segment(containing angle: Double) -> Double? {
        let span = 360 / Double(segmentCount)
        return segmentAngles().first { start in
            let offset = (angle - start + 360).truncatingRemainder(dividingBy: 360)
            return offset < span
        }
    }

    /// The right end of the reachable arc is amber.
    public static func isAmber(_ angle: Double) -> Bool {
        angle >= 305 && angle <= tickRange.upperBound
    }

    /// Where the needle sits while listening: a small twitch around rest that follows the voice
    /// level (0 = silence, 1 = loud), from a few degrees left of rest to well short of amber.
    public static func listeningAngle(level: Double) -> Double {
        needleRange.lowerBound - 6 + 24 * min(max(level, 0), 1)
    }
}
