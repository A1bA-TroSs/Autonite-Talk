import Foundation

/// Reads formality in English against the session's register setting (SPEC AC5).
///
/// English has no verb endings for politeness, so the reader looks for casual markers (slang,
/// contractions like "gonna") and abstains on short phrases with no marker either way.
public enum EnglishRegisterReader {
    static let casualMarkers = [
        "gonna", "wanna", "gotta", "kinda", "sorta", "yeah", "yep", "nope", "nah", "dude", "bro",
        "ain't", "y'all", "lol", "whatever", "cool with", "no way", "what's up", "sup", "hey man",
    ]
    static let politeMarkers = [
        "please", "could you", "would you", "would it", "may i", "thank you", "thanks", "i'd appreciate",
        "i'd like", "sorry", "excuse me", "if you don't mind", "i wonder", "would you mind",
    ]

    public static func read(_ phrase: String, setting: RegisterSetting) -> Reading {
        let text = normalized(phrase)
        guard text.contains(where: \.isLetter) else { return .unknown }
        let casual = casualMarkers.contains { contains(text, $0) }
        let polite = politeMarkers.contains { contains(text, $0) }
        let words = text.split(whereSeparator: \.isWhitespace).count
        switch setting {
        case .politeExpected:
            if casual { return .check }
            if polite || words >= 4 { return .aligned }
            return .unknown
        case .casualFine, .either:
            return casual || polite || words >= 4 ? .aligned : .unknown
        }
    }

    static func normalized(_ s: String) -> String {
        " " + s.lowercased().replacingOccurrences(of: "’", with: "'")
            .map { $0.isLetter || $0 == "'" ? $0 : " " }
            .reduce(into: "") { $0.append($1) } + " "
    }

    /// Whole-word match: the marker must sit between non-letters.
    static func contains(_ text: String, _ marker: String) -> Bool {
        text.contains(" " + marker + " ")
    }
}

/// What the session allows for word choice. Gentle is the default.
public enum WordChoiceSetting: String, Codable, CaseIterable, Sendable {
    case gentle
    case bluntFine
}

/// Reads harsh words in Korean and English against the word-choice setting (SPEC AC6).
///
/// The lexicon is written for this project and ships under the repository's licence. It is
/// deliberately small: it lists words that may sound harsh, and makes no judgement of the person.
public enum WordChoiceReader {
    public static let englishHarsh = [
        "stupid", "idiot", "dumb", "moron", "shut up", "ridiculous", "useless", "pathetic",
        "nonsense", "incompetent", "lazy", "damn", "crap", "hell", "fuck", "fucking", "shit",
        "you always", "you never", "i don't care", "get lost", "who cares",
    ]
    /// Matched as substrings, since Korean attaches particles and endings to the stem.
    public static let koreanHarsh = [
        "바보", "멍청", "닥쳐", "꺼져", "미쳤", "한심", "쓸모없", "짜증나", "씨발", "시발", "병신", "젠장",
        "개같", "어이없", "됐거든", "알아서 해", "시끄러", "너는 맨날", "넌 맨날", "또 그러",
    ]

    /// The harsh words found in the phrase.
    public static func harshWords(in phrase: String) -> [String] {
        let english = EnglishRegisterReader.normalized(phrase)
        return englishHarsh.filter { EnglishRegisterReader.contains(english, $0) }
            + koreanHarsh.filter { phrase.contains($0) }
    }

    public static func read(_ phrase: String, setting: WordChoiceSetting) -> Reading {
        guard phrase.contains(where: \.isLetter) else { return .unknown }
        switch setting {
        case .gentle: return harshWords(in: phrase).isEmpty ? .aligned : .check
        case .bluntFine: return .aligned
        }
    }
}
