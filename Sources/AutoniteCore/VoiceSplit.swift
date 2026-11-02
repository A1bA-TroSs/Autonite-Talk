import Foundation

/// One transcribed word (or word run) with its audio time, in seconds from the start of capture.
public struct WordSpan: Codable, Sendable, Equatable {
    public var text: String
    public let start: Double
    public let end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// A stretch of time in which one diarizer slot was speaking.
public struct SpeakerTurn: Codable, Sendable, Equatable {
    public let slot: Int
    public let start: Double
    public let end: Double

    public init(slot: Int, start: Double, end: Double) {
        self.slot = slot
        self.start = start
        self.end = end
    }
}

/// A run of words assigned to one speaker.
public struct VoicePiece: Sendable, Equatable {
    public let text: String
    public let start: Double
    public let end: Double
    public let slot: Int?
    public let label: SpeakerLabel
    /// Mean share of the piece's words covered by its speaker alone, 0...1.
    public let confidence: Double
    public let overlapped: Bool

    public init(text: String, start: Double, end: Double, slot: Int?, label: SpeakerLabel, confidence: Double, overlapped: Bool) {
        self.text = text
        self.start = start
        self.end = end
        self.slot = slot
        self.label = label
        self.confidence = confidence
        self.overlapped = overlapped
    }

    public var duration: Double { end - start }
}

/// Cuts a transcript line where the speaker changes, using word times and a diarizer timeline.
///
/// Speech where two slots are active at once is `unknown`, so `CueGate` never fires on it.
/// Without an enrolled user slot nothing is called `user`.
public enum VoiceSplitter {
    /// A second slot covering at least this share of a word makes the word overlapped.
    public static let overlapShare = 0.3

    public static func split(words: [WordSpan], turns: [SpeakerTurn], userSlot: Int?) -> [VoicePiece] {
        struct Assignment: Equatable {
            let slot: Int?
            let overlapped: Bool
        }

        var pieces: [VoicePiece] = []
        var current: (assignment: Assignment, words: [WordSpan], coverage: [Double])?

        func flush() {
            guard let run = current, let first = run.words.first, let last = run.words.last else { return }
            let text = run.words.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            let confidence = run.assignment.overlapped || run.assignment.slot == nil
                ? 0 : run.coverage.reduce(0, +) / Double(run.coverage.count)
            let label: SpeakerLabel
            if run.assignment.overlapped || run.assignment.slot == nil || userSlot == nil {
                label = .unknown
            } else {
                label = run.assignment.slot == userSlot ? .user : .other
            }
            if !text.isEmpty {
                pieces.append(VoicePiece(
                    text: text, start: first.start, end: last.end, slot: run.assignment.slot,
                    label: label, confidence: label == .unknown ? 0 : confidence, overlapped: run.assignment.overlapped
                ))
            }
            current = nil
        }

        for word in words {
            let shares = coverage(of: word, by: turns)
            let ranked = shares.sorted { $0.value > $1.value }
            let assignment: Assignment
            let share: Double
            if let top = ranked.first, top.value > 0 {
                let overlapped = ranked.count > 1 && ranked[1].value >= overlapShare
                assignment = Assignment(slot: overlapped ? nil : top.key, overlapped: overlapped)
                share = top.value
            } else {
                assignment = Assignment(slot: nil, overlapped: false)
                share = 0
            }
            if current?.assignment != assignment { flush() }
            if current == nil { current = (assignment, [], []) }
            current?.words.append(word)
            current?.coverage.append(share)
        }
        flush()
        return pieces
    }

    /// Share of the word's duration that each slot covers, 0...1.
    static func coverage(of word: WordSpan, by turns: [SpeakerTurn]) -> [Int: Double] {
        // Words with no duration are treated as a 20 ms window around their time.
        let start = word.end > word.start ? word.start : word.start - 0.01
        let end = word.end > word.start ? word.end : word.start + 0.01
        let duration = end - start
        var covered: [Int: Double] = [:]
        for turn in turns {
            let overlap = min(end, turn.end) - max(start, turn.start)
            if overlap > 0 { covered[turn.slot, default: 0] += overlap }
        }
        return covered.mapValues { min($0 / duration, 1) }
    }
}

extension VoiceSplitter {
    /// Pieces shorter than this are merged into a neighbour.
    public static let minimumPieceSeconds = 0.5

