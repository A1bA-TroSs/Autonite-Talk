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

@Test func smoothingMergesShortPiecesWithoutCreatingUserSpeech() {
    let pieces = [
        VoicePiece(text: "a", start: 0, end: 2, slot: 1, label: .other, confidence: 0.9, overlapped: false),
        VoicePiece(text: "b", start: 2, end: 2.3, slot: 0, label: .user, confidence: 1, overlapped: false),
        VoicePiece(text: "c", start: 2.3, end: 4, slot: 0, label: .user, confidence: 0.9, overlapped: false),
        VoicePiece(text: "d", start: 4, end: 6, slot: 0, label: .user, confidence: 0.8, overlapped: false),
    ]
    let smoothed = VoiceSplitter.smooth(pieces)
    #expect(smoothed.map(\.text) == ["a b", "c", "d"])
    #expect(smoothed.map(\.label) == [.unknown, .user, .user])
    #expect(smoothed[0].confidence == 0)
}

@Test func verifierDropsUserPiecesThatDoNotMatchTheEnrolledVoice() {
    let piece = VoicePiece(text: "x", start: 0, end: 2, slot: 0, label: .user, confidence: 1, overlapped: false)
    #expect(VoiceVerifier.verify(piece, similarity: 0.8).label == .user)
    let short = VoicePiece(text: "x", start: 0, end: 1, slot: 0, label: .user, confidence: 1, overlapped: false)
    #expect(VoiceVerifier.verify(short, similarity: 0.9).label == .unknown)
    #expect(VoiceVerifier.verify(piece, similarity: 0.2).label == .unknown)
    #expect(VoiceVerifier.verify(piece, similarity: nil).label == .unknown)
    let other = VoicePiece(text: "y", start: 0, end: 1, slot: 1, label: .other, confidence: 0.9, overlapped: false)
    #expect(VoiceVerifier.verify(other, similarity: nil).label == .other)
    #expect(VoiceVerifier.cosineSimilarity([1, 0], [1, 0]) == 1)
    #expect(VoiceVerifier.cosineSimilarity([1, 0], [0, 1]) == 0)
}

// MARK: Pass 1 P1: enrolment

@Test func enrollmentScriptsHaveRequiredRegisterSplit() {
    #expect(EnrollmentScript.english.count == 8)
    #expect(EnrollmentScript.korean.count == 8)
    let polite = EnrollmentScript.korean.map(EnrollmentScript.endsPolite)
    #expect(polite == [true, true, true, true, false, false, false, false])
}

@Test func enrollmentFlowRequiresConsentAndRecovery() {
    // Declining consent never reaches done, whatever else is tapped.
    var declined = EnrollmentFlow()
    declined.answerConsent(false)
    declined.confirmPlacement()
    declined.finishSentence()
    declined.finishPhraseCheck(passed: true)
    declined.finishBaseline()
    #expect(declined.step == .declined)

    var flow = EnrollmentFlow()
    flow.confirmPlacement()
    #expect(flow.step == .consent)
    flow.answerConsent(true)
    flow.confirmPlacement()
    for _ in 0..<8 { flow.finishSentence() }
    #expect(flow.step == .freeSpeech)
    let tooShort = flow.finishFreeSpeech(seconds: 12)
    #expect(!tooShort)
    let accepted = flow.finishFreeSpeech(seconds: 25)
    #expect(accepted)
    // A failed check asks for two more sentences, then checks again.
    flow.finishPhraseCheck(passed: false)
    #expect(flow.step == .extraSentence(0))
    flow.finishSentence()
    flow.finishSentence()
    #expect(flow.step == .phraseCheck)
    flow.finishPhraseCheck(passed: true)
    flow.finishBaseline()
    #expect(flow.step == .done)

    flow.withdrawConsent()
    #expect(flow.step == .declined)
}

// MARK: Pass 1 P2: voice profile

@Test func voiceProfileStoreSurvivesRelaunchAndDeletes() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("profile-\(UUID().uuidString)")
    let profile = VoiceProfile(enrollmentAudio: [0.1, -0.2, 0.3], sampleRate: 16_000, voiceprint: [0.6, 0.8])
    try VoiceProfileStore(directory: folder).save(profile)
    // A fresh store, as after a relaunch, reads the same profile.
    #expect(try VoiceProfileStore(directory: folder).load() == profile)
    try VoiceProfileStore(directory: folder).delete()
    #expect(!FileManager.default.fileExists(atPath: folder.path))
    #expect(try VoiceProfileStore(directory: folder).load() == nil)
}

private final class FakeEnroller: SpeakerEnrolling {
    var received: VoiceProfile?
    func enroll(_ profile: VoiceProfile) throws -> Int? {
        received = profile
        return profile.enrollmentAudio.isEmpty ? nil : 0
    }
}

@Test func diarizerAdapterAcceptsStoredProfile() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("profile-\(UUID().uuidString)")
    defer { try? VoiceProfileStore(directory: folder).delete() }
    let store = VoiceProfileStore(directory: folder)
    try store.save(VoiceProfile(enrollmentAudio: [0.1, 0.2], sampleRate: 48_000, voiceprint: [1, 0]))
    let enroller = FakeEnroller()
    let slot = try enroller.enroll(#require(try store.load()))
    #expect(slot == 0)
    #expect(enroller.received?.voiceprint == [1, 0])
}

// MARK: Pass 1 P3: Korean register

