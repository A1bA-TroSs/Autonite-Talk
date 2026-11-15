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

@Test func shortUserWordIsVerifiedOverItsSurroundingTurn() {
    let swear = VoicePiece(text: "씨발", start: 3.0, end: 3.5, slot: 0, label: .user, confidence: 1, overlapped: false)
    // Alone in a short turn: too little audio, so it stays the piece and is held back.
    let lone = VoiceVerifier.evidenceWindow(for: swear, turns: [SpeakerTurn(slot: 0, start: 2.9, end: 3.6)], userSlot: 0)
    #expect(VoiceVerifier.verify(swear, similarity: 0.9, evidence: lone).label == .unknown)
    // Inside the user's own longer speech (two touching turns): measured over all of it.
    let turns = [SpeakerTurn(slot: 0, start: 1.0, end: 3.2), SpeakerTurn(slot: 0, start: 3.3, end: 4.0)]
    let window = VoiceVerifier.evidenceWindow(for: swear, turns: turns, userSlot: 0)
    #expect(window == 1.0...4.0)
    #expect(VoiceVerifier.verify(swear, similarity: 0.8, evidence: window).label == .user)
    #expect(VoiceVerifier.verify(swear, similarity: 0.5, evidence: window).label == .unknown)
    // Anyone else talking in that stretch keeps the window to the piece alone.
    let crowded = turns + [SpeakerTurn(slot: 1, start: 1.5, end: 2.0)]
    #expect(VoiceVerifier.evidenceWindow(for: swear, turns: crowded, userSlot: 0) == 3.0...3.5)
    // Other speakers' pieces are never widened.
    let theirs = VoicePiece(text: "x", start: 3.0, end: 3.5, slot: 1, label: .other, confidence: 1, overlapped: false)
    #expect(VoiceVerifier.evidenceWindow(for: theirs, turns: turns, userSlot: 0) == 3.0...3.5)
}

@Test func earlyReaderCuesSettledMismatchesOnce() {
    var early = EarlyReader()
    let settings = CategorySettings.niceDefault
    // A half-said trailing sentence is not read for register.
    #expect(!early.hasNewMismatch("그거 내가 할", language: .korean, settings: settings))
    // A harsh word counts as soon as it appears.
    #expect(early.hasNewMismatch("아 씨발 이거", language: .korean, settings: settings))
    early.markCued("아 씨발 이거", language: .korean, settings: settings)
    #expect(!early.hasNewMismatch("아 씨발 이거 진짜", language: .korean, settings: settings))
    // The same swear again later in one long sentence is a new hit.
    #expect(early.hasNewMismatch("아 씨발 이거 진짜 왜 이래 씨발", language: .korean, settings: settings))
    // A closed casual sentence is a new hit.
    #expect(early.hasNewMismatch("아 씨발 이거 진짜 별로야. 그리고", language: .korean, settings: settings))
    early.lineFinished()
    #expect(early.cuedHits == 0)
    // After a short pause the unfinished clause counts: its ending is read for register.
    #expect(!early.hasNewMismatch("그거 내가 할게", language: .korean, settings: settings))
    #expect(early.hasNewMismatch("그거 내가 할게", language: .korean, settings: settings, closed: true))
    #expect(!early.hasNewMismatch("그거 제가 할게요", language: .korean, settings: settings, closed: true))
    // Blunt and casual settings never cue early.
    let relaxed = CategorySettings(register: .casualFine, wordChoice: .bluntFine)
    #expect(!EarlyReader().hasNewMismatch("씨발 별로야.", language: .korean, settings: relaxed))
}

@Test func recentUserWindowNeedsTheUserAlone() {
    let solo = [SpeakerTurn(slot: 0, start: 0, end: 4)]
    #expect(VoiceVerifier.recentUserWindow(turns: solo, userSlot: 0) == 1...4)
    let crowded = solo + [SpeakerTurn(slot: 1, start: 3.5, end: 4.2)]
    #expect(VoiceVerifier.recentUserWindow(turns: crowded, userSlot: 0) == nil)
    let brief = [SpeakerTurn(slot: 0, start: 3, end: 4)]
    #expect(VoiceVerifier.recentUserWindow(turns: brief, userSlot: 0) == nil)
    #expect(VoiceVerifier.recentUserWindow(turns: solo, userSlot: nil) == nil)
}

