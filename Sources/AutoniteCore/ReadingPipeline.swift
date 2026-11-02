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
/// for a sentence the transcriber has already closed with punctuation. The trailing unfinished
/// sentence is never read for register, because a half-said word can look casual.
public struct EarlyReader: Sendable {
    /// Mismatch hits already cued in the current in-progress line.
    public private(set) var cuedHits = 0

    public init() {}

    /// Counts mismatches in the settled part of in-progress text.
    public static func hits(in text: String, language: SpeechLanguage, settings: CategorySettings) -> Int {
        var count = 0
        if settings.wordChoice == .gentle {
            count += WordChoiceReader.harshOccurrences(in: text)
        }
        if language == .korean, settings.register == .politeExpected {
            var sentences = KoreanRegisterReader.sentences(in: text)
            let closed = text.trimmingCharacters(in: .whitespaces).last.map { ".?!…".contains($0) } ?? false
            if !closed, !sentences.isEmpty { sentences.removeLast() }
            count += sentences.filter { KoreanRegisterReader.register(ofSentence: $0) == .casual }.count
        }
        return count
    }

    /// True when the in-progress text holds a mismatch not yet cued in this line.
    public func hasNewMismatch(_ text: String, language: SpeechLanguage, settings: CategorySettings) -> Bool {
        Self.hits(in: text, language: language, settings: settings) > cuedHits
    }

    /// Records that the current hits were cued, so the same words don't buzz twice.
    public mutating func markCued(_ text: String, language: SpeechLanguage, settings: CategorySettings) {
        cuedHits = Self.hits(in: text, language: language, settings: settings)
    }

    /// The transcriber finalised the line; the next in-progress text starts fresh.
    public mutating func lineFinished() { cuedHits = 0 }
}
