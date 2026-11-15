#if os(iOS)
import AutoniteCore
import Foundation
import Observation

/// Pass 1: onboarding, session setup, the live screen and the recap, on top of the Pass 0 capture
/// pipeline, with Whisper's second listen and practice mode (loop autunite-reach).
@MainActor
@Observable
final class Pass1Model {
    enum Route: Equatable {
        case onboarding
        case setup
        case live
        case recap
    }

    /// The app's language, chosen apart from the speech language (INTENTIONAL §7), so someone
    /// learning Korean can keep the app in English and speak Korean (research 2026-11-16 §5.7).
    enum AppLanguage: String, CaseIterable {
        case followSpeech
        case korean
        case english
    }

    /// What the user keeps on this iPhone, for the My data section of Settings.
    struct DataSummary: Equatable {
        var voiceBytes: Int64?
        var marks = 0
        var words = 0
        var whisperBytes: Int64?
    }

    let lab: FeasibilityModel
    var language: SpeechLanguage = .korean
    private(set) var appLanguage: AppLanguage = .followSpeech
    var route: Route = .onboarding
    var onboarding = Onboarding()
    var setup = SessionSetup()
    var screen = LiveScreen()
    var isRecordingClip = false
    var checkPhrase = ""
    var message: String?
    /// The last phrase the session heard and what it did with it, so real use shows why a cue
    /// did or didn't fire.
    var lastHeard: String?
    var lastResult: CopyKey?
    /// A word the user has marked wrong more than once, offered for muting (`MarkReview`).
    var muteOffer: String?
    /// The last session's flagged moments. In memory only; replaced when the next session starts.
    var recap = SessionRecap()
    /// The practice situation of the current or last session; nil for a real conversation.
    private(set) var practice: PracticeScenario?
    /// The user's own word list, saved on this iPhone.
    private(set) var words = PersonalWords()
    private(set) var whisperEnabled = false
    private(set) var whisperModel: WhisperReader.Model = .standard
    var showsSettings = false
    var showsPractice = false
    /// What the running session reads with: the practice situation's settings or the confirmed
    /// ones, plus the user's word list.
    private(set) var sessionSettings = CategorySettings.niceDefault

    private let haptics = HapticProbe()
    private let store: VoiceProfileStore?
    private let defaults = UserDefaults.standard
    private enum Keys {
        static let appLanguage = "autunite.appLanguage"
        static let whisperEnabled = "autunite.whisperEnabled"
        static let whisperModel = "autunite.whisperModel"
    }
    private var readingAudio: [Float] = []
    private var freeSpeechAudio: [Float] = []
    private var sampleRate = 48_000.0
    private var needleTask: Task<Void, Never>?
    /// Audio time up to which an early cue already flagged speech, so the final line of the same
    /// moment updates the card without a second hit.
    private var earlyCuedUntil = -1.0
    private var pacer = CuePacer()
    /// The recap moment of the card on screen, and the attributed piece whose words it shows, so a
    /// "wrong" mark and Whisper's re-read reach them.
    private var cueMoment: UUID?
    private var cuePiece: UUID?
    /// Words the user chose to keep flagging when offered, so the offer isn't repeated this run.
    private var keptWords: Set<String> = []

    init(lab: FeasibilityModel) {
        self.lab = lab
        store = try? VoiceProfileStore.appDefault()
        if let profile = try? store?.load() {
            lab.profile = profile
            route = .setup
        }
        appLanguage = defaults.string(forKey: Keys.appLanguage).flatMap { AppLanguage(rawValue: $0) } ?? .followSpeech
        whisperModel = defaults.string(forKey: Keys.whisperModel).flatMap { WhisperReader.Model(rawValue: $0) } ?? .standard
        whisperEnabled = defaults.bool(forKey: Keys.whisperEnabled)
        words = Self.loadWords()
        lab.whisperEnabled = whisperEnabled
        lab.onVoiceUtterance = { [weak self] utterance in self?.receive(utterance) }
        lab.onEarlyCue = { [weak self] utterance in self?.receiveEarly(utterance) }
        lab.onSecondListen = { [weak self] utterance, text in self?.receiveSecondListen(utterance, text) }
        // A model already on the phone loads at launch. A download only ever starts from Settings.
        if whisperEnabled, WhisperReader.downloadedFolder(whisperModel) != nil {
            let model = whisperModel
            Task { await lab.prepareWhisper(model) }
        }
    }

