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
    /// Used only for its WeSpeaker voiceprints (experiment 3), not for diarization.
    private let voiceprints = DiarizerManager()
    private let converter = AudioConverter()
    private var loaded = false
    /// The enrolled voiceprints (several stretches plus their mean), and prints of the user's own
    /// clearly verified speech from this session, which follow today's voice and room.
    private var enrolledPrints: [[Float]] = []
    private var sessionPrints: [[Float]] = []
    private static let maxSessionPrints = 8
    private static let chunkSeconds = 3.0
    /// The last `recentSeconds` of 16 kHz audio, in memory only, so pieces can be voiceprinted.
    private var recent: [Float] = []
    private var recentEnd = 0.0
    private var inputSamples = 0
    private static let recentSeconds = 60.0
    private static let printRate = 16_000.0
    private var finalized: [SpeakerTurn] = []
    private var tentative: [SpeakerTurn] = []
    private var userSlot: Int?

    var isLoaded: Bool { lock.withLock { loaded } }

    /// Downloads the Core ML models on first use (from Hugging Face, free), then loads them.
    func load() async throws {
        if isLoaded { return }
        let models = try await SortformerModels.loadFromHuggingFace(config: .default)
        let printModels = try await DiarizerModels.downloadIfNeeded()
        lock.withLock {
            diarizer.initialize(models: models)
            voiceprints.initialize(models: printModels)
            loaded = true
        }
    }

    /// Builds the saved profile from an enrolment clip: the audio plus its WeSpeaker voiceprint.
    func makeProfile(samples: [Float], sampleRate: Double) throws -> VoiceProfile {
        try makeProfile(reading: [], freeSpeech: samples, sampleRate: sampleRate)
    }

    /// Builds the Pass 1 profile. The voiceprint averages the scripted reading and the free speech,
    /// so both registers and both speaking styles count. The diarizer is primed from the free
    /// speech, stored at 16 kHz to keep the file small.
    func makeProfile(reading: [Float], freeSpeech: [Float], sampleRate: Double) throws -> VoiceProfile {
        try lock.withLock {
            let free = try converter.resample(freeSpeech, from: sampleRate)
            let read = reading.isEmpty ? [] : try converter.resample(reading, from: sampleRate)
            var prints = [try voiceprints.extractSpeakerEmbedding(from: Array(free.suffix(Int(Self.printRate * 10))))]
            if !read.isEmpty {
                prints.append(try voiceprints.extractSpeakerEmbedding(from: Array(read.suffix(Int(Self.printRate * 10)))))
            }
            let mean = (0..<prints[0].count).map { i in prints.map { $0[i] }.reduce(0, +) / Float(prints.count) }
            // One print per few seconds of each sentence and of the free speech, so every tone counts.
            let pieces = try chunkPrints(read) + chunkPrints(free)
            return VoiceProfile(enrollmentAudio: free, sampleRate: Self.printRate, voiceprint: mean, voiceprints: pieces)
        }
    }

    /// Caller holds the lock. Prints of consecutive `chunkSeconds` stretches of 16 kHz audio.
    private func chunkPrints(_ audio: [Float]) throws -> [[Float]] {
        let size = Int(Self.chunkSeconds * Self.printRate)
        guard audio.count >= size else { return [] }
        return try stride(from: 0, through: audio.count - size, by: size).prefix(16).map {
            try voiceprints.extractSpeakerEmbedding(from: Array(audio[$0..<($0 + size)]))
        }
    }

    /// Cosine similarity between a clip and a voiceprint, for the enrolment's random-phrase check.
    func similarity(of samples: [Float], sampleRate: Double, to voiceprint: [Float]) throws -> Double? {
        try lock.withLock {
            let clip = try converter.resample(samples, from: sampleRate)
            return VoiceVerifier.cosineSimilarity(try voiceprints.extractSpeakerEmbedding(from: clip), voiceprint)
        }
    }

    /// Starts a new stream with the enrolled voice in a known slot. Returns that slot, or nil
    /// when enrolment found no speech. The enrolment audio is used here and not kept by the diarizer.
    func beginSession(enrollment: [Float], sampleRate: Double) throws -> Int? {
        try enroll(makeProfile(samples: enrollment, sampleRate: sampleRate))
    }

    func feed(_ samples: [Float], sampleRate: Double) throws {
        try lock.withLock {
            try diarizer.addAudio(samples, sourceSampleRate: sampleRate)
            // Place each chunk by the input sample count so resampling rounding doesn't drift.
            inputSamples += samples.count
            recentEnd = Double(inputSamples) / sampleRate
            recent += try converter.resample(samples, from: sampleRate)
            let keep = Int(Self.recentSeconds * Self.printRate)
            if recent.count > keep { recent.removeFirst(recent.count - keep) }
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

    /// Cosine similarity between the enrolled voice and the audio from `start` to `end`, or nil
    /// when there is no enrolment or that audio is no longer held.
    func voiceMatch(start: Double, end: Double) -> Double? {
        lock.withLock { printOf(start: start, end: end).flatMap { VoiceVerifier.bestMatch($0, against: enrolledPrints + sessionPrints) } }
    }

    /// Adds clearly verified speech of the user's to this session's prints.
    func adapt(start: Double, end: Double) {
        lock.withLock {
            guard sessionPrints.count < Self.maxSessionPrints, let print = printOf(start: start, end: end) else { return }
            sessionPrints.append(print)
        }
    }

    /// Caller holds the lock.
    private func printOf(start: Double, end: Double) -> [Float]? {
        do {
            guard !enrolledPrints.isEmpty, end > start else { return nil }
            let recentStart = recentEnd - Double(recent.count) / Self.printRate
            let from = Int(((start - recentStart) * Self.printRate).rounded())
            let to = Int(((end - recentStart) * Self.printRate).rounded())
            guard from >= 0, to <= recent.count, to > from else { return nil }
            return try? voiceprints.extractSpeakerEmbedding(from: Array(recent[from..<to]))
        }
    }

    /// Clears the held audio and voiceprint at the end of a session.
    func clearAudio() {
        lock.withLock {
            recent = []
            enrolledPrints = []
            sessionPrints = []
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

extension VoiceDiarizer: SpeakerEnrolling {
    /// Starts a new stream with the profile's voice in a known slot (SPEC AC3). Returns that slot,
    /// or nil when the enrolment audio held no speech.
    func enroll(_ profile: VoiceProfile) throws -> Int? {
        try lock.withLock {
            diarizer.reset()
            finalized = []
            tentative = []
            recent = []
            recentEnd = 0
            inputSamples = 0
            // Profiles saved before multi-print enrolment get their prints from the stored audio.
            enrolledPrints = [profile.voiceprint] + (profile.voiceprints ?? (try chunkPrints(profile.enrollmentAudio)))
            sessionPrints = []
            userSlot = try diarizer.enrollSpeaker(withAudio: profile.enrollmentAudio, sourceSampleRate: profile.sampleRate, named: "Me")?.index
            return userSlot
        }
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
