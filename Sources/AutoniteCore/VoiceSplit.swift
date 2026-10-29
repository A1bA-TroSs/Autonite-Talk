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
    /// Cosine similarity a `user` piece needs to stay `user`. Starting value; tune it from
    /// tagged runs so other voices give no false Me.
    public static let threshold = 0.5

    /// Relabels a `user` piece as `unknown` when its similarity is missing or below the threshold.
    public static func verify(_ piece: VoicePiece, similarity: Double?) -> VoicePiece {
        guard piece.label == .user else { return piece }
        if let similarity, similarity >= threshold { return piece }
        return VoicePiece(
            text: piece.text, start: piece.start, end: piece.end, slot: piece.slot,
            label: .unknown, confidence: 0, overlapped: piece.overlapped
        )
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
