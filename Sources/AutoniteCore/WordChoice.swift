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

/// The user's own word list (docs/loop/RESEARCH-2026-11-16.md §5.6): words to flag that the
/// built-in list lacks, and built-in words this user doesn't want flagged, for example after a cue
/// they marked wrong. Kept on this iPhone only.
public struct PersonalWords: Codable, Equatable, Sendable {
    public private(set) var added: [String]
    public private(set) var muted: [String]

    public init(added: [String] = [], muted: [String] = []) {
        self.added = []
        self.muted = []
        for word in added { add(word) }
        for word in muted { mute(word) }
    }

    public var isEmpty: Bool { added.isEmpty && muted.isEmpty }

    /// Flags a word from now on. A muted built-in word is simply unmuted.
    public mutating func add(_ word: String) {
        let word = Self.clean(word)
        guard word.contains(where: \.isLetter) else { return }
        muted.removeAll { $0 == word }
        if !added.contains(word), !WordChoiceReader.builtIn.contains(word) { added.append(word) }
    }

    /// Stops flagging a word.
    public mutating func mute(_ word: String) {
        let word = Self.clean(word)
        guard word.contains(where: \.isLetter) else { return }
        added.removeAll { $0 == word }
        if !muted.contains(word) { muted.append(word) }
    }

    /// Takes a word off both lists, back to the built-in behaviour.
    public mutating func reset(_ word: String) {
        let word = Self.clean(word)
        added.removeAll { $0 == word }
        muted.removeAll { $0 == word }
    }

    /// The form the reader matches: lower case, punctuation as single spaces.
    static func clean(_ word: String) -> String {
        String(NormalizedText(word).characters).trimmingCharacters(in: .whitespaces)
    }
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
        "bullshit", "asshole", "bitch", "piss off", "screw you", "jerk",
    ]
    /// Matched inside words, since Korean attaches particles and endings to the stem. Spaced forms
    /// are listed one by one (개 짜증, 짜증 나) because the recognisers write them both ways; spaces
    /// are never removed wholesale, or "세 시 발표" would read as 시발 and "병 신경" as 병신.
    public static let koreanHarsh = [
        "바보", "멍청", "닥쳐", "꺼져", "미쳤", "한심", "쓸모없", "짜증나", "씨발", "시발", "병신", "젠장",
        "개같", "어이없", "됐거든", "알아서 해", "시끄러", "너는 맨날", "넌 맨날", "또 그러",
        "개새끼", "새끼", "존나", "졸라", "지랄", "씨바", "씨팔", "시팔", "씨빨", "좆", "미친", "엿 먹",
        "개짜증", "개 짜증", "짜증 나", "개소리", "또라이", "등신", "븅신", "존내", "좃",
    ]
    /// Ordinary words that contain a listed stem. A hit never starts or ends inside one.
    static let koreanInnocent = ["시발점", "시발역", "새끼손가락", "새끼발가락"]

    public static var builtIn: [String] { englishHarsh + koreanHarsh }

    /// One harsh word in a phrase.
    public struct Hit: Equatable, Sendable {
        /// The list entry (lower case for English).
        public let word: String
        /// Where it starts and how many characters it covers in the original phrase.
        public let offset: Int
        public let length: Int
    }

    /// Every harsh word in the phrase, in order and without overlaps: the longer entry wins, so
    /// 개새끼 is one hit rather than 개새끼 and 새끼. English entries match whole words; Korean
    /// entries match inside words. The user's muted words are skipped and added words count.
    public static func hits(in phrase: String, words: PersonalWords = PersonalWords()) -> [Hit] {
        let text = NormalizedText(phrase)
        var blocked = Set<Int>()
        for innocent in koreanInnocent {
            for start in text.find(innocent) { blocked.formUnion(start..<(start + innocent.count)) }
        }
        let entries = builtIn.filter { !words.muted.contains($0) } + words.added
        var candidates: [(start: Int, length: Int, word: String)] = []
        for entry in entries {
            let wholeWord = !entry.contains(where: isHangul)
            for start in text.find(entry) where !wholeWord || text.isWordBoundary(start: start, length: entry.count) {
                if blocked.isDisjoint(with: start..<(start + entry.count)) {
                    candidates.append((start, entry.count, entry))
                }
            }
        }
        candidates.sort { $0.start != $1.start ? $0.start < $1.start : $0.length > $1.length }
        var hits: [Hit] = []
        var taken = 0
        for candidate in candidates where candidate.start >= taken {
            let span = text.original(start: candidate.start, length: candidate.length)
            hits.append(Hit(word: candidate.word, offset: span.offset, length: span.length))
            taken = candidate.start + candidate.length
        }
        return hits
    }

    /// The harsh words found in the phrase, each once, in the order they appear.
    public static func harshWords(in phrase: String, words: PersonalWords = PersonalWords()) -> [String] {
        hits(in: phrase, words: words).map(\.word).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    /// How many times harsh words occur, counting repeats, so a second swear in one long
    /// sentence is a new hit for the early cue.
    public static func harshOccurrences(in phrase: String, words: PersonalWords = PersonalWords()) -> Int {
        hits(in: phrase, words: words).count
    }

    public static func read(_ phrase: String, setting: WordChoiceSetting, words: PersonalWords = PersonalWords()) -> Reading {
        guard phrase.contains(where: \.isLetter) else { return .unknown }
        switch setting {
        case .gentle: return hits(in: phrase, words: words).isEmpty ? .aligned : .check
        case .bluntFine: return .aligned
        }
    }

    static func isHangul(_ character: Character) -> Bool {
        character.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x1100...0x11FF).contains($0.value) || (0x3130...0x318F).contains($0.value) }
    }
}

/// A phrase lower-cased, with punctuation turned into spaces and runs of spaces collapsed, plus a
/// map from each kept character back to its position in the original phrase.
struct NormalizedText {
    let characters: [Character]
    let origin: [Int]

    init(_ phrase: String) {
        var characters: [Character] = []
        var origin: [Int] = []
        for (index, raw) in phrase.enumerated() {
            var character: Character = raw == "’" ? "'" : raw
            let lower = character.lowercased()
            if lower.count == 1, let single = lower.first { character = single }
            if character.isLetter || character.isNumber || character == "'" {
                characters.append(character)
                origin.append(index)
            } else if let last = characters.last, last != " " {
                characters.append(" ")
                origin.append(index)
            }
        }
        self.characters = characters
        self.origin = origin
    }

    /// Start positions of every occurrence of `needle`.
    func find(_ needle: String) -> [Int] {
        let pattern = Array(needle)
        guard let first = pattern.first, pattern.count <= characters.count else { return [] }
        var starts: [Int] = []
        for i in 0...(characters.count - pattern.count) where characters[i] == first {
            if Array(characters[i..<(i + pattern.count)]) == pattern { starts.append(i) }
        }
        return starts
    }

    /// No Latin letter right before or after, so "hell" doesn't match inside "hello".
    func isWordBoundary(start: Int, length: Int) -> Bool {
        func latin(_ i: Int) -> Bool { i >= 0 && i < characters.count && characters[i].isASCII && characters[i].isLetter }
        return !latin(start - 1) && !latin(start + length)
    }

    func original(start: Int, length: Int) -> (offset: Int, length: Int) {
        let first = origin[start]
        let last = origin[start + length - 1]
        return (first, last - first + 1)
    }
}
