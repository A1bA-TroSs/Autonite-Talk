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

    // Voice attribution (experiment 2)
    enum VoiceStatus: Equatable {
        case notLoaded
        case loading
        case ready
        case failed(String)
    }
    var voiceStatus: VoiceStatus = .notLoaded
    var isEnrolling = false
    /// The enrolment clip, in memory only for this app run. Never written to disk.
    private var enrollment: (samples: [Float], sampleRate: Double)?
    var isEnrolled: Bool { enrollment != nil }
    /// Voice attribution is used when the model is loaded and a voice is enrolled; otherwise level.
    var method: AttributionMethod { voiceStatus == .ready && isEnrolled ? .voice : .level }
    private(set) var sessionMethod: AttributionMethod = .level
    private let voice = VoiceDiarizer()
    private var voiceFeed: AsyncStream<([Float], Double)>.Continuation?
    private var voiceFeedTask: Task<Void, Never>?
    private var resolveTask: Task<Void, Never>?
    private var pending: [PendingLine] = []

    /// A final transcript line waiting for the diarizer to catch up with its end time.
    private struct PendingLine {
        let words: [WordSpan]
        let start: Double
        let end: Double
        let text: String
        let latency: Double
        let arrived: Date
    }

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

    var attribution: AttributionScore { AttributionScore(utterances: utterances, method: sessionMethod) }
    var attributionDelay: LatencyStats { LatencyStats(samples: utterances.compactMap(\.attributionDelay)) }
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
        pending = []
        sessionMethod = method
        let engine = LiveTranscriptionEngine()
        self.engine = engine
        if sessionMethod == .voice, let enrollment {
            do {
                if try voice.beginSession(enrollment: enrollment.samples, sampleRate: enrollment.sampleRate) == nil {
                    failures.append("Enrolment found no speech; using level attribution")
                    sessionMethod = .level
                }
            } catch {
                failures.append("Voice session failed: \(error.localizedDescription); using level attribution")
                sessionMethod = .level
            }
        }
        if sessionMethod == .voice {
            let (stream, feed) = AsyncStream.makeStream(of: ([Float], Double).self)
            engine.onSamples = { samples, rate in feed.yield((samples, rate)) }
            voiceFeed = feed
            let voice = self.voice
            voiceFeedTask = Task.detached {
                for await (samples, rate) in stream {
                    try? voice.feed(samples, sampleRate: rate)
                }
            }
            resolveTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    self?.resolvePending(final: false)
                }
            }
        }
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
            resolveTask?.cancel()
            voiceFeed?.finish()
            voiceFeed = nil
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
        if sessionMethod == .voice {
            resolveTask?.cancel()
            resolveTask = nil
            voiceFeed?.finish()
            voiceFeed = nil
            await voiceFeedTask?.value
            voiceFeedTask = nil
            do { try voice.finish() } catch { failures.append("Diarizer finish failed: \(error.localizedDescription)") }
            resolvePending(final: true)
        }
        self.engine = nil
        if let startedAt {
            report.sessions.append(.init(
                language: language,
                startedAt: startedAt,
                duration: Date().timeIntervalSince(startedAt),
                audioSessionMode: LiveTranscriptionEngine.audioSessionMode.rawValue,
                utterances: utterances,
                interruptions: interruptions,
                failures: failures,
                attributionMethod: sessionMethod
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
        case .final(let text, let start, let end, let latency, let words):
            volatileText = ""
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if sessionMethod == .voice {
                pending.append(PendingLine(words: words, start: start, end: end, text: text, latency: latency, arrived: Date()))
                resolvePending(final: false)
                return
            }
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
        // Voice predictions are fixed when made, so tagging does not change them.
        guard sessionMethod == .level else { return }
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

    // MARK: Voice attribution

    func loadVoiceModel() async {
        guard voiceStatus != .loading, voiceStatus != .ready else { return }
        voiceStatus = .loading
        do {
            try await voice.load()
            voiceStatus = .ready
        } catch {
            voiceStatus = .failed(error.localizedDescription)
        }
    }

    /// Records the user's voice for 10 s. Only the user should speak.
    func enroll() async {
        guard state == .idle, !isEnrolling else { return }
        isEnrolling = true
        defer { isEnrolling = false }
        do {
            let clip = try await EnrollmentRecorder().record(seconds: 10)
            enrollment = clip
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Splits each waiting line once the diarizer has final turns past its end, or all of them at the end of a session.
    private func resolvePending(final: Bool) {
        guard !pending.isEmpty else { return }
        let snapshot = voice.snapshot()
        while let line = pending.first, final || snapshot.finalizedUntil >= line.end {
            pending.removeFirst()
            let delay = Date().timeIntervalSince(line.arrived) + line.latency
            let words = line.words.isEmpty ? [WordSpan(text: line.text, start: line.start, end: line.end)] : line.words
            for piece in VoiceSplitter.split(words: words, turns: snapshot.turns, userSlot: snapshot.userSlot) {
                utterances.append(Utterance(
                    start: piece.start, end: piece.end, text: piece.text, latency: line.latency,
                    meanLevelDB: engine?.levels.meanDB(from: piece.start, to: piece.end),
                    predicted: piece.label, predictionConfidence: piece.confidence,
                    voiceSlot: piece.slot, overlapped: piece.overlapped, attributionDelay: delay
                ))
            }
        }
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
