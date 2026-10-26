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

        if failures.isEmpty {
            log(sentinel)
            exit(0)
        }
        failures.forEach { log("selftest FAIL: \($0)") }
        exit(1)
    }

    /// Unbuffered, so lines reach `simctl launch --console` before the app exits or is killed.
    private static func log(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}
#endif