@Test func variedVoiceMatchesTheClosestPrintAndDriftedSlotsAreReclaimedStrictly() {
    #expect(VoiceVerifier.bestMatch([1, 0], against: [[0, 1], [1, 0]]) == 1)
    let drifted = VoicePiece(text: "x", start: 0, end: 2, slot: 1, label: .other, confidence: 1, overlapped: false)
    #expect(VoiceVerifier.reclaim(drifted, similarity: 0.8).label == .user)
    #expect(VoiceVerifier.reclaim(drifted, similarity: 0.68).label == .other)
    let short = VoicePiece(text: "x", start: 0, end: 1, slot: 1, label: .other, confidence: 1, overlapped: false)
    #expect(VoiceVerifier.reclaim(short, similarity: 0.9).label == .other)
    let both = VoicePiece(text: "x", start: 0, end: 2, slot: 1, label: .other, confidence: 1, overlapped: true)
    #expect(VoiceVerifier.reclaim(both, similarity: 0.9).label == .other)
    // Sequential speakers are fine for the speech window; simultaneous ones are not.
    let turns = [SpeakerTurn(slot: 0, start: 0, end: 2), SpeakerTurn(slot: 1, start: 2, end: 4)]
    #expect(VoiceVerifier.recentSpeechWindow(turns: turns) == 1...4)
    #expect(VoiceVerifier.recentSpeechWindow(turns: turns + [SpeakerTurn(slot: 0, start: 3, end: 3.5)]) == nil)
}

@Test func koreanSwearsAreReadAndInnocentWordsAreNot() {
    for phrase in ["아 씨발 진짜", "존나 짜증나네", "이 새끼가", "지랄하지 마", "미친 거 아니야?", "씨팔"] {
        #expect(WordChoiceReader.read(phrase, setting: .gentle) == .check, "\(phrase)")
    }
    for phrase in ["여기가 시발점이에요.", "새끼손가락을 다쳤어요."] {
        #expect(WordChoiceReader.read(phrase, setting: .gentle) == .aligned, "\(phrase)")
    }
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
    let profile = VoiceProfile(voiceprint: [0.6, 0.8], voiceprints: [[0.6, 0.8], [0.8, 0.6]])
    try VoiceProfileStore(directory: folder).save(profile)
    // A fresh store, as after a relaunch, reads the same profile.
    #expect(try VoiceProfileStore(directory: folder).load() == profile)
    try VoiceProfileStore(directory: folder).delete()
    #expect(!FileManager.default.fileExists(atPath: folder.path))
    #expect(try VoiceProfileStore(directory: folder).load() == nil)
}

private final class FakeEnroller: SpeakerEnrolling {
    var received: VoiceProfile?
    func enroll(_ profile: VoiceProfile) throws -> Bool {
        received = profile
        return !profile.voiceprint.isEmpty
    }
}

@Test func diarizerAdapterAcceptsStoredProfile() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("profile-\(UUID().uuidString)")
    defer { try? VoiceProfileStore(directory: folder).delete() }
    let store = VoiceProfileStore(directory: folder)
    try store.save(VoiceProfile(voiceprint: [1, 0]))
    let enroller = FakeEnroller()
    let taken = try enroller.enroll(#require(try store.load()))
    #expect(taken)
    #expect(enroller.received?.voiceprint == [1, 0])
}

// MARK: Rubric M3: no audio on disk

private func plistKeys(_ folder: URL) throws -> Set<String> {
    let data = try Data(contentsOf: folder.appendingPathComponent("voice-profile.plist"))
    let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    return Set(plist.keys)
}

@Test func savedVoiceProfileHoldsNoAudio() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("profile-\(UUID().uuidString)")
    defer { try? VoiceProfileStore(directory: folder).delete() }
    try VoiceProfileStore(directory: folder).save(VoiceProfile(voiceprint: [0.6, 0.8], voiceprints: [[0.6, 0.8]]))
    // Prints and a date, and nothing that could hold samples.
    #expect(try plistKeys(folder) == ["voiceprint", "voiceprints", "createdAt"])
    #expect(!VoiceProfileStore.holdsAudio(try Data(contentsOf: folder.appendingPathComponent("voice-profile.plist"))))
}

/// The shape earlier builds saved, enrolment audio included.
private struct LegacyVoiceProfile: Encodable {
    let enrollmentAudio: [Float]
    let sampleRate: Double
    let voiceprint: [Float]
    let voiceprints: [[Float]]?
    let createdAt: Date
}

@Test func earlierProfileIsRewrittenWithoutItsAudio() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("profile-\(UUID().uuidString)")
    defer { try? VoiceProfileStore(directory: folder).delete() }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let legacy = LegacyVoiceProfile(enrollmentAudio: [0.1, -0.2, 0.3], sampleRate: 16_000, voiceprint: [1, 0],
                                    voiceprints: [[1, 0], [0.9, 0.1]], createdAt: Date(timeIntervalSince1970: 1_700_000_000))
    try encoder.encode(legacy).write(to: folder.appendingPathComponent("voice-profile.plist"))
    #expect(try plistKeys(folder).contains("enrollmentAudio"))

    // Loading keeps the prints and rewrites the file without the samples.
    let loaded = try #require(try VoiceProfileStore(directory: folder).load())
    #expect(loaded == VoiceProfile(voiceprint: [1, 0], voiceprints: [[1, 0], [0.9, 0.1]], createdAt: legacy.createdAt))
    #expect(try plistKeys(folder) == ["voiceprint", "voiceprints", "createdAt"])
    #expect(try VoiceProfileStore(directory: folder).load() == loaded)
}