    /// Merges pieces shorter than `minimumPieceSeconds` into the piece before them (or after,
    /// for the first). Two pieces with different labels merge as `unknown`, so smoothing can
    /// only take speech away from the user, never give it.
    public static func smooth(_ pieces: [VoicePiece]) -> [VoicePiece] {
        var result: [VoicePiece] = []
        for piece in pieces {
            if let last = result.last, last.duration < minimumPieceSeconds || piece.duration < minimumPieceSeconds {
                result[result.count - 1] = merge(last, piece)
            } else {
                result.append(piece)
            }
        }
        return result
    }

    static func merge(_ a: VoicePiece, _ b: VoicePiece) -> VoicePiece {
        let label = a.label == b.label ? a.label : .unknown
        let total = a.duration + b.duration
        let confidence = label == .unknown || total <= 0
            ? 0 : (a.confidence * a.duration + b.confidence * b.duration) / total
        return VoicePiece(
            text: a.text + " " + b.text, start: a.start, end: b.end,
            slot: a.slot == b.slot ? a.slot : nil, label: label,
            confidence: confidence, overlapped: a.overlapped || b.overlapped
        )
    }
}

/// Checks that speech the diarizer put in the user's slot sounds like the enrolled voice.
///
/// The diarizer only tracks which slot is talking. When the user goes quiet under a louder
/// voice, that voice can drift into the user's slot (Pass 0 run, 2026-10-29). Each `user`
/// piece is kept only when its voiceprint is close enough to the enrolment's.
public enum VoiceVerifier {
    /// Cosine similarity a `user` piece needs to stay `user`. On 2026-11-01 clean solo speech scored
    /// 0.69-0.82 and slot-Me pieces under a podcast 0.29-0.59, so 0.65 sits between them. Tune it from
    /// tagged runs so other voices give no false Me.
    public static let threshold = 0.65
    /// Voiceprints from shorter speech are unreliable (ECAPA EER 7% at 1 s, 3% at 1.5 s), so a
    /// shorter `user` piece is held back rather than verified. See the 2026-10-31 teardown.
    public static let minimumSeconds = 1.5

    /// Relabels a `user` piece as `unknown` when it is too short to verify, or its similarity
    /// is missing or below the threshold.
    ///
    /// `evidence` is the span the similarity was measured over (see `evidenceWindow`); it defaults
    /// to the piece itself.
    public static func verify(_ piece: VoicePiece, similarity: Double?, evidence: ClosedRange<Double>? = nil) -> VoicePiece {
        guard piece.label == .user else { return piece }
        let seconds = evidence.map { $0.upperBound - $0.lowerBound } ?? piece.duration
        if seconds >= minimumSeconds, let similarity, similarity >= threshold { return piece }
        return VoicePiece(
            text: piece.text, start: piece.start, end: piece.end, slot: piece.slot,
            label: .unknown, confidence: 0, overlapped: piece.overlapped
        )
    }

    /// The span to measure a `user` piece's voiceprint over. A piece of at least `minimumSeconds`
    /// is measured on its own. A shorter one (a lone word such as a swear) is measured over the
    /// user slot's continuous speech around it, so long as no other slot talks anywhere in that
    /// span; otherwise it stays the piece alone, and `verify` then holds it back as too short.
    public static func evidenceWindow(for piece: VoicePiece, turns: [SpeakerTurn], userSlot: Int?) -> ClosedRange<Double> {
        let own = piece.start...max(piece.start, piece.end)
        guard piece.label == .user, piece.duration < minimumSeconds, let userSlot else { return own }
        let mine = turns.filter { $0.slot == userSlot }.sorted { $0.start < $1.start }
        guard var window = mine.first(where: { $0.start <= piece.end && $0.end >= piece.start }).map({ $0.start...$0.end }) else { return own }
        // Join the user's turns that touch this one (gaps under `joinGap`).
        var grew = true
        while grew {
            grew = false
            for turn in mine where turn.end >= window.lowerBound - joinGap && turn.start <= window.upperBound + joinGap {
                let joined = min(window.lowerBound, turn.start)...max(window.upperBound, turn.end)
                if joined != window { window = joined; grew = true }
            }
        }
        let others = turns.contains { $0.slot != userSlot && $0.start < window.upperBound && $0.end > window.lowerBound }
        return others ? own : min(window.lowerBound, own.lowerBound)...max(window.upperBound, own.upperBound)
    }

