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
