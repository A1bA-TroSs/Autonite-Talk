#if os(iOS)
import AVFoundation
import AutoniteCore
import FluidAudio
import Foundation

/// Pass 0 experiment 2: FluidAudio's Sortformer streaming diarizer with the user's voice enrolled.
///
/// Not actor-isolated, like `LiveTranscriptionEngine`: audio arrives from a background task and
/// Core ML runs there. Every access to the diarizer goes through the lock.
final class VoiceDiarizer: @unchecked Sendable {
    struct Snapshot: Sendable {
        /// Finalized turns plus the tentative tail.
        let turns: [SpeakerTurn]
        /// Audio time up to which the turns are final, in seconds from the start of capture.
        let finalizedUntil: Double
        let userSlot: Int?
    }

    private let lock = NSLock()
    private let diarizer = SortformerDiarizer(config: .default)
    private var loaded = false
    private var finalized: [SpeakerTurn] = []
    private var tentative: [SpeakerTurn] = []
    private var userSlot: Int?

    var isLoaded: Bool { lock.withLock { loaded } }

    /// Downloads the Core ML models on first use (from Hugging Face, free), then loads them.
    func load() async throws {
        if isLoaded { return }
        let models = try await SortformerModels.loadFromHuggingFace(config: .default)
        lock.withLock {
            diarizer.initialize(models: models)
            loaded = true
        }
    }

    /// Starts a new stream with the enrolled voice in a known slot. Returns that slot, or nil
    /// when enrolment found no speech. The enrolment audio is used here and not kept by the diarizer.
    func beginSession(enrollment: [Float], sampleRate: Double) throws -> Int? {
        try lock.withLock {
            diarizer.reset()
            finalized = []
            tentative = []
            userSlot = try diarizer.enrollSpeaker(withAudio: enrollment, sourceSampleRate: sampleRate, named: "Me")?.index
            return userSlot
        }
    }

    func feed(_ samples: [Float], sampleRate: Double) throws {
        try lock.withLock {
            try diarizer.addAudio(samples, sourceSampleRate: sampleRate)
            while let update = try diarizer.process() {
                apply(update)
            }
        }
    }

    /// Flushes the remaining audio so every turn is final.
    func finish() throws {
        try lock.withLock {
            if let update = try diarizer.finalizeSession() { apply(update) }
            tentative = []
        }
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            let frameSeconds = Double(diarizer.config.frameDurationSeconds)
            return Snapshot(
                turns: finalized + tentative,
                finalizedUntil: Double(diarizer.numFramesProcessed) * frameSeconds,
                userSlot: userSlot
            )
        }
    }

    /// Caller holds the lock.
    private func apply(_ update: DiarizerTimelineUpdate) {
        finalized += update.finalizedSegments.map(Self.turn)
        tentative = update.tentativeSegments.map(Self.turn)
    }

    private static func turn(_ segment: DiarizerSegment) -> SpeakerTurn {
        SpeakerTurn(slot: segment.speakerIndex, start: Double(segment.startTime), end: Double(segment.endTime))
    }
}

/// Records a short clip of the user's voice for enrolment. The samples stay in memory only.
final class EnrollmentRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []

    /// Records for `seconds` and returns mono samples and their sample rate.
    func record(seconds: Double) async throws -> (samples: [Float], sampleRate: Double) {
        guard await AVAudioApplication.requestRecordPermission() else { throw EngineError.microphoneDenied }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: LiveTranscriptionEngine.audioSessionMode, options: [.defaultToSpeaker])
        try session.setActive(true)
        lock.withLock { samples = [] }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable [self] buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let chunk = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            lock.withLock { samples.append(contentsOf: chunk) }
        }
        engine.prepare()
        try engine.start()
        try? await Task.sleep(for: .seconds(seconds))
        engine.stop()
        input.removeTap(onBus: 0)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        return (lock.withLock { samples }, format.sampleRate)
    }
}
#endif
