#if os(iOS)
import AVFoundation
import AutoniteCore
import FluidAudio
import Foundation

/// FluidAudio's Sortformer streaming diarizer, with the user's slot found by voiceprint.
///
/// The saved profile holds voiceprints only, no audio (rubric M3), and Sortformer can only prime a
/// slot from audio. So the diarizer runs unprimed, and `UserSlotFinder` names the slot whose
/// speech matches the user's prints. Until it does, nothing is called the user's and no cue fires.
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
    private var finder = UserSlotFinder()

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

    /// Builds the saved profile from an enrolment clip: its WeSpeaker voiceprints, not the audio.
    func makeProfile(samples: [Float], sampleRate: Double) throws -> VoiceProfile {
        try makeProfile(reading: [], freeSpeech: samples, sampleRate: sampleRate)
    }

    /// Builds the Pass 1 profile. The voiceprint averages the scripted reading and the free speech,
    /// so both registers and both speaking styles count, and one print per few seconds keeps each
    /// tone. Only the prints are kept; the audio is dropped when this returns (rubric M3).
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
            return VoiceProfile(voiceprint: mean, voiceprints: pieces)
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

    /// Starts a new stream that looks for the voice of an enrolment clip held in memory (the lab's
    /// enrol button). Returns false when the clip gave no print. The clip itself is not kept.
    func beginSession(enrollment: [Float], sampleRate: Double) throws -> Bool {
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
            findUser()
        }
    }

    /// Caller holds the lock. Prints each slot's latest clear stretch (at most every
    /// `UserSlotFinder.recheckSeconds`) and lets the finder name the user's slot.
    private func findUser() {
        guard !enrolledPrints.isEmpty else { return }
        for (slot, window) in finder.windows(in: Array(finalized.suffix(20)) + tentative) {
            guard let print = printOf(start: window.lowerBound, end: window.upperBound),
                  let match = VoiceVerifier.bestMatch(print, against: enrolledPrints + sessionPrints) else { continue }
            userSlot = finder.record(slot: slot, window: window, match: match)
        }
    }

    /// Flushes the remaining audio so every turn is final. FluidAudio closes its still-open
    /// segments after this last update, so they are kept as final here; dropping them lost the
    /// session's last turn (found by the CI voice self-test, round 2).
    func finish() throws {
        try lock.withLock {
            if let update = try diarizer.finalizeSession() { apply(update) }
            finalized += tentative
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

    /// A copy of the held 16 kHz audio from `start` to `end`, for Whisper's second listen, or nil
    /// when none of that stretch is held any more. Memory only; nothing is written to disk.
    func audio(start: Double, end: Double) -> [Float]? {
        lock.withLock {
            let recentStart = recentEnd - Double(recent.count) / Self.printRate
            let from = max(0, Int(((start - recentStart) * Self.printRate).rounded()))
            let to = min(recent.count, Int(((end - recentStart) * Self.printRate).rounded()))
            guard to > from else { return nil }
            return Array(recent[from..<to])
        }
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
    /// Starts a new stream that looks for the profile's voice (SPEC AC3). The user's slot is
    /// unknown until their speech matches the prints. Returns false when the profile has no print.
    func enroll(_ profile: VoiceProfile) throws -> Bool {
        lock.withLock {
            diarizer.reset()
            finalized = []
            tentative = []
            recent = []
            recentEnd = 0
            inputSamples = 0
            enrolledPrints = profile.allPrints.filter { !$0.isEmpty }
            sessionPrints = []
            finder = UserSlotFinder()
            userSlot = nil
            return !enrolledPrints.isEmpty
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
