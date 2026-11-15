#if os(iOS)
import AutoniteCore
import Foundation

/// Simulator self-test for `xtkit.py simtest`. Speech assets don't load in the Simulator,
/// so this proves the app launches and its wiring holds, not that transcription works.
///
///     SIMCTL_CHILD_AUTONITE_SELFTEST=1 python3 xtkit.py simtest . --sentinel "autonite selftest succeeded"
enum SelfTest {
    static let sentinel = "autonite selftest succeeded"

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["AUTONITE_SELFTEST"] == "1"
    }

    /// `AUTONITE_SELFTEST=whisper`: the Whisper check (rubric M9), run in CI after the main one.
    static var isWhisperRequested: Bool {
        ProcessInfo.processInfo.environment["AUTONITE_SELFTEST"] == "whisper"
    }

    static let whisperSentinel = "autonite whisper selftest succeeded"

    @MainActor
    static func run(_ model: FeasibilityModel) async {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        log("selftest started")

        // Speech assets may be missing in the Simulator, so a locale check that never returns
        // is reported rather than allowed to hang the test.
        let localesChecked = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await model.checkLocales(); return true }
            group.addTask { try? await Task.sleep(for: .seconds(20)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        if localesChecked {
            expect(model.report.locales.count == SpeechLanguage.allCases.count, "locale check did not cover every language")
            for check in model.report.locales {
                log("selftest locale \(check.language.rawValue): supported=\(check.supported) installed=\(check.installedBeforeRun)")
            }
        } else {
            log("selftest locale check did not return within 20 s (unverified in Simulator)")
        }

        let otherSpeech = Utterance(start: 0, end: 1, text: "x", latency: 0, meanLevelDB: -20, predicted: .other, predictionConfidence: 1)
        expect(CueGate.evaluate(otherSpeech) != .deliver, "gate delivered a cue on the other speaker")
        expect(model.report.jsonString().contains("deviceModel"), "report did not encode")
        expect(model.state == .idle && !model.isRecording, "model did not start idle")

        // Pass 1 paths: enrolment, a saved profile, and a reading through the own-speech gate.
        var onboarding = Onboarding()
        onboarding.answerBiometricConsent(true)
        onboarding.update { $0.confirmPlacement() }
        expect(onboarding.mayRecordEnrolment, "enrolment could not record after consent")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-profile")
        let store = VoiceProfileStore(directory: folder)
        do {
            try store.save(VoiceProfile(enrollmentAudio: [0, 0.1], sampleRate: 16_000, voiceprint: [1, 0]))
            expect(try store.load() != nil, "profile did not reload")
            try store.delete()
            expect(try store.load() == nil, "profile was not deleted")
        } catch {
            failures.append("profile store failed: \(error.localizedDescription)")
        }
        let mine = Utterance(start: 0, end: 2, text: "그거 내가 할게.", latency: 0, meanLevelDB: nil,
                             predicted: .user, predictionConfidence: 0.9, overlapped: false, voiceMatch: 0.8)
        var screen = LiveScreen()
        screen.start()
        let cued = screen.receive(ReadingPipeline.evaluate(mine, language: .korean, settings: .niceDefault), phrase: mine.text, language: .korean)
        expect(cued, "a 반말 phrase under polite settings did not cue")
        let theirs = Utterance(start: 0, end: 2, text: mine.text, latency: 0, meanLevelDB: nil, predicted: .other, predictionConfidence: 1)
        expect(ReadingPipeline.evaluate(theirs, language: .korean, settings: .niceDefault) != .read(PhraseReader.read(theirs.text, language: .korean, settings: .niceDefault), cue: true),
               "the other speaker's words were read")
        log("selftest pass1 paths checked")

        if failures.isEmpty {
            log(sentinel)
            exit(0)
        }
        failures.forEach { log("selftest FAIL: \($0)") }
        exit(1)
    }

    /// Loads Whisper tiny (downloaded into a temporary folder) and reads speech that CI made with
    /// `say` and copied into the app's tmp folder: `selftest-clips/en.wav`, and `ko.wav` when the
    /// runner has a Korean voice. It logs each read's words and time. The clips are synthesized
    /// speech, never microphone audio.
    @MainActor
    static func runWhisper() async {
        log("whisper selftest started")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-clips", isDirectory: true)
        var clips: [(path: String, language: SpeechLanguage)] = []
        for (name, language) in [("en.wav", SpeechLanguage.english), ("ko.wav", .korean)] {
            let path = folder.appendingPathComponent(name).path
            if FileManager.default.fileExists(atPath: path) { clips.append((path, language)) }
        }
        guard clips.contains(where: { $0.language == .english }) else {
            log("whisper selftest FAIL: no English clip in \(folder.path)")
            exit(1)
        }
        if !clips.contains(where: { $0.language == .korean }) {
            log("whisper selftest: no Korean clip (no Korean voice on this runner)")
        }
        var failures: [String] = []
        do {
            let started = Date()
            let results = try await WhisperReader.selfTest(clips: clips, variant: "openai_whisper-tiny")
            log("whisper selftest: download, load and reads took \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
            for (result, clip) in zip(results, clips) {
                let text = result.text ?? ""
                log("whisper selftest \(clip.language.rawValue): \(String(format: "%.2f", result.seconds)) s: \(text.isEmpty ? "(nothing)" : text)")
                switch clip.language {
                case .english:
                    if !text.lowercased().contains("tomorrow") { failures.append("the English clip did not read as 'tomorrow'") }
                case .korean:
                    if !text.unicodeScalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) }) {
                        failures.append("the Korean clip read without Hangul")
                    }
                }
            }
            if results.count != clips.count { failures.append("\(results.count) reads for \(clips.count) clips") }
        } catch {
            failures.append("Whisper failed: \(error.localizedDescription)")
        }
        if failures.isEmpty {
            log(whisperSentinel)
            exit(0)
        }
        failures.forEach { log("whisper selftest FAIL: \($0)") }
        exit(1)
    }

    /// Unbuffered, so lines reach `simctl launch --console` before the app exits or is killed.
    private static func log(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}
#endif
