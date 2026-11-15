import Foundation

/// Whisper's second listen to speech that Apple's recogniser and the voice gate already gave to the
/// user. Whisper only corrects the words: a word only Whisper heard never creates a cue, because
/// Whisper invents whole phrases in about 1% of segments, sometimes violent ones
/// (docs/loop/RESEARCH-2026-11-16.md §4; BRIEF of the `autunite-reach` loop).
public enum SecondReading {
    /// Pieces shorter than this aren't re-read: Whisper guesses on very short audio.
    public static let minimumSeconds = 0.6
    /// Audio kept on each side of a piece, so a clipped first or last syllable is still heard.
    public static let padding = 0.25

    /// Whether a piece may be re-read: only speech the gate gave to the user, the same rule a cue
    /// needs. Another person's words, overlapped speech and unverified pieces are never re-read.
    public static func admits(_ utterance: Utterance) -> Bool {
        guard CueGate.evaluate(utterance) == .deliver, utterance.overlapped != true else { return false }
        if let match = utterance.voiceMatch, match < VoiceVerifier.threshold { return false }
        return utterance.end - utterance.start >= minimumSeconds && utterance.text.contains(where: \.isLetter)
    }

    /// Phrases Whisper writes for silence or noise: subtitle credits from its training data.
    public static let hallucinations = [
        "시청해주셔서 감사합니다", "시청해 주셔서 감사합니다", "구독과 좋아요", "구독 좋아요", "좋아요와 구독",
        "다음 영상에서 만나요", "자막 제공", "자막 by", "mbc 뉴스", "kbs 뉴스", "sbs 뉴스",
        "thank you for watching", "thanks for watching", "please subscribe", "subtitles by",
        "transcribed by", "like and subscribe", "see you in the next video",
    ]

    /// One Whisper segment made safe to show, or nil when nothing worth reading is left. A segment
    /// that repeats itself, or that Whisper rates as probably not speech, is dropped; sound tags
    /// ([Music], (웃음)), special tokens, known silence phrases and stray letters from other
    /// scripts (Cyrillic, kana) are removed.
    public static func clean(_ text: String, noSpeechProbability: Double = 0, averageLogProbability: Double = 0, compressionRatio: Double = 1) -> String? {
        if compressionRatio > 2.4 { return nil }
        if noSpeechProbability > 0.6, averageLogProbability < -1 { return nil }
        var cleaned = text.replacingOccurrences(of: "<\\|[^|>]*\\|>", with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\[[^\\]]*\\]|\\([^)]*\\)|（[^）]*）|[♪♫]+", with: " ", options: .regularExpression)
        for phrase in hallucinations {
            cleaned = cleaned.replacingOccurrences(of: phrase, with: " ", options: .caseInsensitive)
        }
        cleaned = String(String.UnicodeScalarView(cleaned.unicodeScalars.filter { !isStray($0) }))
        cleaned = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return cleaned.contains(where: \.isLetter) ? cleaned : nil
    }

    /// Cyrillic, hiragana and katakana: never part of Korean or English speech here.
    static func isStray(_ scalar: Unicode.Scalar) -> Bool {
        (0x0400...0x04FF).contains(scalar.value) || (0x3040...0x30FF).contains(scalar.value)
    }

    /// How the two recognisers compare on harsh words in the same piece.
    public struct Comparison: Equatable, Sendable {
        /// Harsh words only Whisper heard: listed in the recap, never cued.
        public let onlyWhisper: [String]
        /// Harsh words only Apple heard: the cue may rest on a misheard word.
        public let onlyApple: [String]
        /// The texts differ beyond spacing and punctuation.
        public let differs: Bool
    }

    public static func compare(apple: String, whisper: String, words: PersonalWords = PersonalWords()) -> Comparison {
        let heardByApple = WordChoiceReader.harshWords(in: apple, words: words)
        let heardByWhisper = WordChoiceReader.harshWords(in: whisper, words: words)
        return Comparison(
            onlyWhisper: heardByWhisper.filter { !heardByApple.contains($0) },
            onlyApple: heardByApple.filter { !heardByWhisper.contains($0) },
            differs: squash(apple) != squash(whisper)
        )
    }

    /// Letters and digits only, lower case: two texts that differ only in spacing or punctuation match.
    public static func squash(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}

/// Pieces waiting for Whisper's second listen. Whisper can fall behind continuous talk (the large
/// model on an iPhone; docs/loop/whisper-bench/RESULTS.md), so pieces that gave a cue go first and,
/// when the queue is full, the oldest piece without a cue is dropped.
public struct ReReadQueue<Item: Sendable>: Sendable {
    struct Entry: Sendable {
        let item: Item
        let cued: Bool
    }

    public let capacity: Int
    private var entries: [Entry] = []

    public init(capacity: Int = 8) {
        self.capacity = max(1, capacity)
    }

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }

    public mutating func push(_ item: Item, cued: Bool) {
        entries.append(Entry(item: item, cued: cued))
        while entries.count > capacity {
            if let oldest = entries.firstIndex(where: { !$0.cued }) {
                entries.remove(at: oldest)
            } else {
                entries.removeFirst()
            }
        }
    }

    /// The next piece: the oldest one that gave a cue, otherwise the oldest.
    public mutating func pop() -> Item? {
        if let cued = entries.firstIndex(where: { $0.cued }) { return entries.remove(at: cued).item }
        return entries.isEmpty ? nil : entries.removeFirst().item
    }

    public mutating func removeAll() { entries.removeAll() }
}