    /// The app's own language: the speech language unless the user chose one in Settings.
    var uiLanguage: SpeechLanguage {
        switch appLanguage {
        case .followSpeech: language
        case .korean: .korean
        case .english: .english
        }
    }

    func copy(_ key: CopyKey) -> String { Copy.text(key, uiLanguage) }

    /// Set only by the CI screenshot fixture, so the strip shows a recording session.
    var fixtureStartedAt: Date?
    var showsRecording: Bool { lab.isRecording || fixtureStartedAt != nil }
    var recordingStartedAt: Date? { fixtureStartedAt ?? lab.startedAt }

    var hasProfile: Bool { lab.profile != nil }

    /// The phrase being spoken right now (the recogniser's in-progress text) and a running verdict,
    /// so the user sees the check while still talking (Danny, 2026-11-08).
    var liveText: String { lab.volatileText.trimmingCharacters(in: .whitespacesAndNewlines) }
    var liveFlagged: Bool {
        !liveText.isEmpty && EarlyReader.hits(in: liveText, language: language, settings: sessionSettings) > 0
    }

    /// The session fell back to level attribution, which never reads the user's words.
    var voiceCheckOff: Bool { lab.isRecording && lab.sessionMethod != .voice }

    // MARK: Onboarding

    func answerConsent(_ agreed: Bool) {
        onboarding.answerBiometricConsent(agreed)
        message = agreed ? nil : copy(.consentDeclined)
        if agreed { Task { await lab.loadVoiceModel() } }
    }

    func confirmPlacement() { onboarding.update { $0.confirmPlacement() } }

