import Foundation
import Testing
@testable import AutoniteCore

private func utterance(level: Double?, truth: SpeakerLabel?, predicted: SpeakerLabel = .unknown, confidence: Double = 0) -> Utterance {
    Utterance(start: 0, end: 1, text: "x", latency: 0.5, meanLevelDB: level, predicted: predicted, predictionConfidence: confidence, groundTruth: truth)
}

@Test func latencyPercentilesUseNearestRank() {
    let stats = LatencyStats(samples: [0.4, 0.1, 0.3, 0.2, 1.0])
    #expect(stats.count == 5)
    #expect(stats.median == 0.3)
    #expect(stats.p90 == 1.0)
    #expect(stats.max == 1.0)
    #expect(LatencyStats(samples: []).median == nil)
}

@Test func levelTimelineAveragesOnlyTheWindow() {
    let timeline = LevelTimeline()
    timeline.append(time: 0.5, db: -40)
    timeline.append(time: 1.5, db: -20)
    timeline.append(time: 2.5, db: -30)
    #expect(timeline.meanDB(from: 1, to: 3) == -25)
    #expect(timeline.meanDB(from: 5, to: 6) == nil)
}

@Test func attributorNeedsBothSpeakersLabelled() {
    #expect(LevelAttributor(labelled: [utterance(level: -20, truth: .user)]) == nil)
}

@Test func attributorAbstainsWhenVoicesAreNotSeparated() throws {
    let attributor = try #require(LevelAttributor(labelled: [
        utterance(level: -20, truth: .user),
        utterance(level: -21, truth: .other),
    ]))
    #expect(attributor.predict(levelDB: -20).0 == .unknown)
}

@Test func attributorPicksTheNearerSpeaker() throws {
    let attributor = try #require(LevelAttributor(labelled: [
        utterance(level: -20, truth: .user),
        utterance(level: -32, truth: .other),
    ]))
    let (near, nearConfidence) = attributor.predict(levelDB: -19)
    #expect(near == .user)
    #expect(nearConfidence == 1)
    let (far, _) = attributor.predict(levelDB: -31)
    #expect(far == .other)
    // Exactly at the midpoint carries no confidence.
    #expect(attributor.predict(levelDB: -26).1 == 0)
}

@Test func scoreCountsOtherSpeakerCalledUser() {
    let utterances = [
        utterance(level: -20, truth: .user),
        utterance(level: -21, truth: .user),
        utterance(level: -32, truth: .other),
        utterance(level: -33, truth: .other),
        utterance(level: -19, truth: .other), // loud other speaker: the dangerous case
    ]
    let score = AttributionScore(utterances: utterances, minimumConfidence: 0)
    #expect(score.labelled == 5)
    #expect(score.otherTotal == 3)
    #expect(score.otherAsUser == 1)
}

@Test func gateOnlyDeliversConfidentUserSpeech() {
    #expect(CueGate.evaluate(utterance(level: nil, truth: nil, predicted: .user, confidence: 0.9)) == .deliver)
    #expect(CueGate.evaluate(utterance(level: nil, truth: nil, predicted: .user, confidence: 0.2)) != .deliver)
    #expect(CueGate.evaluate(utterance(level: nil, truth: nil, predicted: .other, confidence: 1)) != .deliver)
    #expect(CueGate.evaluate(utterance(level: nil, truth: nil, predicted: .unknown, confidence: 1)) != .deliver)
}

@Test func reportEncodesToJSON() {
    var report = FeasibilityReport(deviceModel: "iPhone17,1", osVersion: "26.1", transcriberAvailable: true, hapticsSupported: true)
    report.hapticTrials.append(.init(placement: .tableFaceUp, duringRecording: true, felt: false))
    #expect(report.jsonString().contains("\"tableFaceUp\"") == false)
    #expect(report.jsonString().contains("table, face up"))
}

// MARK: Voice split

private func word(_ text: String, _ start: Double, _ end: Double) -> WordSpan {
    WordSpan(text: text, start: start, end: end)
}

@Test func splitterCutsALineWhereTheSpeakerChanges() {
    // "Is it louder? No, it just buzzes." spoken by the other person, then the user.
    let words = [word("Is", 0.0, 0.3), word(" it", 0.3, 0.5), word(" louder?", 0.5, 1.0),
                 word(" No,", 1.2, 1.5), word(" it", 1.5, 1.7), word(" buzzes.", 1.7, 2.2)]
    let turns = [SpeakerTurn(slot: 1, start: 0.0, end: 1.1), SpeakerTurn(slot: 0, start: 1.15, end: 2.3)]
    let pieces = VoiceSplitter.split(words: words, turns: turns, userSlot: 0)
    #expect(pieces.map(\.text) == ["Is it louder?", "No, it buzzes."])
    #expect(pieces.map(\.label) == [.other, .user])
    #expect(pieces[1].confidence == 1)
}

@Test func splitterHoldsBackOverlappingSpeech() {
    let words = [word("wait", 0.0, 0.5), word(" what", 0.5, 1.0)]
    let turns = [SpeakerTurn(slot: 0, start: 0.0, end: 1.0), SpeakerTurn(slot: 1, start: 0.4, end: 1.0)]
    let pieces = VoiceSplitter.split(words: words, turns: turns, userSlot: 0)
    #expect(pieces.map(\.label) == [.user, .unknown])
    #expect(pieces[1].overlapped)
    #expect(CueGate.evaluate(Utterance(start: 0.5, end: 1, text: "what", latency: 0, meanLevelDB: nil,
                                       predicted: pieces[1].label, predictionConfidence: pieces[1].confidence)) != .deliver)
}

@Test func splitterCallsNobodyTheUserWithoutEnrolment() {
    let pieces = VoiceSplitter.split(words: [word("hi", 0, 0.5)], turns: [SpeakerTurn(slot: 0, start: 0, end: 1)], userSlot: nil)
    #expect(pieces.map(\.label) == [.unknown])
}

@Test func splitterLeavesUncoveredWordsUnknown() {
    let pieces = VoiceSplitter.split(words: [word("hi", 5, 5.5)], turns: [SpeakerTurn(slot: 0, start: 0, end: 1)], userSlot: 0)
    #expect(pieces.map(\.label) == [.unknown])
    #expect(pieces[0].confidence == 0)
}

@Test func recordedScoreCountsOtherCalledMe() {
    let pieces = [
        utterance(level: nil, truth: .user, predicted: .user, confidence: 0.9),
        utterance(level: nil, truth: .other, predicted: .user, confidence: 0.8),
        utterance(level: nil, truth: .other, predicted: .unknown),
    ]
    let score = AttributionScore(utterances: pieces, method: .voice)
    #expect(score.labelled == 3)
    #expect(score.committed == 2)
    #expect(score.correct == 1)
    #expect(score.otherAsUser == 1)
    #expect(score.otherTotal == 2)
}
