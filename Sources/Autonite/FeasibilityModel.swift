#if os(iOS)
import AutoniteCore
import Foundation
import Observation
import Speech
import UIKit

@MainActor
@Observable
final class FeasibilityModel {
    enum State: Equatable {
        case idle
        case preparing
        case recording
        case interrupted
        case finishing
    }

    var language: SpeechLanguage = .english
    var state: State = .idle
    var volatileText = ""
    var utterances: [Utterance] = []
    var levelDB: Double = -120
    var startedAt: Date?
    var lastError: String?
    var placement: FeasibilityReport.Placement = .tableFaceUp
    var report: FeasibilityReport

    private var engine: LiveTranscriptionEngine?
    private var eventsTask: Task<Void, Never>?
    private var interruptions = 0
    private var failures: [String] = []
    private let haptics = HapticProbe()

    init() {
        report = FeasibilityReport(
            deviceModel: Self.deviceModel(),
            osVersion: UIDevice.current.systemVersion,
            transcriberAvailable: SpeechTranscriber.isAvailable,
            hapticsSupported: HapticProbe.isSupported
        )
    }

    var isRecording: Bool { state == .recording || state == .interrupted }

    var attribution: AttributionScore { AttributionScore(utterances: utterances) }
    var latency: LatencyStats { LatencyStats(samples: utterances.map(\.latency)) }

    // MARK: Locale checks

    func checkLocales() async {
        var checks: [FeasibilityReport.LocaleCheck] = []
        for language in SpeechLanguage.allCases {
            checks.append(await LiveTranscriptionEngine.check(language))
        }
        report.locales = checks
    }

    // MARK: Session

    func start() async {
        guard state == .idle else { return }
        state = .preparing
        lastError = nil
        utterances = []
        volatileText = ""
        interruptions = 0
        failures = []
        let engine = LiveTranscriptionEngine()
        self.engine = engine
        eventsTask = Task { [weak self] in
            for await event in engine.events {
                self?.handle(event)
            }
        }
        do {
            try await engine.start(language: language)
            startedAt = Date()
            state = .recording
        } catch {
            lastError = error.localizedDescription
            failures.append(error.localizedDescription)
            await engine.stop()
            eventsTask?.cancel()
            self.engine = nil
            state = .idle
        }
    }

    func stop() async {
        guard isRecording, let engine else { return }
        state = .finishing
        await engine.stop()
        eventsTask?.cancel()
        eventsTask = nil
        self.engine = nil
        if let startedAt {
            report.sessions.append(.init(
                language: language,
                startedAt: startedAt,
                duration: Date().timeIntervalSince(startedAt),
                audioSessionMode: LiveTranscriptionEngine.audioSessionMode.rawValue,
                utterances: utterances,
                interruptions: interruptions,
                failures: failures
            ))
        }
        volatileText = ""
        state = .idle
    }

    private func handle(_ event: EngineEvent) {
        switch event {
        case .level(let db):
            levelDB = db
        case .volatile(let text):
            volatileText = text
        case .final(let text, let start, let end, let latency):
            volatileText = ""
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            var utterance = Utterance(
                start: start, end: end, text: text, latency: latency,
                meanLevelDB: engine?.levels.meanDB(from: start, to: end)
            )
            predict(&utterance, using: utterances)
            utterances.append(utterance)
        case .interruption(let began):
            if began {
                interruptions += 1
                state = .interrupted
            } else if state == .interrupted {
                // Pass 0 records the interruption and does not try to resume capture.
                failures.append("Capture was interrupted and not resumed")
            }
        case .failed(let message):
            failures.append(message)
            lastError = message
        }
    }

    // MARK: Attribution experiment

    func label(_ id: Utterance.ID, as truth: SpeakerLabel) {
        guard let index = utterances.firstIndex(where: { $0.id == id }) else { return }
        utterances[index].groundTruth = truth
        // Re-predict every utterance from the other labels, so the live view matches the score.
        for i in utterances.indices {
            var others = utterances
            others.remove(at: i)
            predict(&utterances[i], using: others)
        }
    }

    private func predict(_ utterance: inout Utterance, using labelled: [Utterance]) {
        guard let attributor = LevelAttributor(labelled: labelled) else {
            utterance.predicted = .unknown
            utterance.predictionConfidence = 0
            return
        }
        let (label, confidence) = attributor.predict(levelDB: utterance.meanLevelDB)
        utterance.predicted = label
        utterance.predictionConfidence = confidence
    }

    // MARK: Haptics

    func pulse() {
        haptics.pulse()
    }

    func recordHaptic(felt: Bool) {
        report.hapticTrials.append(.init(placement: placement, duringRecording: isRecording, felt: felt))
    }

    // MARK: Device

    private static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
#endif