    /// Records the current reading step. Audio stays in memory until the profile is built.
    func recordStep() async {
        guard onboarding.mayRecordEnrolment, !isRecordingClip else { return }
        isRecordingClip = true
        defer { isRecordingClip = false }
        let step = onboarding.enrollment.step
        let seconds: Double = switch step {
        case .freeSpeech: 25
        case .phraseCheck: 4
        default: 6
        }
        do {
            let clip = try await EnrollmentRecorder().record(seconds: seconds)
            sampleRate = clip.sampleRate
            switch step {
            case .sentence, .extraSentence:
                readingAudio += clip.samples
                onboarding.update { $0.finishSentence() }
            case .freeSpeech:
                freeSpeechAudio = clip.samples
                onboarding.update { $0.finishFreeSpeech(seconds: seconds) }
                checkPhrase = randomCheckPhrase()
            case .phraseCheck:
                await check(clip.samples)
            default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func randomCheckPhrase() -> String {
        (language == .korean ? EnrollmentScript.checkPhrases.korean : EnrollmentScript.checkPhrases.english).randomElement() ?? ""
    }

    private func check(_ samples: [Float]) async {
        if lab.voiceStatus != .ready { await lab.loadVoiceModel() }
        do {
            let profile = try lab.makeProfile(reading: readingAudio, freeSpeech: freeSpeechAudio, sampleRate: sampleRate)
            let match = try lab.similarity(of: samples, sampleRate: sampleRate, to: profile.voiceprint) ?? 0
            let passed = match >= VoiceVerifier.threshold
            message = copy(passed ? .checkPassed : .checkFailed)
            onboarding.update { $0.finishPhraseCheck(passed: passed) }
            guard passed else { return }
            try store?.save(profile)
            lab.profile = profile
            readingAudio = []
            freeSpeechAudio = []
            onboarding.update { $0.finishBaseline() }
            message = copy(.enrolmentDone)
            route = .setup
        } catch {
            message = error.localizedDescription
        }
    }

    /// Deletes the voice profile and everything recorded for it.
    func deleteVoice() {
        try? store?.delete()
        lab.profile = nil
        onboarding = Onboarding()
        route = .onboarding
        message = copy(.voiceDeleted)
    }

    // MARK: Live

    /// Starts a conversation, or a practice run of `practice` with the settings it shows.
    func startSession(practice: PracticeScenario? = nil) async {
        if lab.voiceStatus != .ready { await lab.loadVoiceModel() }
        self.practice = practice
        sessionSettings = (practice?.settings ?? setup.confirmed).with(words)
        lab.language = language
        lastHeard = nil
        lastResult = nil
        muteOffer = nil
        earlyCuedUntil = -1
        cueMoment = nil
        cuePiece = nil
        pacer.reset()
        recap = SessionRecap(practice: practice)
        lab.earlySettings = sessionSettings
        lab.whisperEnabled = whisperEnabled
        haptics.prepare()
        screen = LiveScreen()
        screen.start()
        route = .live
        await lab.start()
        if !lab.isRecording { screen.stop() }
    }

    /// Ends the session and shows its recap. Whisper may still be re-reading the last pieces; the
    /// recap fills in as it finishes.
    func endSession() async {
        let started = lab.startedAt
        lab.earlySettings = nil
        await lab.stop()
        screen.stop()
        recap.duration = started.map { Date().timeIntervalSince($0) } ?? 0
        route = .recap
    }

    func backToSetup() {
        screen = LiveScreen()
        route = .setup
    }

    /// Leaves the recap. It is gone after this, and Whisper stops on the last session.
    func newConversation() {
        lab.endSecondListen()
        recap = SessionRecap()
        practice = nil
        screen = LiveScreen()
        route = .setup
    }

    /// Saves the mark on the phone so wrong cues can be counted later (SPEC AC13), and marks the
    /// moment in the recap.
    func markInaccurate() {
        guard let cue = screen.currentCue else { return }
        screen.markInaccurate()
        if let cueMoment { recap.mark(cueMoment, .inaccurate) }
        var marks = loadMarks()
        marks.append(LiveScreen.InaccurateMark(phrase: cue.phrase, categories: cue.categories))
        saveMarks(marks)
        message = copy(.cueMarked)
        offerMute(among: harshWords(on: cue), marks: marks)
    }

    /// The user's mark on a recap moment. "Wrong" is saved like a mark on the live card, and its
    /// harsh words can then be muted from the recap.
    func markMoment(_ moment: SessionRecap.Moment, _ verdict: SessionRecap.Verdict) {
        let before = moment.verdict
        recap.mark(moment.id, verdict)
        var marks = loadMarks()
        if verdict == .inaccurate, before != .inaccurate {
            marks.append(LiveScreen.InaccurateMark(phrase: moment.quote, categories: moment.categories))
        } else if verdict == .accurate, before == .inaccurate,
                  let i = marks.lastIndex(where: { $0.phrase == moment.quote || $0.phrase == moment.apple }) {
            marks.remove(at: i)
        }
        saveMarks(marks)
        if verdict == .inaccurate, moment.categories.contains(.wordChoice) {
            offerMute(among: moment.harshWords(PersonalWords(added: words.added)), marks: marks)
        }
    }

    /// Offers to stop flagging a word from this card once it has been marked wrong
    /// `MarkReview.offerAfter` times. Nothing is muted until the user says so.
    private func offerMute(among cardWords: [String], marks: [LiveScreen.InaccurateMark]) {
        let offers = MarkReview.wordsToOffer(marks: marks, words: words)
        muteOffer = cardWords.first { offers.contains($0) && !keptWords.contains($0) }
    }

    func acceptMuteOffer(_ word: String) {
        mute(word)
        muteOffer = nil
    }

    func keepFlagging(_ word: String) {
        keptWords.insert(word)
        muteOffer = nil
    }

    private func receive(_ utterance: Utterance) {
        let outcome = ReadingPipeline.evaluate(utterance, language: language, settings: sessionSettings)
        lastHeard = utterance.text
        switch outcome {
        case .quiet(let reason): lastResult = Self.quietKey(reason)
        case .read(_, let cue): lastResult = cue ? .resultCue : .resultAligned
        }
        guard case .read(let readings, true) = outcome else { return }
        // The early path already flagged this stretch of speech: the card and the recap take the
        // final words, without a second hit.
        let sameMoment = utterance.start <= earlyCuedUntil + SessionRecap.mergeGap
        let moment = recap.recordCue(start: utterance.start, end: utterance.end, text: utterance.text,
                                     categories: readings.mismatches, piece: utterance.id)
        guard screen.receive(outcome, phrase: utterance.text, language: language, uiLanguage: uiLanguage, sameMoment: sameMoment) else { return }
        cueMoment = moment
        cuePiece = utterance.id
        if !sameMoment { feelCue() }
    }

    /// A cue from in-progress text, while the user is still talking.
    private func receiveEarly(_ utterance: Utterance) {
        let outcome = ReadingPipeline.evaluate(utterance, language: language, settings: sessionSettings)
        guard case .read(let readings, true) = outcome,
              screen.receive(outcome, phrase: utterance.text, language: language, uiLanguage: uiLanguage) else { return }
        cueMoment = recap.recordCue(start: utterance.start, end: utterance.end, text: utterance.text, categories: readings.mismatches)
        cuePiece = nil
        lastHeard = utterance.text
        lastResult = .resultCue
        earlyCuedUntil = utterance.end
        feelCue()
    }

    /// Whisper re-read one of the user's pieces. It corrects the words on the card and in the
    /// recap; it never gives a cue (`SecondReading`).
    private func receiveSecondListen(_ utterance: Utterance, _ text: String) {
        recap.applySecondListen(start: utterance.start, end: utterance.end, apple: utterance.text, whisper: text,
                                piece: utterance.id, words: words)
        if utterance.id == cuePiece { screen.applySecondListen(text, language: language) }
    }

    /// Every hit slams the needle and counts on the card; the buzz waits out `CuePacer.minimumGap`.
    private func feelCue() {
        // Screenshots keep the needle on the cue and never buzz.
        guard fixtureStartedAt == nil else { return }
        if pacer.allowBuzz(at: ProcessInfo.processInfo.systemUptime) { haptics.pulse() }
        needleTask?.cancel()
        needleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.screen.settleNeedle()
        }
    }

    private static func quietKey(_ reason: String) -> CopyKey {
        if reason.contains("other") { return .quietOther }
        if reason.contains("overlap") { return .quietOverlap }
        if reason.contains("does not match") { return .quietVoice }
        if reason.contains("no words") { return .quietNoWords }
        return .quietUnsure
    }

    // MARK: Settings

    func setAppLanguage(_ value: AppLanguage) {
        appLanguage = value
        defaults.set(value.rawValue, forKey: Keys.appLanguage)
    }

    /// Turning Whisper on loads a model already on the phone; one that isn't waits for the user to
    /// tap Download, which shows its size first. Turning it off frees its memory and keeps the files.
    func setWhisperEnabled(_ on: Bool) {
        whisperEnabled = on
        defaults.set(on, forKey: Keys.whisperEnabled)
        lab.whisperEnabled = on
        if on {
            if whisperOnPhone { downloadWhisper() }
        } else {
            Task { await lab.unloadWhisper() }
        }
    }

    func setWhisperModel(_ model: WhisperReader.Model) {
        guard model != whisperModel else { return }
        whisperModel = model
        defaults.set(model.rawValue, forKey: Keys.whisperModel)
        guard whisperEnabled else { return }
        if whisperOnPhone {
            downloadWhisper()
        } else {
            Task { await lab.unloadWhisper() }
        }
    }

    /// Downloads the chosen model when it isn't on the phone yet, then loads it.
    func downloadWhisper() {
        let model = whisperModel
        Task { await lab.prepareWhisper(model) }
    }

    var whisperOnPhone: Bool { WhisperReader.downloadedFolder(whisperModel) != nil }

    var whisperBusy: Bool {
        switch lab.whisperStatus {
        case .downloading, .preparing: true
        default: false
        }
    }

    /// The chosen model is loaded and re-reading the user's speech.
    var whisperReady: Bool { lab.whisperStatus == .ready && lab.whisper.loaded == whisperModel }

    /// Whisper is on but not ready (downloading, failed or not downloaded), so a running
    /// conversation is read by Apple's recogniser alone. Shown on the live screen.
    var whisperAppleOnly: Bool { whisperEnabled && !whisperReady && showsRecording && fixtureStartedAt == nil }

    func deleteWhisperModels() async {
        await lab.deleteWhisper()
        setWhisperEnabled(false)
    }

    // MARK: My words

    func addWord(_ word: String) {
        words.add(word)
        wordsChanged()
    }

    /// Stops flagging a word, from the cue card or from a recap moment marked wrong.
    func mute(_ word: String) {
        words.mute(word)
        wordsChanged()
    }

    func resetWord(_ word: String) {
        words.reset(word)
        wordsChanged()
    }

    func isMuted(_ word: String) -> Bool { words.muted.contains(word) }

    func deleteWords() {
        words = PersonalWords()
        wordsChanged()
    }

    /// The harsh words on a word-choice card, which the user can stop flagging from the card.
    func harshWords(on cue: Cue) -> [String] {
        guard cue.categories.contains(.wordChoice) else { return [] }
        let list = PersonalWords(added: words.added)
        return ([cue.phrase] + [cue.firstHeard].compactMap { $0 })
            .flatMap { WordChoiceReader.harshWords(in: $0, words: list) }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    /// Stops flagging a word straight from the card and closes it.
    func muteFromCard(_ word: String) {
        mute(word)
        screen.dismissCue()
    }

    /// Saves the list, and a running session reads with it from the next phrase on.
    private func wordsChanged() {
        saveWords()
        guard route == .live, lab.earlySettings != nil else { return }
        sessionSettings = sessionSettings.with(words)
        lab.earlySettings = sessionSettings
    }

    private static var wordsFile: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("personal-words.json")
    }

    private static func loadWords() -> PersonalWords {
        guard let file = wordsFile, let data = try? Data(contentsOf: file) else { return PersonalWords() }
        return (try? JSONDecoder().decode(PersonalWords.self, from: data)) ?? PersonalWords()
    }

    private func saveWords() {
        guard let file = Self.wordsFile else { return }
        if words.isEmpty {
            try? FileManager.default.removeItem(at: file)
        } else {
            try? JSONEncoder().encode(words).write(to: file, options: [.atomic, .completeFileProtection])
        }
    }

    // MARK: My data

    private static var marksFile: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("inaccurate-cues.json")
    }

    private func loadMarks() -> [LiveScreen.InaccurateMark] {
        guard let file = Self.marksFile, let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([LiveScreen.InaccurateMark].self, from: data)) ?? []
    }