    /// The stretch of audio to verify while the user is still talking: the last `span` seconds up to
    /// the diarizer's newest turn. Returns nil unless the user's slot covers at least
    /// `minimumSeconds` of it and no other slot speaks anywhere in it.
    public static func recentUserWindow(turns: [SpeakerTurn], userSlot: Int?, span: Double = 3) -> ClosedRange<Double>? {
        guard let userSlot, let now = turns.map(\.end).max() else { return nil }
        let window = max(0, now - span)...now
        let inside = turns.filter { $0.start < window.upperBound && $0.end > window.lowerBound }
        guard !inside.contains(where: { $0.slot != userSlot }) else { return nil }
        let mine = inside.map { max($0.start, window.lowerBound)...min($0.end, window.upperBound) }
        let covered = mine.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
        guard covered >= minimumSeconds, let first = mine.map(\.lowerBound).min(), let last = mine.map(\.upperBound).max() else { return nil }
        return first...last
    }

    /// User turns closer than this count as one stretch of speech.
    public static let joinGap = 0.3

    /// A higher bar for speech the diarizer did not put in the user's slot. Its slots drift when the
    /// user changes tone, so a piece that sounds clearly like the user is reclaimed, but only above
    /// this, which sits over every other-voice score seen so far (0.29-0.59 on 2026-11-01).
    public static let strictThreshold = 0.72

    /// The closest of several enrolled voiceprints, so varied tones and pitches all match.
    public static func bestMatch(_ print: [Float], against prints: [[Float]]) -> Double? {
        prints.compactMap { cosineSimilarity(print, $0) }.max()
    }

    /// Relabels a non-overlapped `other` piece as `user` when it is long enough and clearly the
    /// enrolled voice (at least `strictThreshold`). Everything else is returned unchanged.
    public static func reclaim(_ piece: VoicePiece, similarity: Double?, evidence: ClosedRange<Double>? = nil) -> VoicePiece {
        guard piece.label == .other, !piece.overlapped, let similarity, similarity >= strictThreshold else { return piece }
        let seconds = evidence.map { $0.upperBound - $0.lowerBound } ?? piece.duration
        guard seconds >= minimumSeconds else { return piece }
        return VoicePiece(text: piece.text, start: piece.start, end: piece.end, slot: piece.slot,
                          label: .user, confidence: 1, overlapped: false)
    }

    /// The last `span` seconds of speech when no two slots talk at the same moment in it and there is
    /// at least `minimumSeconds` of speech. Used, with `strictThreshold`, when the diarizer has put
    /// some of the user's own speech in another slot.
    public static func recentSpeechWindow(turns: [SpeakerTurn], span: Double = 3) -> ClosedRange<Double>? {
        guard let now = turns.map(\.end).max() else { return nil }
        let window = max(0, now - span)...now
        let inside = turns.filter { $0.start < window.upperBound && $0.end > window.lowerBound }
            .map { SpeakerTurn(slot: $0.slot, start: max($0.start, window.lowerBound), end: min($0.end, window.upperBound)) }
        for a in inside {
            for b in inside where b.slot != a.slot && b.start < a.end && a.start < b.end { return nil }
        }
        let covered = inside.reduce(0) { $0 + ($1.end - $1.start) }
        guard covered >= minimumSeconds, let first = inside.map(\.start).min(), let last = inside.map(\.end).max() else { return nil }
        return first...last
    }

    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for (x, y) in zip(a, b) {
            dot += Double(x) * Double(y)
            normA += Double(x) * Double(x)
            normB += Double(y) * Double(y)
        }
        guard normA > 0, normB > 0 else { return nil }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }
}
