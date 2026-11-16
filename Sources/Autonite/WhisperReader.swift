#if os(iOS)
import AutoniteCore
import Foundation
import WhisperKit

/// Whisper (WhisperKit, MIT; Core ML on this iPhone) as a second listen to the user's own speech.
/// Apple's SpeechTranscriber stays the live path. This re-reads pieces the voice gate already gave
/// to the user and corrects their words on the card and in the recap; it never decides a cue
/// (`SecondReading`). Models download once, after the user turns Whisper on, from Hugging Face
/// (argmaxinc/whisperkit-coreml, free) into Application Support, kept out of backups.
///
/// Not actor-isolated, like the other audio classes: a read runs on a background task, and the
/// caller awaits each read before starting the next, so the model is never used twice at once.
final class WhisperReader: @unchecked Sendable {
    enum Model: String, CaseIterable, Codable, Sendable {
        /// 479 MB on disk; 0.34 s per 1.85 s Korean clip warm on an M4. With the app's word list it
        /// catches 8 of the 9 swears on the ko20 bench (docs/loop/whisper-bench/RESULTS.md). Keeps up
        /// with talk.
        case standard = "openai_whisper-small"
        /// Large-v3 turbo, 4-bit (606 MB on disk). 1.11 s per 1.85 s clip warm on an M4 and the same
        /// 8 of 9 swears as small on that bench, so on an iPhone its re-reads may finish after the
        /// session.
        case accurate = "openai_whisper-large-v3-v20240930_626MB"
    }

    static let repo = "argmaxinc/whisperkit-coreml"

    private let lock = NSLock()
    private var kit: WhisperKit?
    private var loadedModel: Model?

    var loaded: Model? { lock.withLock { loadedModel } }

    /// Application Support/Whisper, excluded from backups.
    static func folder() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var folder = base.appendingPathComponent("Whisper", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        return folder
    }

    /// The model's folder when a download finished and loaded once, otherwise nil.
    static func downloadedFolder(_ model: Model) -> URL? {
        guard let base = try? folder() else { return nil }
        let folder = HubApiWrapper(downloadBase: base).localRepoLocation(HubApiWrapper.Repo(id: repo))
            .appendingPathComponent(model.rawValue, isDirectory: true)
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent(completeMarker).path) ? folder : nil
    }

    private static let completeMarker = ".autunite-complete"

    /// Downloads the model unless it is already on the phone, then loads it. `progress` reports the
    /// download from 0 to 1; `preparing` is called when loading starts, which takes minutes the
    /// first time while Core ML compiles the model for this iPhone.
    func load(_ model: Model, progress: @escaping @Sendable (Double) -> Void, preparing: @escaping @Sendable () -> Void) async throws {
        if loaded == model { return }
        await unload()
        let base = try Self.folder()
        let folder: URL
        if let local = Self.downloadedFolder(model) {
            folder = local
        } else {
            folder = try await WhisperKit.download(variant: model.rawValue, downloadBase: base, from: Self.repo,
                                                   progressCallback: { progress($0.fractionCompleted) })
        }
        preparing()
        let config = WhisperKitConfig(model: model.rawValue, downloadBase: base, modelRepo: Self.repo, modelFolder: folder.path,
                                      verbose: false, logLevel: .error, prewarm: true, load: true, download: false)
        let kit = try await WhisperKit(config)
        try? Data().write(to: folder.appendingPathComponent(Self.completeMarker))
        lock.withLock {
            self.kit = kit
            loadedModel = model
        }
    }

    func unload() async {
        let kit = lock.withLock { () -> WhisperKit? in
            let kit = self.kit
            self.kit = nil
            loadedModel = nil
            return kit
        }
        await kit?.unloadModels()
    }

    /// Unloads and deletes every downloaded model and its tokenizer.
    func deleteModels() async throws {
        await unload()
        let folder = try Self.folder()
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    /// Whisper's words for 16 kHz mono audio, cleaned (`SecondReading.clean`), and whether it was
    /// sure of them; nil when it heard nothing worth showing. The audio stays in memory.
    func read(_ samples: [Float], language: SpeechLanguage) async throws -> SecondReading.Heard? {
        guard let kit = lock.withLock({ self.kit }) else { return nil }
        let options = DecodingOptions(
            verbose: false, task: .transcribe, language: language == .korean ? "ko" : "en",
            temperature: 0, temperatureFallbackCount: 2, usePrefillPrompt: true, detectLanguage: false,
            skipSpecialTokens: true, withoutTimestamps: false, wordTimestamps: false,
            // Pieces are short; the default 1 s clip would skip a piece under a second entirely.
            windowClipTime: 0.3, suppressBlank: true,
            compressionRatioThreshold: 2.4, logProbThreshold: -1.0, firstTokenLogProbThreshold: -1.5, noSpeechThreshold: 0.6,
            // One worker: parallel workers slowed every file on the Mac bench.
            concurrentWorkerCount: 1
        )
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        let kept = results.flatMap(\.segments).compactMap { segment -> (text: String, logProbability: Double)? in
            SecondReading.clean(segment.text, noSpeechProbability: Double(segment.noSpeechProb),
                                averageLogProbability: Double(segment.avgLogprob), compressionRatio: Double(segment.compressionRatio))
                .map { (text: $0, logProbability: Double(segment.avgLogprob)) }
        }
        guard !kept.isEmpty else { return nil }
        return SecondReading.Heard(text: kept.map(\.text).joined(separator: " "),
                                   sure: SecondReading.isSure(averageLogProbabilities: kept.map(\.logProbability)))
    }

    /// The CI Simulator self-test (rubric M9): a reader with `variant` downloaded into a temporary
    /// folder, so the test goes through the same `read` the app uses. Never used on a phone.
    static func selfTestReader(variant: String) async throws -> WhisperReader {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-selftest", isDirectory: true)
        let folder = try await WhisperKit.download(variant: variant, downloadBase: base, from: repo)
        let config = WhisperKitConfig(model: variant, downloadBase: base, modelRepo: repo, modelFolder: folder.path,
                                      verbose: false, logLevel: .error, load: true, download: false)
        let kit = try await WhisperKit(config)
        let reader = WhisperReader()
        reader.lock.withLock { reader.kit = kit }
        return reader
    }

    /// 16 kHz mono samples of an audio file, for the self-test's synthesized clips.
    static func samples(ofFile path: String) throws -> [Float] {
        try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
    }
}
#endif
