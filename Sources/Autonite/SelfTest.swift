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

    /// `AUTONITE_SELFTEST=voice`: the voiceprint-only voice path (rubric M3 and M5), run in CI.
    static var isVoiceRequested: Bool {
        ProcessInfo.processInfo.environment["AUTONITE_SELFTEST"] == "voice"
    }

    static let voiceSentinel = "autonite voice selftest succeeded"

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
            try store.save(VoiceProfile(voiceprint: [1, 0], voiceprints: [[1, 0]]))
            expect(try store.load() != nil, "profile did not reload")
            // Rubric M3: the saved profile holds prints only, no samples.
            let saved = try Data(contentsOf: folder.appendingPathComponent("voice-profile.plist"))
            expect(!VoiceProfileStore.holdsAudio(saved), "the saved profile holds audio")
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
            let reader = try await WhisperReader.selfTestReader(variant: "openai_whisper-tiny")
            log("whisper selftest: tiny downloaded and loaded in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
            for clip in clips {
                let samples = try WhisperReader.samples(ofFile: clip.path)
                log("whisper selftest \(clip.language.rawValue) clip: \(String(format: "%.1f", Double(samples.count) / 16_000)) s of audio")
                // Rubric M6: the main actor keeps running while Whisper reads. A ticker on the main
                // actor counts 20 ms steps during the read; a read on the main actor would stop it.
                let ticker = Task { @MainActor () -> Int in
                    var ticks = 0
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(20))
                        ticks += 1
                    }
                    return ticks
                }
                let readStarted = Date()
                let heard = try await reader.read(samples, language: clip.language)
                let text = heard?.text ?? ""
                let seconds = Date().timeIntervalSince(readStarted)
                ticker.cancel()
                let ticks = await ticker.value
                log("whisper selftest \(clip.language.rawValue): \(String(format: "%.2f", seconds)) s, main actor ticked \(ticks) times, sure: \(heard?.sure == true): \(text.isEmpty ? "(nothing)" : text)")
                if seconds >= 0.3, ticks < 3 { failures.append("the main actor stalled during the \(clip.language.rawValue) read") }
                switch clip.language {
                case .english:
                    if !text.lowercased().contains("tomorrow") { failures.append("the English clip did not read as 'tomorrow'") }
                case .korean:
                    if !text.unicodeScalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) }) {
                        failures.append("the Korean clip read without Hangul")
                    }
                }
            }
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

    /// The voice path end to end on speech CI made with `say` and copied into the app's tmp folder
    /// (`selftest-voice/`): a profile is made from one synthetic voice and must hold no audio; then a
    /// conversation of that voice and another runs through the unprimed diarizer, and the user's
    /// slot must be found by voiceprint, on the right voice. Synthesized speech, never microphone audio.
    @MainActor
    static func runVoice() async {
        log("voice selftest started")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-voice", isDirectory: true)
        let rate = 16_000.0
        var failures: [String] = []
        do {
            let voice = VoiceDiarizer()
            let started = Date()
            try await voice.load()
            log("voice selftest: diarizer and voiceprint models loaded in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")

            let enrolment = try WhisperReader.samples(ofFile: folder.appendingPathComponent("me-enrol.wav").path)
            let profile = try voice.makeProfile(reading: [], freeSpeech: enrolment, sampleRate: rate)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let saved = try encoder.encode(profile)
            log("voice selftest: profile from \(String(format: "%.1f", Double(enrolment.count) / rate)) s of speech: \(profile.allPrints.count) prints, \(saved.count) bytes")
            if VoiceProfileStore.holdsAudio(saved) { failures.append("the profile holds audio") }
            if try !voice.enroll(profile) { failures.append("the profile was not taken") }

            // Other, user, other, user, with a short pause between turns.
            var audio: [Float] = []
            var mine: [ClosedRange<Double>] = []
            var theirs: [ClosedRange<Double>] = []
            for name in ["turn1-other", "turn2-me", "turn3-other", "turn4-me"] {
                let turn = try WhisperReader.samples(ofFile: folder.appendingPathComponent("\(name).wav").path)
                let start = Double(audio.count) / rate
                audio += turn
                let range = start...(Double(audio.count) / rate)
                if name.hasSuffix("-me") { mine.append(range) } else { theirs.append(range) }
                audio += [Float](repeating: 0, count: Int(rate * 0.4))
            }
            // The early-cue gate on the real diarizer (rubric M5): in every turn a swear "shows up" in
            // the in-progress text 0.4 s after the turn's middle. The other's must never cue early.
            var planted: [(mine: Bool, turn: ClosedRange<Double>, hit: EarlyCueGate.Hit, verdict: EarlyCueGate.Verdict?, at: Double?)] = []
            for (isMine, turn) in mine.map({ (true, $0) }) + theirs.map({ (false, $0) }) {
                let heardAt = (turn.lowerBound + turn.upperBound) / 2 + 0.4
                planted.append((isMine, turn, EarlyCueGate.Hit(text: "아 존나", closed: false, hits: 1, heardAt: heardAt, since: heardAt), nil, nil))
            }
            var check: EarlyCueGate.Check?
            var checkedAt = -1.0
            // Fed in 100 ms chunks, as the microphone delivers it, with the app's 250 ms background check.
            let chunk = Int(rate / 10)
            var foundAt: Double?
            let fedStarted = Date()
            for offset in stride(from: 0, to: audio.count, by: chunk) {
                try voice.feed(Array(audio[offset..<min(offset + chunk, audio.count)]), sampleRate: rate)
                let position = Double(min(offset + chunk, audio.count)) / rate
                let state = voice.snapshot()
                if foundAt == nil, state.userSlot != nil { foundAt = position }
                if position - checkedAt >= 0.25 {
                    checkedAt = position
                    check = FeasibilityModel.checkRecent(voice, state).map { EarlyCueGate.Check(window: $0.window, match: $0.match, slot: state.userSlot) }
                }
                for i in planted.indices where planted[i].verdict == nil && planted[i].hit.heardAt <= position {
                    let verdict = EarlyCueGate.judge(planted[i].hit, check: check, turns: state.turns, userSlot: state.userSlot,
                                                     heardUntil: state.heardUntil, now: position)
                    if verdict != .wait {
                        planted[i].verdict = verdict
                        planted[i].at = position
                    }
                }
            }
            for item in planted.sorted(by: { $0.turn.lowerBound < $1.turn.lowerBound }) {
                let outcome: String
                switch item.verdict {
                case .cue: outcome = "cued"
                case .drop(let reason): outcome = "dropped (\(reason))"
                case .wait, nil: outcome = "still waiting when the audio ended"
                }
                let after = item.at.map { String(format: " %.1f s after the words showed up", $0 - item.hit.heardAt) } ?? ""
                log("voice selftest early cue in the \(item.mine ? "user's" : "other's") turn at \(String(format: "%.1f", item.turn.lowerBound)) s: \(outcome)\(after)")
                if !item.mine, item.verdict == .cue {
                    failures.append("an early cue fired in the other voice's turn at \(String(format: "%.1f", item.turn.lowerBound)) s")
                }
            }
            if !planted.contains(where: { $0.mine && $0.verdict == .cue }) { failures.append("no early cue fired in the user's own turns") }
            try voice.finish()
            let snapshot = voice.snapshot()
            log("voice selftest: \(String(format: "%.1f", Double(audio.count) / rate)) s of conversation diarized in \(String(format: "%.1f", Date().timeIntervalSince(fedStarted))) s")

            func overlap(_ slot: Int, _ ranges: [ClosedRange<Double>]) -> Double {
                var total = 0.0
                for turn in snapshot.turns where turn.slot == slot {
                    for range in ranges {
                        total += max(0, min(turn.end, range.upperBound) - max(turn.start, range.lowerBound))
                    }
                }
                return total
            }
            let slots = Set(snapshot.turns.map(\.slot)).sorted()
            for slot in slots {
                log("voice selftest slot \(slot): \(String(format: "%.1f", overlap(slot, mine))) s in the user's turns, \(String(format: "%.1f", overlap(slot, theirs))) s in the other's")
            }
            let expected = slots.max { overlap($0, mine) < overlap($1, mine) }
            let userSeconds = mine.reduce(0.0) { $0 + ($1.upperBound - $1.lowerBound) }
            let otherSeconds = theirs.reduce(0.0) { $0 + ($1.upperBound - $1.lowerBound) }
            log("voice selftest: user's slot found by voiceprint = \(snapshot.userSlot.map { "\($0)" } ?? "none"), expected \(expected.map { "\($0)" } ?? "none"); found at \(foundAt.map { String(format: "%.1f s", $0) } ?? "never"), the user's first turn ran \(String(format: "%.1f-%.1f s", mine[0].lowerBound, mine[0].upperBound))")
            if snapshot.userSlot == nil || snapshot.userSlot != expected { failures.append("the user's slot was not found on the user's voice") }
            if let expected {
                log("voice selftest: the user's slot covers \(String(format: "%.1f of %.1f", overlap(expected, mine), userSeconds)) s of the user's speech and \(String(format: "%.1f of %.1f", overlap(expected, theirs), otherSeconds)) s of the other's")
                // Every turn, the last one included, sits mostly in the right slot.
                for range in mine where overlap(expected, [range]) < (range.upperBound - range.lowerBound) / 2 {
                    failures.append("the user's turn at \(String(format: "%.1f", range.lowerBound)) s is mostly outside the user's slot")
                }
                for range in theirs where overlap(expected, [range]) > (range.upperBound - range.lowerBound) / 2 {
                    failures.append("the other's turn at \(String(format: "%.1f", range.lowerBound)) s is mostly in the user's slot")
                }
            }
            for range in mine {
                let match = voice.voiceMatch(start: max(range.lowerBound, range.upperBound - 3), end: range.upperBound)
                log("voice selftest user turn \(String(format: "%.1f", range.lowerBound)) s: match \(match.map { String(format: "%.2f", $0) } ?? "none")")
                if (match ?? 0) < VoiceVerifier.threshold { failures.append("a user turn did not match the profile") }
            }
            for range in theirs {
                let match = voice.voiceMatch(start: max(range.lowerBound, range.upperBound - 3), end: range.upperBound)
                log("voice selftest other turn \(String(format: "%.1f", range.lowerBound)) s: match \(match.map { String(format: "%.2f", $0) } ?? "none")")
                if let match, match >= VoiceVerifier.threshold { failures.append("the other voice matched the profile") }
            }
        } catch {
            failures.append("the voice path failed: \(error.localizedDescription)")
        }
        if failures.isEmpty {
            log(voiceSentinel)
            exit(0)
        }
        failures.forEach { log("voice selftest FAIL: \($0)") }
        exit(1)
    }

    /// Unbuffered, so lines reach `simctl launch --console` before the app exits or is killed.
    private static func log(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}
#endif