    private func saveMarks(_ marks: [LiveScreen.InaccurateMark]) {
        guard let file = Self.marksFile else { return }
        if marks.isEmpty {
            try? FileManager.default.removeItem(at: file)
        } else {
            try? JSONEncoder().encode(marks).write(to: file, options: [.atomic, .completeFileProtection])
        }
    }

    func deleteMarks() { saveMarks([]) }

    func dataSummary() -> DataSummary {
        DataSummary(
            voiceBytes: hasProfile ? store.flatMap { Self.size(of: $0.directory) } : nil,
            marks: loadMarks().count,
            words: words.added.count + words.muted.count,
            whisperBytes: (try? WhisperReader.folder()).flatMap { Self.size(of: $0) }
        )
    }

    /// Bytes the files in a folder take on disk, or nil when there are none.
    private static func size(of folder: URL) -> Int64? {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return nil }
        var total: Int64 = 0
        for case let url as URL in items {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total > 0 ? total : nil
    }
}

// MARK: CI screenshot fixtures

#if DEBUG
/// Debug builds only: the CI screenshot step launches the app with AUTONITE_SCREEN set, and the
/// app shows one screen in a known state. A release build has none of this.
extension Pass1Model {
    /// CI screenshots (AUTONITE_SCREEN=setup|live|cue|learner|muteoffer|practice|settings|recap): puts the
    /// screens in a known state so a render can be compared with the UI reference. Nothing here is
    /// saved, downloaded or recorded. Never used on a phone.
    func showFixture(_ name: String) {
        language = .korean
        setup.intentionText = "차분하고 예의 있게"
        // An enrolled user, in memory only.
        lab.profile = VoiceProfile(voiceprint: [1, 0])
        switch name {
        case "setup":
            route = .setup
        case "practice":
            route = .setup
            showsPractice = true
        case "settings":
            route = .setup
            whisperEnabled = true
            words = PersonalWords(added: ["대박"], muted: ["짜증 나"])
            showsSettings = true
        case "recap":
            showRecapFixture()
        default:
            route = .live
            fixtureStartedAt = Date().addingTimeInterval(-754)
            sessionSettings = setup.confirmed.with(words)
            screen.start()
            switch name {
            case "cue":
                // Two hits on one card, the second re-read by Whisper with other words.
                receive(fixtureUtterance("아 그거 진짜 별로야", start: 40))
                let second = fixtureUtterance("아 그거 진짜 별로야", start: 44)
                receive(second)
                receiveSecondListen(second, "아, 그거 진짜 별로잖아.")
                screen.openCue()
            case "learner":
                appLanguage = .english
                setup.intentionText = "Polite with my team lead"
                receive(fixtureUtterance("그거 내가 할게", start: 40))
                screen.openCue()
            case "muteoffer":
                // A word marked wrong a second time: the app offers to stop flagging it.
                receive(fixtureUtterance("아 진짜 짜증 나", start: 40))
                screen.markInaccurate()
                muteOffer = "짜증 나"
            default:
                let heard = fixtureUtterance("내일 오후에 반찬 써도 될까요", start: 30)
                receive(heard)
                receiveSecondListen(heard, "내일 오후에 반차 써도 될까요?")
            }
        }
    }

    private func fixtureUtterance(_ text: String, start: Double) -> Utterance {
        Utterance(start: start, end: start + 2, text: text, latency: 0, meanLevelDB: nil,
                  predicted: .user, predictionConfidence: 1, overlapped: false, voiceMatch: 0.8)
    }

    private func showRecapFixture() {
        route = .recap
        recap = SessionRecap()
        recap.duration = 754
        let first = recap.recordCue(start: 41, end: 43.5, text: "아 그거 진짜 별로야", categories: [.register])
        recap.applySecondListen(start: 41, end: 43.5, apple: "아 그거 진짜 별로야", whisper: "아, 그거 진짜 별로잖아.", words: words)
        recap.mark(first, .accurate)
        let second = recap.recordCue(start: 188, end: 191, text: "그건 좀 짜증 나요", categories: [.wordChoice])
        recap.applySecondListen(start: 188, end: 191, apple: "그건 좀 짜증 나요", whisper: "그건 좀 짜증 나요.", words: words)
        recap.mark(second, .inaccurate)
        recap.applySecondListen(start: 402, end: 405, apple: "아 그건 좀 한 심하다", whisper: "아, 그건 좀 한심하다.", words: words)
    }
}
#endif
#endif
