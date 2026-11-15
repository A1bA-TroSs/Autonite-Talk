import Foundation

/// The live path from a completed, attributed phrase to a reading and cue (SPEC AC8).
///
/// Attribution is checked before any analysis: speech that is not confidently the user's never
/// reaches a reader, so it can never produce a reading or a haptic.
public enum ReadingPipeline {
    public enum Outcome: Equatable, Sendable {
        /// Nothing is shown or felt.
        case quiet(reason: String)
        /// The phrase was read. `cue` is true when a category may not fit the settings.
        case read(PhraseReadings, cue: Bool)
    }

    public static func evaluate(_ utterance: Utterance, language: SpeechLanguage, settings: CategorySettings) -> Outcome {
        if case .suppress(let reason) = CueGate.evaluate(utterance) {
            return .quiet(reason: reason)
        }
        if utterance.overlapped == true {
            return .quiet(reason: "two voices overlapped")
        }
        if let match = utterance.voiceMatch, match < VoiceVerifier.threshold {
            return .quiet(reason: "voice does not match the enrolled voice")
        }
        guard utterance.text.contains(where: \.isLetter) else {
            return .quiet(reason: "no words")
        }
        let readings = PhraseReader.read(utterance.text, language: language, settings: settings)
        return .read(readings, cue: !readings.mismatches.isEmpty)
    }
}

/// Reads the transcriber's in-progress (volatile) text, so a cue can fire while the user is still
/// talking instead of after the sentence is finalised (Danny, 2026-11-02: the buzz came too late).
///
/// Only settled evidence counts: a harsh word as soon as it appears, and a register mismatch only
/// for a sentence already closed by punctuation, a pause, or a word that opens the next sentence
/// (근데, 그래서…; see `KoreanRegisterReader.openers`). The trailing unfinished sentence is never
/// read for register, because a half-said word can look casual.
public struct EarlyReader: Sendable {
    /// Mismatch hits already cued in the current in-progress line.
    public private(set) var cuedHits = 0

    public init() {}

    /// Counts mismatches in the settled part of in-progress text.
    /// `closed` means the speaker paused after the text (see `pauseSeconds`), so its last clause is
    /// finished and its ending can be read for register, like a sentence the recogniser closed.
    public static func hits(in text: String, language: SpeechLanguage, settings: CategorySettings, closed: Bool = false) -> Int {
        var count = 0
        if settings.wordChoice == .gentle {
            count += WordChoiceReader.harshOccurrences(in: text, words: settings.words)
        }
        if language == .korean, settings.register == .politeExpected {
            var sentences = KoreanRegisterReader.sentences(in: text)
            let punctuated = text.trimmingCharacters(in: .whitespaces).last.map { ".?!…".contains($0) } ?? false
            if !(closed || punctuated), !sentences.isEmpty { sentences.removeLast() }
            count += sentences.filter { KoreanRegisterReader.register(ofSentence: $0) == .casual }.count
        }
        return count
    }

    /// True when the in-progress text holds a mismatch not yet cued in this line.
    public func hasNewMismatch(_ text: String, language: SpeechLanguage, settings: CategorySettings, closed: Bool = false) -> Bool {
        Self.hits(in: text, language: language, settings: settings, closed: closed) > cuedHits
    }

    /// Records that the current hits were cued, so the same words don't buzz twice.
    public mutating func markCued(_ text: String, language: SpeechLanguage, settings: CategorySettings, closed: Bool = false) {
        cuedHits = Self.hits(in: text, language: language, settings: settings, closed: closed)
    }

    /// A pause this long with no new words closes the current clause, so a long sentence is read in
    /// short pieces as it is spoken rather than all at once at its end (Danny, 2026-11-08).
    public static let pauseSeconds = 0.6

    /// The transcriber finalised the line; the next in-progress text starts fresh.
    public mutating func lineFinished() { cuedHits = 0 }
}

/// Decides whether a voice check vouches for words that just showed up in in-progress text
/// (rubric M5, round 2 must-fix). In-progress text carries no audio times, so the words are only
/// known to lie somewhere in the `lookback` seconds before the capture time at which they appeared.
/// So the early cue waits until the diarizer has heard up to that time, and then:
/// - another slot speaking anywhere from the start of the lookback on drops it for good;
/// - otherwise it needs a check made on the user's current slot that matched the enrolled voice,
///   whose stretch reaches to within `maximumLag` of when the words appeared and has no other
///   voice in it. Until such a check comes it waits, at most `maximumWait`.
/// A dropped hit is never cued early; the final line, which has word times, decides it.
public enum EarlyCueGate {
    /// How long before the moment they appeared the words may have been spoken: the recogniser's
    /// lag (0.3-0.6 s), the word itself and a late revision.
    public static let lookback = 2.0
    /// How close to that moment the checked stretch of the user's voice must reach.
    public static let maximumLag = 0.5
    /// How long a hit may wait for the diarizer and a clean, fresh check.
    public static let maximumWait = 1.5

    /// A background voice check: the stretch it printed, its match and the user slot at the time.
    public struct Check: Equatable, Sendable {
        public let window: ClosedRange<Double>
        public let match: Double
        public let slot: Int?

        public init(window: ClosedRange<Double>, match: Double, slot: Int?) {
            self.window = window
            self.match = match
            self.slot = slot
        }
    }

    /// New mismatches in in-progress text, with the capture times at which the first and the
    /// latest of them showed up.
    public struct Hit: Equatable, Sendable {
        public private(set) var text: String
        /// The in-progress text when the first mismatch showed up.
        public let firstText: String
        public private(set) var closed: Bool
        /// `EarlyReader.hits` in `text`.
        public private(set) var hits: Int
        public let firstHeardAt: Double
        public private(set) var heardAt: Double
        /// Seconds on a steady clock when it first showed up.
        public let since: Double

        public init(text: String, closed: Bool, hits: Int, heardAt: Double, since: Double) {
            self.text = text
            firstText = text
            self.closed = closed
            self.hits = hits
            firstHeardAt = heardAt
            self.heardAt = heardAt
            self.since = since
        }

        /// The line grew. Only another mismatch moves `heardAt`: more words around the same one
        /// don't, or a user who keeps talking would keep the diarizer from ever catching up.
        public mutating func update(text: String, closed: Bool, hits: Int, heardAt: Double) {
            self.text = text
            self.closed = closed
            if hits > self.hits {
                self.hits = hits
                self.heardAt = max(self.heardAt, heardAt)
            }
        }
    }

    public enum Verdict: Equatable, Sendable {
        case cue
        case wait
        /// Never cue these words early; the final line decides.
        case drop(String)
    }

    /// `heardUntil` is the newest audio time the diarizer has looked at; `now` is the clock `since` uses.
    public static func judge(_ hit: Hit, check: Check?, turns: [SpeakerTurn], userSlot: Int?, heardUntil: Double, now: Double) -> Verdict {
        let others = turns.filter { $0.slot != userSlot }
        if userSlot != nil, others.contains(where: { $0.end > hit.firstHeardAt - lookback }) {
            return .drop("another voice spoke while the words were said")
        }
        let vouched = userSlot != nil && heardUntil >= hit.heardAt && check.map { check in
            check.slot == userSlot && check.match >= VoiceVerifier.threshold
                && check.window.upperBound >= hit.heardAt - maximumLag
                && !others.contains { $0.end > check.window.lowerBound }
        } == true
        if vouched { return .cue }
        return now - hit.since > maximumWait ? .drop("no clean, fresh voice check in time") : .wait
    }
}
