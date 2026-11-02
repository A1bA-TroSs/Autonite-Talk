#if os(iOS)
import AutoniteCore
import Foundation
import Observation

/// Pass 1: onboarding, session setup and the live screen, on top of the Pass 0 capture pipeline.
@MainActor
@Observable
final class Pass1Model {
    enum Route: Equatable {
        case onboarding
        case setup
        case live
    }

    let lab: FeasibilityModel
    var language: SpeechLanguage = .korean
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

    private let haptics = HapticProbe()
    private let store: VoiceProfileStore?
    private var readingAudio: [Float] = []
    private var freeSpeechAudio: [Float] = []
    private var sampleRate = 48_000.0
    private var needleTask: Task<Void, Never>?
    /// Audio time up to which an early cue already buzzed, so the final line doesn't buzz again.
    private var earlyCuedUntil = -1.0

    init(lab: FeasibilityModel) {
        self.lab = lab
        store = try? VoiceProfileStore.appDefault()
        if let profile = try? store?.load() {
            lab.profile = profile
            route = .setup
        }
        lab.onVoiceUtterance = { [weak self] utterance in self?.receive(utterance) }
        lab.onEarlyCue = { [weak self] utterance in self?.receiveEarly(utterance) }
    }

    func copy(_ key: CopyKey) -> String { Copy.text(key, language) }

    /// Set only by the CI screenshot fixture, so the strip shows a recording session.
    var fixtureStartedAt: Date?
    var showsRecording: Bool { lab.isRecording || fixtureStartedAt != nil }
    var recordingStartedAt: Date? { fixtureStartedAt ?? lab.startedAt }

    /// CI screenshots (AUTONITE_SCREEN=setup|live|cue): puts the screens in a known state so a
    /// render can be compared with the UI reference. Never used on a phone.
    func showFixture(_ name: String) {
        language = .korean
        setup.intentionText = "차분하고 예의 있게"
        switch name {
        case "setup":
            route = .setup
        default:
            route = .live
            fixtureStartedAt = Date().addingTimeInterval(-754)
            screen.start()
            guard name == "cue" else { return }
            let phrase = "아 그거 진짜 별로야."
            let utterance = Utterance(start: 0, end: 2, text: phrase, latency: 0, meanLevelDB: nil,
                                      predicted: .user, predictionConfidence: 1, overlapped: false, voiceMatch: 0.8)
            let outcome = ReadingPipeline.evaluate(utterance, language: language, settings: setup.confirmed)
            screen.receive(outcome, phrase: phrase, language: language)
            screen.openCue()
            lastHeard = phrase
            lastResult = .resultCue
        }
    }

    var hasProfile: Bool { lab.profile != nil }

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

    func startSession() async {
        if lab.voiceStatus != .ready { await lab.loadVoiceModel() }
        lab.language = language
        lastHeard = nil
        lastResult = nil
        earlyCuedUntil = -1
        lab.earlySettings = setup.confirmed
        screen.start()
        route = .live
        await lab.start()
        if !lab.isRecording { screen.stop() }
    }

    func endSession() async {
        lab.earlySettings = nil
        await lab.stop()
        screen.stop()
    }

    func backToSetup() {
        screen = LiveScreen()
        route = .setup
    }

    /// Saves the mark on the phone so wrong cues can be counted later (SPEC AC13).
    func markInaccurate() {
        screen.markInaccurate()
        guard let folder = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return }
        let file = folder.appendingPathComponent("inaccurate-cues.json")
        var saved = (try? JSONDecoder().decode([LiveScreen.InaccurateMark].self, from: Data(contentsOf: file))) ?? []
        if let latest = screen.marks.last { saved.append(latest) }
        try? JSONEncoder().encode(saved).write(to: file, options: [.atomic, .completeFileProtection])
        message = copy(.cueMarked)
    }

    private func receive(_ utterance: Utterance) {
        let outcome = ReadingPipeline.evaluate(utterance, language: language, settings: setup.confirmed)
        lastHeard = utterance.text
        switch outcome {
        case .quiet(let reason): lastResult = Self.quietKey(reason)
        case .read(_, let cue): lastResult = cue ? .resultCue : .resultAligned
        }
        guard screen.receive(outcome, phrase: utterance.text, language: language) else { return }
        // The early path already buzzed for this stretch of speech; the card now shows the final words.
        if utterance.start <= earlyCuedUntil + 0.5 { return }
        buzz()
    }

    /// A cue from in-progress text, while the user is still talking.
    private func receiveEarly(_ utterance: Utterance) {
        let outcome = ReadingPipeline.evaluate(utterance, language: language, settings: setup.confirmed)
        guard screen.receive(outcome, phrase: utterance.text, language: language) else { return }
        lastHeard = utterance.text
        lastResult = .resultCue
        earlyCuedUntil = utterance.end
        buzz()
    }

    private func buzz() {
        haptics.pulse()
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
}
#endif