@Test func koreanRegisterThirtyPhraseFixture() {
    // (phrase, reading when 존댓말 is expected)
    let fixture: [(String, Reading)] = [
        // 하십시오체
        ("그 부분은 조금 더 확인해 보고 다시 말씀드리겠습니다.", .aligned),
        ("회의는 세 시에 시작합니다.", .aligned),
        ("이 자료가 맞습니까?", .aligned),
        ("잠시만 기다려 주십시오.", .aligned),
        ("제 생각은 조금 다릅니다", .aligned),
        ("그건 제 실수가 아닙니다.", .aligned),
        ("내일 다시 연락드리겠습니다.", .aligned),
        // 해요체
        ("내일 회의 자료는 제가 오전까지 정리해서 보내 드릴게요.", .aligned),
        ("팀장님, 일정이 빠듯해서 금요일은 어려울 것 같아요.", .aligned),
        ("혹시 쓰신 보고서를 같이 볼 수 있을까요?", .aligned),
        ("그건 좀 어렵죠.", .aligned),
        ("지금 가고 있어요", .aligned),
        ("네.", .aligned),
        ("저도 그렇게 생각해요. 근데 시간이 부족해요.", .aligned),
        // 반말
        ("아까 내가 좀 딱딱하게 말했지? 미안, 그런 뜻 아니었어.", .check),
        ("그냥 네 생각을 솔직하게 듣고 싶어서 물어본 거야.", .check),
        ("주말에 시간 괜찮으면 같이 밥이나 먹자.", .check),
        ("의자 좀 저쪽으로 치워 줄래? 짐 놓을 데가 없어.", .check),
        ("그거 내가 할게.", .check),
        ("왜 그렇게 늦었냐?", .check),
        ("빨리 와 봐.", .check),
        ("그건 아니다.", .check),
        ("이거 진짜 맛있네.", .check),
        ("너 어제 거기 갔잖아.", .check),
        // Mixed: one 반말 slip in polite speech is a check.
        ("네, 알겠습니다. 근데 그건 좀 아니야.", .check),
        ("저는 괜찮아요. 너는 어때?", .check),
        ("확인했습니다. 내일 보자.", .check),
        // No clear final ending: abstain.
        ("그리고 적당히 즐기고", .unknown),
        ("그러니까", .unknown),
        ("어", .unknown),
        ("회의 자료", .unknown),
        ("내가 생각하기에는 그게 좀 그래서", .unknown),
        ("hello there", .unknown),
    ]
    #expect(fixture.count >= 30)
    for (phrase, expected) in fixture {
        #expect(KoreanRegisterReader.read(phrase, setting: .politeExpected).reading == expected, "\(phrase)")
    }
    // A confirmed relaxed setting never checks; abstentions stay unknown.
    for (phrase, expected) in fixture {
        let relaxed = KoreanRegisterReader.read(phrase, setting: .casualFine).reading
        #expect(relaxed == (expected == .unknown ? .unknown : .aligned), "\(phrase)")
    }
    #expect(KoreanRegisterReader.read("회의는 세 시에 시작합니다.", setting: .politeExpected).found == [.formal])
    #expect(KoreanRegisterReader.read("지금 가고 있어요", setting: .politeExpected).found == [.polite])
}

// MARK: Pass 1 P4: English formality and word choice

@Test func englishRegisterTwentyPhraseFixture() {
    // (phrase, reading when formal speech is expected)
    let fixture: [(String, Reading)] = [
        ("Could you walk me through the numbers again before Thursday?", .aligned),
        ("Would you mind sending the file later today?", .aligned),
        ("Thank you, that helps.", .aligned),
        ("Please take a seat.", .aligned),
        ("I'd appreciate a second look at the draft.", .aligned),
        ("Sorry, I missed that.", .aligned),
        ("That's fair. Let's keep the budget where it is for now.", .aligned),
        ("Which version should we show the vendor on Monday?", .aligned),
        ("I think the bigger issue is the schedule.", .aligned),
        ("We both want this to work.", .aligned),
        ("Yeah, I'm gonna skip that meeting.", .check),
        ("Nah, that's not happening.", .check),
        ("Dude, just send it.", .check),
        ("Whatever, do what you want.", .check),
        ("I wanna wrap this up.", .check),
        ("We gotta move faster on this.", .check),
        ("Yep.", .check),
        ("Sure.", .unknown),
        ("Okay then.", .unknown),
        ("Hmm", .unknown),
        ("...", .unknown),
    ]
    #expect(fixture.count >= 20)
    for (phrase, expected) in fixture {
        #expect(EnglishRegisterReader.read(phrase, setting: .politeExpected) == expected, "\(phrase)")
        let relaxed = EnglishRegisterReader.read(phrase, setting: .casualFine)
        #expect(relaxed == (expected == .unknown ? .unknown : .aligned), "\(phrase)")
    }
}

@Test func wordChoiceRespectsBluntIntention() {
    let harsh = ["That idea is stupid.", "Shut up for a second.", "너 진짜 멍청하다.", "그만 좀 해, 짜증나.", "You never listen."]
    let mild = ["I see it differently.", "그건 좀 다르게 생각해요.", "Let's try another way."]
    for phrase in harsh {
        #expect(WordChoiceReader.read(phrase, setting: .gentle) == .check, "\(phrase)")
        #expect(WordChoiceReader.read(phrase, setting: .bluntFine) == .aligned, "\(phrase)")
    }
    for phrase in mild {
        #expect(WordChoiceReader.read(phrase, setting: .gentle) == .aligned, "\(phrase)")
    }
    // "hell" is matched as a word, not inside "hello".
    #expect(WordChoiceReader.read("Hello there", setting: .gentle) == .aligned)
    #expect(WordChoiceReader.harshWords(in: "그만 좀 해, 짜증나.") == ["짜증나"])
}
