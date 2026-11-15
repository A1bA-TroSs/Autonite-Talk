import Foundation

/// The end-of-session recap (INTENTIONAL §6 and Pass 1's "end-session recap layout";
/// docs/loop/RESEARCH-2026-11-16.md §3 and §5.4): the flagged moments in order, each with its quote,
/// what each recogniser heard and the user's accurate/inaccurate mark. There is no overall grade.
/// It is kept in memory only and replaced when the next session starts.
public struct SessionRecap: Equatable, Sendable {
    public enum Verdict: String, Codable, Sendable {
        case accurate
        case inaccurate
    }

    public struct Moment: Identifiable, Equatable, Sendable {
        public let id: UUID
        /// Seconds from the start of capture.
        public internal(set) var start: Double
        public internal(set) var end: Double
        /// Apple's words: the final line once it arrived.
        public internal(set) var apple: String
        /// Whisper's words, once its second listen is done.
        public internal(set) var whisper: String?
        public internal(set) var categories: [ReadingCategory]
        /// A cue was given. False for harsh words only Whisper heard, which never cue.
        public internal(set) var cued: Bool
        public internal(set) var onlyWhisper: [String]
        public internal(set) var verdict: Verdict?
        /// The attributed pieces (utterance ids) this moment was recorded from, so Whisper's
        /// re-read of a piece reaches its own moment and not a neighbour's.
        public internal(set) var pieces: [UUID] = []

        /// The words to quote: Whisper's when its second listen is done, else Apple's.
        public var quote: String { whisper ?? apple }

        /// Whisper's words differ from Apple's beyond spacing and punctuation.
        public var heardDifferently: Bool {
            guard let whisper else { return false }
            return SecondReading.squash(whisper) != SecondReading.squash(apple)
        }

        /// The harsh words either recogniser heard here, which the user can mute from the recap.
        public func harshWords(_ words: PersonalWords = PersonalWords()) -> [String] {
            (WordChoiceReader.harshWords(in: quote, words: words) + WordChoiceReader.harshWords(in: apple, words: words))
                .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        }
    }

    public private(set) var moments: [Moment] = []
    /// Set when the session was a practice run.
    public var practice: PracticeScenario?
    /// Length of the session in seconds.
    public var duration: Double = 0

    public init(practice: PracticeScenario? = nil) {
        self.practice = practice
    }

    /// Moments closer than this are one moment: an early cue and the final line it came from.
    public static let mergeGap = 0.5

    /// Records a flagged moment. One that overlaps an earlier moment updates it: the final line's
    /// words replace the in-progress piece and the categories are joined.
    /// `piece` is the attributed piece the cue came from, when it came from a final line.
    @discardableResult
    public mutating func recordCue(start: Double, end: Double, text: String, categories: [ReadingCategory], piece: UUID? = nil) -> UUID {
        if let i = index(overlapping: start, end) {
            moments[i].start = min(moments[i].start, start)
            moments[i].end = max(moments[i].end, end)
            moments[i].apple = text
            moments[i].cued = true
            let joined = moments[i].categories
            moments[i].categories = ReadingCategory.allCases.filter { joined.contains($0) || categories.contains($0) }
            if let piece, !moments[i].pieces.contains(piece) { moments[i].pieces.append(piece) }
            return moments[i].id
        }
        let moment = Moment(id: UUID(), start: start, end: end, apple: text, whisper: nil, categories: categories,
                            cued: true, onlyWhisper: [], verdict: nil, pieces: piece.map { [$0] } ?? [])
        insert(moment)
        return moment.id
    }

    /// Applies Whisper's second listen of the piece from `start` to `end`. The flagged moment of
    /// that piece takes Whisper's words: found by `piece` when given, otherwise by overlap.
    /// Elsewhere, harsh words only Whisper heard become an uncued moment so the user can see what
    /// it caught; they never cue.
    public mutating func applySecondListen(start: Double, end: Double, apple: String, whisper: String, piece: UUID? = nil, words: PersonalWords = PersonalWords()) {
        let comparison = SecondReading.compare(apple: apple, whisper: whisper, words: words)
        let match = if let piece { moments.firstIndex { $0.pieces.contains(piece) } } else { index(overlapping: start, end) }
        if let i = match {
            moments[i].whisper = whisper
            moments[i].onlyWhisper = comparison.onlyWhisper
            return
        }
        guard !comparison.onlyWhisper.isEmpty else { return }
        insert(Moment(id: UUID(), start: start, end: end, apple: apple, whisper: whisper, categories: [.wordChoice],
                      cued: false, onlyWhisper: comparison.onlyWhisper, verdict: nil, pieces: piece.map { [$0] } ?? []))
    }

    public mutating func mark(_ id: UUID, _ verdict: Verdict) {
        guard let i = moments.firstIndex(where: { $0.id == id }) else { return }
        moments[i].verdict = verdict
    }

    public var cueCount: Int { moments.filter(\.cued).count }

    public func cueCount(_ category: ReadingCategory) -> Int {
        moments.filter { $0.cued && $0.categories.contains(category) }.count
    }

    private func index(overlapping start: Double, _ end: Double) -> Int? {
        moments.firstIndex { $0.start < end + Self.mergeGap && start < $0.end + Self.mergeGap }
    }

    private mutating func insert(_ moment: Moment) {
        moments.append(moment)
        moments.sort { $0.start < $1.start }
    }
}

/// Keeps the buzz sparing: at most one every `minimumGap` seconds (research §3, Rhema: one cue at
/// a time with a minimum gap; INTENTIONAL §5: coalesce repeated warnings for one thought). Every
/// hit still slams the needle and counts on the card; only the haptic waits.
public struct CuePacer: Sendable {
    public static let minimumGap = 3.0
    public private(set) var lastBuzz: Double?

    public init() {}

    /// True when a buzz may play at `time` (seconds on a steady clock), and records it.
    public mutating func allowBuzz(at time: Double) -> Bool {
        if let lastBuzz, time - lastBuzz < Self.minimumGap { return false }
        lastBuzz = time
        return true
    }

    public mutating func reset() { lastBuzz = nil }
}

/// Practice alone before a real conversation (research §5.5: rehearsal is what people pay for, and
/// with nobody else talking there is no other voice to mistake for the user's). Each situation
/// proposes the settings it calls for; the reading and the gate are the same as in a conversation.
public enum PracticeScenario: String, CaseIterable, Codable, Sendable {
    case askManager
    case requestJunior
    case declineColleague
    case disagreeFriend

    public var settings: CategorySettings {
        switch self {
        case .askManager, .requestJunior, .declineColleague: .niceDefault
        case .disagreeFriend: CategorySettings(register: .casualFine, wordChoice: .gentle)
        }
    }

    public var titleKey: CopyKey {
        switch self {
        case .askManager: .practiceAskManagerTitle
        case .requestJunior: .practiceRequestJuniorTitle
        case .declineColleague: .practiceDeclineTitle
        case .disagreeFriend: .practiceDisagreeTitle
        }
    }

    public var promptKey: CopyKey {
        switch self {
        case .askManager: .practiceAskManagerPrompt
        case .requestJunior: .practiceRequestJuniorPrompt
        case .declineColleague: .practiceDeclinePrompt
        case .disagreeFriend: .practiceDisagreePrompt
        }
    }
}
