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

    private let haptics = HapticProbe()
    private let store: VoiceProfileStore?
    private var readingAudio: [Float] = []
    private var freeSpeechAudio: [Float] = []
    private var sampleRate = 48_000.0
    private var needleTask: Task<Void, Never>?

    init(lab: FeasibilityModel) {
        self.lab = lab
        store = try? VoiceProfileStore.appDefault()
        if let profile = try? store?.load() {
            lab.profile = profile
            route = .setup
        }
        lab.onVoiceUtterance = { [weak self] utterance in self?.receive(utterance) }
    }

    func copy(_ key: CopyKey) -> String { Copy.text(key, language) }

    var hasProfile: Bool { lab.profile != nil }

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
        screen.start()
        route = .live
        await lab.start()
        if !lab.isRecording { screen.stop() }
    }

    func endSession() async {
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
        guard screen.receive(outcome, phrase: utterance.text, language: language) else { return }
        haptics.pulse()
        needleTask?.cancel()
        needleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.screen.settleNeedle()
        }
    }
}
#endif
