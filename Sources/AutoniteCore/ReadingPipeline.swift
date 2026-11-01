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
