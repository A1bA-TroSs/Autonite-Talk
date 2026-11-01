#if os(iOS)
import AVFoundation
import AutoniteCore
import Foundation
import Speech

enum EngineEvent: Sendable {
    case level(db: Double)
    case volatile(text: String)
    case final(text: String, start: Double, end: Double, latency: Double, words: [WordSpan])
    case interruption(began: Bool)
    case failed(String)
}

enum EngineError: LocalizedError {
    case transcriberUnavailable
    case localeUnsupported(SpeechLanguage)
    case microphoneDenied
    case noCompatibleFormat
    case converterUnavailable

    var errorDescription: String? {
        switch self {
        case .transcriberUnavailable: "SpeechTranscriber is not available on this device."
        case .localeUnsupported(let language): "\(language.displayName) is not supported by SpeechTranscriber on this device."
        case .microphoneDenied: "Microphone access was denied. Enable it in Settings."
        case .noCompatibleFormat: "No audio format is compatible with the installed speech assets."
        case .converterUnavailable: "Could not convert microphone audio to the analyzer format."
        }
    }
}

/// Microphone → SpeechAnalyzer pipeline, one language per session.
///
/// Not actor-isolated on purpose: the audio tap runs on a real-time thread, and a tap
/// closure that inherits main-actor isolation traps at runtime.
final class LiveTranscriptionEngine: @unchecked Sendable {
    /// The audio session mode under test. `.measurement` turns off automatic gain control,
    /// which the level-based attribution experiment depends on.
    static var audioSessionMode: AVAudioSession.Mode { .measurement }

    let events: AsyncStream<EngineEvent>
    let levels = LevelTimeline()
    /// Mono samples at the input rate, for the voice diarizer. Set before `start`; called on the tap thread.
    var onSamples: (@Sendable ([Float], Double) -> Void)?

    private let continuation: AsyncStream<EngineEvent>.Continuation
    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: EngineEvent.self)
        events = stream
        self.continuation = continuation
    }

    // MARK: Locale checks

    static func check(_ language: SpeechLanguage) async -> FeasibilityReport.LocaleCheck {
        let requested = Locale(identifier: language.localeIdentifier)
        let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: requested)
        let installed = await SpeechTranscriber.installedLocales
        let isInstalled = resolved.map { locale in
            installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
        } ?? false
        return .init(
            language: language,
            resolvedIdentifier: resolved?.identifier(.bcp47),
            supported: resolved != nil,
            installedBeforeRun: isInstalled
        )
    }

    // MARK: Session

    func start(language: SpeechLanguage) async throws {
        guard SpeechTranscriber.isAvailable else { throw EngineError.transcriberUnavailable }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language.localeIdentifier)) else {
            throw EngineError.localeUnsupported(language)
        }
        guard await AVAudioApplication.requestRecordPermission() else { throw EngineError.microphoneDenied }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange]
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: Self.audioSessionMode, options: [.defaultToSpeaker])
        // iOS mutes haptics while recording unless this is set. The live cue depends on it.
        try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw EngineError.noCompatibleFormat
        }
        try await analyzer.prepareToAnalyze(in: analyzerFormat)

        let (inputSequence, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await analyzer.start(inputSequence: inputSequence)
        self.analyzer = analyzer
        self.inputBuilder = inputBuilder

        levels.reset()
        let captureStart = Date()
        resultsTask = Task { [continuation] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        let start = result.range.start.seconds
                        let end = result.range.end.seconds
                        let latency = Date().timeIntervalSince(captureStart) - end
                        continuation.yield(.final(text: text, start: start, end: end, latency: latency, words: Self.words(in: result.text)))
                    } else {
                        continuation.yield(.volatile(text: text))
                    }
                }
            } catch {
                continuation.yield(.failed("Transcription stopped: \(error.localizedDescription)"))
            }
        }

        try startCapture(into: inputBuilder, analyzerFormat: analyzerFormat)
        observeInterruptions()
    }

    func stop() async {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        inputBuilder?.finish()
        inputBuilder = nil
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            continuation.yield(.failed("Finalizing failed: \(error.localizedDescription)"))
        }
        await resultsTask?.value
        resultsTask = nil
        analyzer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Word runs with their audio times. Runs without a time (spacing) join the word before them.
    private static func words(in text: AttributedString) -> [WordSpan] {
        var words: [WordSpan] = []
        for run in text.runs {
            let piece = String(text[run.range].characters)
            if let range = run.audioTimeRange {
                words.append(WordSpan(text: piece, start: range.start.seconds, end: range.end.seconds))
            } else if !words.isEmpty {
                words[words.count - 1].text += piece
            }
        }
        return words
    }

    // MARK: Capture

    private func startCapture(into builder: AsyncStream<AnalyzerInput>.Continuation, analyzerFormat: AVAudioFormat) throws {
        let input = audioEngine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = BufferConverter(from: inputFormat, to: analyzerFormat) else {
            throw EngineError.converterUnavailable
        }
        let levels = self.levels
        let continuation = self.continuation
        let sampleRate = inputFormat.sampleRate
        let clock = FrameClock()
        let onSamples = self.onSamples

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { @Sendable buffer, _ in
            let midpoint = clock.advance(by: buffer.frameLength, sampleRate: sampleRate)
            if let channel = buffer.floatChannelData?[0] {
                let db = LevelTimeline.rmsDB(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
                levels.append(time: midpoint, db: db)
                continuation.yield(.level(db: db))
                onSamples?(Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))), sampleRate)
            }
            if let converted = converter.convert(buffer) {
                builder.yield(AnalyzerInput(buffer: converted))
            }
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func observeInterruptions() {
        let continuation = self.continuation
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            continuation.yield(.interruption(began: type == .began))
        }
    }
}

/// Capture time in seconds, counted from frames so it matches the analyzer's timeline.
private final class FrameClock: @unchecked Sendable {
    private var frames: Double = 0

    /// Advances by one buffer and returns the buffer's midpoint time. Called only from the tap.
    func advance(by count: AVAudioFrameCount, sampleRate: Double) -> Double {
        let start = frames / sampleRate
        frames += Double(count)
        return (start + frames / sampleRate) / 2
    }
}

/// Wraps AVAudioConverter for use from the tap thread only.
private final class BufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat

    init?(from input: AVAudioFormat, to output: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: input, to: output) else { return nil }
        self.converter = converter
        self.outputFormat = output
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == outputFormat { return buffer }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        // The input block may be imported as @Sendable; it runs synchronously inside convert.
        nonisolated(unsafe) let input = buffer
        let supplied = SuppliedFlag()
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied.value {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied.value = true
            inputStatus.pointee = .haveData
            return input
        }
        return status == .error || error != nil ? nil : output
    }
}

private final class SuppliedFlag: @unchecked Sendable {
    var value = false
}
#endif