@Test func userSlotIsFoundByVoiceprintAlone() {
    var finder = UserSlotFinder()
    // The other person talks first; their slot doesn't sound like the user.
    finder.record(slot: 1, window: 0...3, match: 0.41)
    #expect(finder.slot == nil)
    // The user's slot clears the strict bar, well above the other slot.
    finder.record(slot: 0, window: 3...6, match: 0.8)
    #expect(finder.slot == 0)
}

@Test func userSlotNeedsTheStrictBarAndAClearLead() {
    // Below the strict bar: not the user yet, so nothing can cue.
    var weak = UserSlotFinder()
    weak.record(slot: 0, window: 0...2, match: 0.7)
    #expect(weak.slot == nil)
    // Two slots that both sound like the user: too close to call.
    var close = UserSlotFinder()
    close.record(slot: 1, window: 0...2, match: 0.7)
    close.record(slot: 0, window: 2...4, match: 0.78)
    #expect(close.slot == nil)
}

@Test func userSlotHoldsAgainstOneOddStretchAndMovesOnAClearOne() {
    var finder = UserSlotFinder()
    finder.record(slot: 0, window: 0...3, match: 0.8)
    finder.record(slot: 1, window: 3...5, match: 0.3)
    #expect(finder.slot == 0)
    // One stretch of the other slot sounding close doesn't take the user's place.
    finder.record(slot: 1, window: 5...8, match: 0.82)
    #expect(finder.slot == 0)
    // When the slots have clearly swapped, the user's slot follows, after a second clear stretch.
    finder.record(slot: 0, window: 8...11, match: 0.3)
    finder.record(slot: 1, window: 11...14, match: 0.85)
    #expect(finder.slot == 0)
    finder.record(slot: 1, window: 14...17, match: 0.85)
    #expect(finder.slot == 1)
}

@Test func userSlotSearchPrintsClearRecentStretchesOnly() {
    var finder = UserSlotFinder()
    let turns = [
        SpeakerTurn(slot: 0, start: 0, end: 0.6),   // too short to print
        SpeakerTurn(slot: 1, start: 1, end: 6),     // long: its last 3 s are printed
        SpeakerTurn(slot: 0, start: 6.5, end: 8.5),
        SpeakerTurn(slot: 2, start: 7.5, end: 9.5), // talks over slot 0's turn
    ]
    let first = finder.windows(in: turns)
    #expect(first.map(\.slot) == [1])
    #expect(first.first?.window == 3...6)
    // A slot is printed again only after enough new speech: its turn one second longer is
    // skipped, two seconds longer is printed.
    finder.record(slot: 1, window: 3...6, match: 0.4)
    #expect(finder.windows(in: [SpeakerTurn(slot: 1, start: 1, end: 7)]).isEmpty)
    #expect(finder.windows(in: [SpeakerTurn(slot: 1, start: 1, end: 8)]).map(\.window) == [5...8])
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

// MARK: Pass 1 P5: settings, weighting, unmeasured slots

@Test func intentionWeightingTableSuppressesChosenModes() {
    let casual = "그거 내가 할게."
    let harsh = "That idea is stupid."
    let nice = CategorySettings.niceDefault
    #expect(PhraseReader.read(casual, language: .korean, settings: nice)[.register] == .check)
    #expect(PhraseReader.read(harsh, language: .english, settings: nice)[.wordChoice] == .check)
    for register in [RegisterSetting.casualFine, .either] {
        let settings = CategorySettings(register: register, wordChoice: .gentle)
        #expect(PhraseReader.read(casual, language: .korean, settings: settings).mismatches.isEmpty)
    }
    let blunt = CategorySettings(register: .politeExpected, wordChoice: .bluntFine)
    #expect(PhraseReader.read(harsh, language: .english, settings: blunt)[.wordChoice] == .aligned)
}

@Test func confirmedCategorySettingsDriveReaders() {
    var setup = SessionSetup(intentionText: "편하게 얘기하고 싶어")
    // Nice by default: 반말 to anyone is a check until the user relaxes it.
    #expect(PhraseReader.read("내일 보자.", language: .korean, settings: setup.confirmed).mismatches == [.register])
    setup.propose(.closeFriend)
    setup.confirmProposal()
    #expect(PhraseReader.read("내일 보자.", language: .korean, settings: setup.confirmed).mismatches.isEmpty)
    setup.confirm(register: .politeExpected)
    #expect(PhraseReader.read("내일 보자.", language: .korean, settings: setup.confirmed).mismatches == [.register])
    // The free text is kept as written and never changes a setting.
    #expect(setup.intentionText == "편하게 얘기하고 싶어")
}

@Test func unconfirmedPresetDoesNotChangeReadings() {
    var setup = SessionSetup()
    setup.propose(.closeFriend)
    #expect(setup.confirmed == .niceDefault)
    #expect(PhraseReader.read("내일 보자.", language: .korean, settings: setup.confirmed)[.register] == .check)
    setup.discardProposal()
    #expect(setup.proposed == nil)
    #expect(setup.confirmed == .niceDefault)
}

@Test func unmeasuredCategoriesAlwaysAbstain() {
    let phrases = ["그거 내가 할게.", "That idea is stupid.", "네, 알겠습니다.", ""]
    let settings = [CategorySettings.niceDefault, SettingsPreset.closeFriend.settings, SettingsPreset.firmNo.settings]
    for phrase in phrases {
        for s in settings {
            let readings = PhraseReader.read(phrase, language: .korean, settings: s)
            for category in [ReadingCategory.sarcasm, .manner, .voiceTone] {
                #expect(readings[category] == .notMeasured)
                #expect(!readings.mismatches.contains(category))
            }
        }
    }
}

// MARK: Pass 1 P6: own-speech gate

@Test func readingPipelineRejectsOtherUnknownOverlapAndLowConfidence() {
    func piece(_ label: SpeakerLabel, confidence: Double = 0.95, overlapped: Bool = false, match: Double? = 0.8) -> Utterance {
        Utterance(start: 0, end: 2, text: "그거 내가 할게.", latency: 0, meanLevelDB: nil,
                  predicted: label, predictionConfidence: confidence, overlapped: overlapped, voiceMatch: match)
    }
    let settings = CategorySettings.niceDefault
    let quiet: [Utterance] = [
        piece(.other),
        piece(.unknown, confidence: 0),
        piece(.user, confidence: 0.5),
        piece(.user, overlapped: true),
        piece(.user, match: 0.4),
    ]
    for utterance in quiet {
        guard case .quiet = ReadingPipeline.evaluate(utterance, language: .korean, settings: settings) else {
            Issue.record("expected quiet for \(utterance.predicted) \(utterance.predictionConfidence)")
            continue
        }
    }
    // The same 반말 phrase, confidently the user's, is read and cued.
    guard case .read(let readings, let cue) = ReadingPipeline.evaluate(piece(.user), language: .korean, settings: settings) else {
        Issue.record("expected a reading")
        return
    }
    #expect(cue)
    #expect(readings.mismatches == [.register])
}

// MARK: Pass 1 P7: onboarding, setup, copy

@Test func pass1CopyIsBilingualAndAvoidsForbiddenClaims() {
    for key in CopyKey.allCases {
        let en = Copy.english[key], ko = Copy.korean[key]
        #expect(en?.isEmpty == false, "missing English for \(key)")
        #expect(ko?.isEmpty == false, "missing Korean for \(key)")
        for text in [en ?? "", ko ?? ""] {
            for phrase in Copy.forbidden {
                #expect(!text.lowercased().contains(phrase), "\(key) contains \(phrase)")
            }
        }
    }
    #expect(Copy.text(.listening, .korean) == "듣고 있어요")
}

@Test func enrollmentOnboardingRequiresConsent() {
    var onboarding = Onboarding()
    // Recording permission for conversations is not biometric consent.
    onboarding.allowRecording(true)
    #expect(!onboarding.biometricConsent)
    #expect(!onboarding.mayRecordEnrolment)
    onboarding.update { $0.confirmPlacement() }
    #expect(onboarding.enrollment.step == .consent)
    onboarding.answerBiometricConsent(true)
    #expect(!onboarding.mayRecordEnrolment) // placement first
    onboarding.update { $0.confirmPlacement() }
    #expect(onboarding.mayRecordEnrolment)

    var declined = Onboarding()
    declined.answerBiometricConsent(false)
    #expect(declined.enrollment.step == .declined)
    #expect(!declined.mayRecordEnrolment)
}

@Test func sessionSetupConfirmsCategorySettings() {
    var setup = SessionSetup(intentionText: "Direct but respectful")
    setup.propose(.firmNo)
    // Pending: readers still use the nice default.
    #expect(PhraseReader.read("That idea is stupid.", language: .english, settings: setup.confirmed)[.wordChoice] == .check)
    setup.confirmProposal()
    #expect(setup.confirmed == SettingsPreset.firmNo.settings)
    #expect(PhraseReader.read("That idea is stupid.", language: .english, settings: setup.confirmed)[.wordChoice] == .aligned)
    setup.confirm(wordChoice: .gentle)
    #expect(setup.confirmed.wordChoice == .gentle)
    #expect(setup.intentionText == "Direct but respectful")
}

// MARK: Pass 1 P8: live screen

@Test func liveViewModelStatesAndCueCardContents() {
    var screen = LiveScreen()
    #expect(screen.phase == .idle)
    let mine = Utterance(start: 0, end: 2, text: "그냥 네 생각을 솔직하게 듣고 싶어서 물어본 거야.", latency: 0, meanLevelDB: nil,
                         predicted: .user, predictionConfidence: 0.9, overlapped: false, voiceMatch: 0.8)
    let outcome = ReadingPipeline.evaluate(mine, language: .korean, settings: .niceDefault)
    // Nothing happens before the session starts.
    let beforeStart = screen.receive(outcome, phrase: mine.text, language: .korean)
    #expect(!beforeStart)
    screen.start()
    #expect(screen.phase == .listening)
    let afterStart = screen.receive(outcome, phrase: mine.text, language: .korean)
    #expect(afterStart)
    #expect(screen.needle == 1)
    guard case .cueWaiting(let cue) = screen.phase else {
        Issue.record("expected a waiting cue")
        return
    }
    #expect(cue.phrase == mine.text)
    #expect(cue.possibleReading == Copy.text(.readingRegisterCasual, .korean))
    #expect(cue.whyHere == Copy.text(.whyRegisterPolite, .korean))
    #expect(cue.tryNext == "그냥 네 생각을 솔직하게 듣고 싶어서 물어본 거예요.")
    #expect(cue.categories == [.register])
    screen.settleNeedle()
    screen.openCue()
    #expect(screen.phase == .cueOpen(cue))
    screen.markInaccurate()
    #expect(screen.phase == .listening)
    #expect(screen.marks.map(\.phrase) == [mine.text])
    // Another person's words never open a cue.
    let theirs = Utterance(start: 0, end: 2, text: mine.text, latency: 0, meanLevelDB: nil, predicted: .other, predictionConfidence: 1)
    let theirsBuzz = screen.receive(ReadingPipeline.evaluate(theirs, language: .korean, settings: .niceDefault), phrase: theirs.text, language: .korean)
    #expect(!theirsBuzz)
    screen.stop()
    #expect(screen.phase == .stopped)
}

@Test func liveMeterGeometryKeepsLowerTicksAbsent() {
    let ticks = MeterGeometry.tickAngles()
    #expect(!ticks.isEmpty)
    for angle in ticks {
        // Upper half on screen is 180...360 degrees; every tick is on the reachable arc.
        #expect(angle >= 180 && angle <= 360)
        #expect(MeterGeometry.tickRange.contains(angle))
    }
    // The needle rests straight up and stays on the ticked arc.
    #expect(MeterGeometry.needleAngle(0) == 270)
    #expect(MeterGeometry.tickRange.contains(MeterGeometry.needleAngle(1)))
    #expect(MeterGeometry.segment(containing: 270) != nil)
    // Talking only twitches the needle; it never reaches amber without a cue.
    #expect(!MeterGeometry.isAmber(MeterGeometry.listeningAngle(level: 1)))
    #expect(MeterGeometry.listeningAngle(level: 0) < MeterGeometry.listeningAngle(level: 1))
    // Ring segments still go all the way round, keeping the circle.
    #expect(MeterGeometry.segmentAngles().contains { $0 > 0 && $0 < 180 })
    #expect(MeterGeometry.isAmber(MeterGeometry.needleAngle(1)))
    #expect(!MeterGeometry.isAmber(MeterGeometry.needleAngle(0)))
}

// MARK: Loop autunite-reach (2026-11-16): word list, Whisper second listen, recap, pacing, practice

@Test func personalWordsAddAndMuteChangeWhatIsFlagged() {
    var words = PersonalWords()
    #expect(WordChoiceReader.read("이거 완전 별로네", setting: .gentle, words: words) == .aligned)
    words.add(" 별로 ")
    #expect(words.added == ["별로"])
    #expect(WordChoiceReader.read("이거 완전 별로네", setting: .gentle, words: words) == .check)
    words.mute("존나")
    #expect(WordChoiceReader.read("존나 웃기네", setting: .gentle, words: words) == .aligned)
    #expect(WordChoiceReader.read("존나 웃기네", setting: .gentle) == .check)
    // Adding a muted built-in word unmutes it rather than listing it twice.
    words.add("존나")
    #expect(words.muted.isEmpty)
    #expect(!words.added.contains("존나"))
    #expect(WordChoiceReader.read("존나 웃기네", setting: .gentle, words: words) == .check)
    // English additions match whole words only.
    words.add("Whatever")
    #expect(WordChoiceReader.harshWords(in: "Whatever, fine.", words: words) == ["whatever"])
    #expect(WordChoiceReader.harshWords(in: "whateverland", words: words).isEmpty)
    // The settings carry the list into the phrase reader and the early reader.
    let settings = CategorySettings.niceDefault.with(words)
    #expect(PhraseReader.read("이거 완전 별로네요.", language: .korean, settings: settings)[.wordChoice] == .check)
    #expect(EarlyReader.hits(in: "이거 별로", language: .korean, settings: settings) == 1)
    words.reset("별로")
    #expect(words.added == ["whatever"])
}

@Test func harshHitsCountEachSwearOnceAndKeepSpacesMeaningful() {
    // A longer entry wins: 개새끼 is one hit, and a repeat is a second one.
    #expect(WordChoiceReader.harshOccurrences(in: "이 개새끼가") == 1)
    #expect(WordChoiceReader.harshOccurrences(in: "씨발 진짜 씨발") == 2)
    // Spellings and spaced forms the recognisers wrote on the ko20 bench (docs/loop/whisper-bench).
    for phrase in ["개 짜증 나네", "아 짜증 나", "개짜증", "개소리 하지 마", "존내 웃기네", "시팔", "븅신 같아", "좃 됐다"] {
        #expect(WordChoiceReader.read(phrase, setting: .gentle) == .check, "\(phrase)")
    }
    // Spaces are never removed wholesale: these ordinary sentences hold no swear.
    for phrase in ["세 시 발표 준비됐어요?", "그 병 신경 쓰지 마세요.", "hello there", "a shell script"] {
        #expect(WordChoiceReader.read(phrase, setting: .gentle) == .aligned, "\(phrase)")
    }
    // Where the hit sits in the original phrase.
    let hit = WordChoiceReader.hits(in: "아, 씨발!").first
    #expect(hit?.word == "씨발")
    #expect(hit?.offset == 3)
    #expect(hit?.length == 2)
}

@Test func whisperOnlyCorrectsTextAndAnotherSpeakersSwearNeverCues() {
    // Known silence phrases, sound tags, special tokens and stray scripts are dropped.
    #expect(SecondReading.clean("시청해주셔서 감사합니다.") == nil)
    #expect(SecondReading.clean("[음악] 네, 알겠습니다 <|ko|>") == "네, 알겠습니다")
    #expect(SecondReading.clean("존다а んだ 웃기네") == "존다 웃기네")
    #expect(SecondReading.clean("same same same", compressionRatio: 3) == nil)
    #expect(SecondReading.clean("음", noSpeechProbability: 0.9, averageLogProbability: -1.5) == nil)
    // Only the user's verified speech is re-read.
    let mine = Utterance(start: 0, end: 2, text: "아 진짜 별로예요", latency: 0, meanLevelDB: nil,
                         predicted: .user, predictionConfidence: 1, overlapped: false, voiceMatch: 0.8)
    #expect(SecondReading.admits(mine))
    let theirs = Utterance(start: 0, end: 2, text: "씨발 진짜", latency: 0, meanLevelDB: nil, predicted: .other, predictionConfidence: 1)
    #expect(!SecondReading.admits(theirs))
    var unverified = mine
    unverified.voiceMatch = 0.4
    #expect(!SecondReading.admits(unverified))
    var overlapped = mine
    overlapped.overlapped = true
    #expect(!SecondReading.admits(overlapped))
    // Another speaker's swear never cues, however clearly it was heard.
    var screen = LiveScreen()
    screen.start()
    let theirsCued = screen.receive(ReadingPipeline.evaluate(theirs, language: .korean, settings: .niceDefault), phrase: theirs.text, language: .korean)
    #expect(!theirsCued)
    // A word only Whisper heard changes nothing on screen: there is no card to correct.
    screen.applySecondListen("아 씨발 진짜 별로예요", language: .korean)
    #expect(screen.phase == .listening)
    #expect(screen.needle == 0)
    // In the recap it is listed, uncued.
    var recap = SessionRecap()
    recap.applySecondListen(start: 0, end: 2, apple: mine.text, whisper: "아 씨발 진짜 별로예요")
    #expect(recap.cueCount == 0)
    #expect(recap.moments.count == 1)
    #expect(recap.moments.first?.cued == false)
    #expect(recap.moments.first?.onlyWhisper == ["씨발"])
    // Whisper agreeing with Apple on a clean piece adds nothing.
    recap.applySecondListen(start: 5, end: 7, apple: "네 알겠습니다", whisper: "네, 알겠습니다.")
    #expect(recap.moments.count == 1)
}

@Test func cueCardTakesWhisperWordsButKeepsItsReasons() {
    var screen = LiveScreen()
    screen.start()
    let mine = Utterance(start: 0, end: 2, text: "그거 내가 할게.", latency: 0, meanLevelDB: nil,
                         predicted: .user, predictionConfidence: 1, overlapped: false, voiceMatch: 0.8)
    screen.receive(ReadingPipeline.evaluate(mine, language: .korean, settings: .niceDefault), phrase: mine.text, language: .korean)
    screen.applySecondListen("그거 내가 할 거야.", language: .korean)
    let cue = screen.currentCue
    #expect(cue?.phrase == "그거 내가 할 거야.")
    #expect(cue?.firstHeard == "그거 내가 할게.")
    #expect(cue?.checkedAgain == true)
    #expect(cue?.categories == [.register])
    #expect(cue?.tryNext == "그거 내가 할 거예요.")
    // The same words with other punctuation are not a correction.
    screen.applySecondListen("그거 내가 할 거야", language: .korean)
    #expect(screen.currentCue?.firstHeard == "그거 내가 할게.")
}

@Test func recapMergesAMomentAndCarriesWhisperWordsAndMarks() {
    var recap = SessionRecap(practice: .askManager)
    let early = recap.recordCue(start: 4, end: 7, text: "아 씨발 이거", categories: [.wordChoice])
    let final = recap.recordCue(start: 3.5, end: 8, text: "아 씨발 이거 진짜 별로야.", categories: [.register, .wordChoice])
    #expect(early == final)
    #expect(recap.moments.count == 1)
    #expect(recap.moments[0].categories == [.register, .wordChoice])
    #expect(recap.moments[0].apple == "아 씨발 이거 진짜 별로야.")
    recap.recordCue(start: 20, end: 22, text: "그거 내가 할게.", categories: [.register])
    #expect(recap.cueCount == 2)
    #expect(recap.cueCount(.register) == 2)
    #expect(recap.cueCount(.wordChoice) == 1)
    recap.applySecondListen(start: 3.5, end: 8, apple: "아 씨발 이거 진짜 별로야.", whisper: "아 씨발 이거 진짜 별로야")
    #expect(recap.moments[0].whisper == "아 씨발 이거 진짜 별로야")
    #expect(!recap.moments[0].heardDifferently)
    // Whisper heard 존댓말 where Apple heard 반말: the cue stays, and the recap shows the disagreement.
    recap.applySecondListen(start: 20, end: 22, apple: "그거 내가 할게.", whisper: "그거 제가 할게요.")
    #expect(recap.moments[1].heardDifferently)
    #expect(recap.moments[1].cued)
    #expect(recap.moments[1].quote == "그거 제가 할게요.")
    recap.mark(early, .inaccurate)
    #expect(recap.moments[0].verdict == .inaccurate)
    #expect(recap.moments[0].harshWords() == ["씨발"])
    #expect(recap.practice == .askManager)
}

@Test func buzzesAreSpacedAndCloseHitsShareOneCard() {
    var pacer = CuePacer()
    let allowed = [10, 11.5, 12.9, 13.1].map { pacer.allowBuzz(at: $0) }
    #expect(allowed == [true, false, false, true])
    var screen = LiveScreen()
    screen.start()
    let first = Utterance(start: 0, end: 2, text: "아 씨발 진짜", latency: 0, meanLevelDB: nil,
                          predicted: .user, predictionConfidence: 1, overlapped: false, voiceMatch: 0.8)
    let outcome = ReadingPipeline.evaluate(first, language: .korean, settings: .niceDefault)
    let shown = screen.receive(outcome, phrase: first.text, language: .korean)
    #expect(shown)
    #expect(screen.currentCue?.count == 1)
    // The final line of the same moment replaces the words without counting again.
    let finalLine = screen.receive(outcome, phrase: "아 씨발 진짜 왜 이래", language: .korean, sameMoment: true)
    #expect(finalLine)
    #expect(screen.currentCue?.count == 1)
    #expect(screen.currentCue?.phrase == "아 씨발 진짜 왜 이래")
    // A new hit before the card is closed counts on the same card, and an open card stays open.
    screen.openCue()
    let again = screen.receive(outcome, phrase: "또 씨발", language: .korean)
    #expect(again)
    #expect(screen.currentCue?.count == 2)
    guard case .cueOpen = screen.phase else {
        Issue.record("a newer hit closed the open card")
        return
    }
    // Once the user closed the card, a late final line of that moment doesn't reopen it.
    screen.dismissCue()
    let reopened = screen.receive(outcome, phrase: "또 씨발", language: .korean, sameMoment: true)
    #expect(!reopened)
    #expect(screen.phase == .listening)
}

@Test func practiceScenariosPresetsAndLearnerCards() {
    for scenario in PracticeScenario.allCases {
        #expect(!Copy.text(scenario.titleKey, .korean).isEmpty)
        #expect(!Copy.text(scenario.promptKey, .english).isEmpty)
    }
    #expect(PracticeScenario.requestJunior.settings.register == .politeExpected)
    #expect(PracticeScenario.disagreeFriend.settings.register == .casualFine)
    #expect(SettingsPreset.junior.settings == .niceDefault)
    // A learner (app in English, speech in Korean) gets the reasons in English and the next line in Korean.
    let readings = PhraseReader.read("그거 내가 할게.", language: .korean, settings: .niceDefault)
    let cue = CueComposer.compose(phrase: "그거 내가 할게.", readings: readings, language: .korean, uiLanguage: .english)
    #expect(cue?.possibleReading == Copy.text(.readingRegisterCasual, .english))
    #expect(cue?.tryNext == "그거 내가 할게요.")
    #expect(cue?.note == Copy.text(.learnerRegisterNote, .english))
    #expect(CueComposer.compose(phrase: "그거 내가 할게.", readings: readings, language: .korean)?.note == nil)
}

@Test func reReadQueuePutsCuedPiecesFirstAndDropsUncuedWhenFull() {
    var queue = ReReadQueue<Int>(capacity: 3)
    queue.push(1, cued: false)
    queue.push(2, cued: true)
    queue.push(3, cued: false)
    // Full: the oldest piece without a cue goes.
    queue.push(4, cued: false)
    #expect(queue.count == 3)
    let order = (0..<4).map { _ in queue.pop() }
    #expect(order == [2, 3, 4, nil])
}

@Test func secondListenReachesItsOwnMomentNotANeighbours() {
    var recap = SessionRecap()
    let piece = UUID()
    // The early cue's window reaches back into the previous piece; the final line joins it.
    recap.recordCue(start: 9, end: 12, text: "아 씨발", categories: [.wordChoice])
    recap.recordCue(start: 10, end: 14, text: "아 씨발 진짜", categories: [.wordChoice], piece: piece)
    #expect(recap.moments.count == 1)
    #expect(recap.moments[0].pieces == [piece])
    // Whisper reads the cued piece first, then the earlier piece that overlaps the early window.
    recap.applySecondListen(start: 10, end: 14, apple: "아 씨발 진짜", whisper: "아, 씨발 진짜.", piece: piece)
    recap.applySecondListen(start: 7, end: 10, apple: "그래서 말인데", whisper: "그래서 말인데요", piece: UUID())
    #expect(recap.moments.count == 1)
    #expect(recap.moments[0].whisper == "아, 씨발 진짜.")
    // A neighbour where only Whisper heard a harsh word gets its own uncued moment.
    recap.applySecondListen(start: 14, end: 16, apple: "아 진짜 한 심하다", whisper: "아 진짜 한심하다", piece: UUID())
    #expect(recap.moments.count == 2)
    #expect(recap.moments[1].cued == false)
    #expect(recap.moments[1].onlyWhisper == ["한심"])
    #expect(recap.cueCount == 1)
}

// MARK: Rubric C4: marks that change something

@Test func aWordMarkedWrongTwiceIsOfferedForMutingAndTrueCuesSurvive() {
    let first = LiveScreen.InaccurateMark(phrase: "아 짜증 나", categories: [.wordChoice])
    // One wrong mark: nothing is offered, and the word still cues.
    #expect(MarkReview.wordsToOffer(marks: [first], words: PersonalWords()).isEmpty)
    // Twice: offered, but still flagged until the user says to stop.
    let twice = [first, LiveScreen.InaccurateMark(phrase: "진짜 짜증 나네", categories: [.wordChoice])]
    #expect(MarkReview.wordsToOffer(marks: twice, words: PersonalWords()) == ["짜증 나"])
    #expect(WordChoiceReader.read("아 짜증 나", setting: .gentle) == .check)
    // Register cards marked wrong don't count toward a word.
    let register = LiveScreen.InaccurateMark(phrase: "짜증 나 그거 내가 할게", categories: [.register])
    #expect(MarkReview.wordsToOffer(marks: [first, register], words: PersonalWords()).isEmpty)
    // Once muted it isn't offered again, and only that word stops cueing.
    var words = PersonalWords()
    words.mute("짜증 나")
    #expect(MarkReview.wordsToOffer(marks: twice, words: words).isEmpty)
    #expect(WordChoiceReader.read("아 짜증 나", setting: .gentle, words: words) == .aligned)
    #expect(WordChoiceReader.read("미친 거 아니야", setting: .gentle, words: words) == .check)
}

@Test func aClauseEndingBeforeASentenceOpenerIsReadMidTurn() {
    let settings = CategorySettings.niceDefault
    // No punctuation: the casual clause before 근데 is finished, so it counts while the user goes on.
    #expect(EarlyReader.hits(in: "내일 갈 거야 근데 너는", language: .korean, settings: settings) == 1)
    // A polite clause before it doesn't, and neither does a connective, which says nothing.
    #expect(EarlyReader.hits(in: "내일 갈 거예요 근데 저는", language: .korean, settings: settings) == 0)
    #expect(EarlyReader.hits(in: "그거 하고 근데", language: .korean, settings: settings) == 0)
    // The finished line reads both clauses, so a polite last ending doesn't hide a casual one.
    #expect(KoreanRegisterReader.read("내일 갈 거야 근데 너는 어때요", setting: .politeExpected).reading == .check)
    #expect(KoreanRegisterReader.read("내일 갈 거예요 그래서 저는 괜찮아요", setting: .politeExpected).reading == .aligned)
}
