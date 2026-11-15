#if os(iOS)
import AVFoundation
import AutoniteCore
import Foundation
import Speech

/// CI only (`AUTONITE_SELFTEST=apple`, rubric C1): Apple's recogniser on the clips CI made with
/// `say`, streamed at real time the way the microphone delivers audio. It logs when each
/// in-progress result arrived, in seconds of audio, so the time from a word to the text that shows
/// it can be read off, and when the early reader would have flagged a harsh word against when the
/// sentence ended. The Simulator may lack the speech assets; then it says so. It never fails the
/// build and is never used on a phone. Synthesized speech only, never microphone audio.
enum AppleProbe {
    static let sentinel = "autonite apple probe finished"

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["AUTONITE_SELFTEST"] == "apple"
    }

    @MainActor
    static func runAll() async {
        log("apple probe started; SpeechTranscriber available: \(SpeechTranscriber.isAvailable)")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-clips", isDirectory: true)
        for (name, language) in [("ko-swear", SpeechLanguage.korean), ("ko", .korean), ("en", .english)] {
            let path = folder.appendingPathComponent("\(name).wav").path
            guard FileManager.default.fileExists(atPath: path) else {
                log("apple probe \(name): no clip")
                continue
            }
            do {
                try await probe(name: name, path: path, language: language)
            } catch {
                log("apple probe \(name): failed: \(error.localizedDescription)")
            }
        }
        log(sentinel)
        exit(0)
    }

    private static func probe(name: String, path: String, language: SpeechLanguage) async throws {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language.localeIdentifier)) else {
            log("apple probe \(name): \(language.rawValue) is not supported here")
            return
        }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange]
        )
        let installStarted = Date()
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        log("apple probe \(name): \(language.rawValue) speech assets ready after \(String(format: "%.1f", Date().timeIntervalSince(installStarted))) s")

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            log("apple probe \(name): no audio format fits the speech assets")
            return
        }
        let pieces = try Self.chunks(ofFile: path, in: format, seconds: 0.1)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)
        let (inputs, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await analyzer.start(inputSequence: inputs)

        let clock = FedClock()
        // Boxed so the results task can read the transcriber while this function keeps using the analyzer.
        let module = Box(transcriber)
        let collector = Task { () async -> (volatiles: [(at: Double, text: String)], finals: [(text: String, words: [WordSpan], end: Double)]) in
            var volatiles: [(at: Double, text: String)] = []
            var finals: [(text: String, words: [WordSpan], end: Double)] = []
            do {
                for try await result in module.value.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        finals.append((text, Self.words(in: result.text), result.range.end.seconds))
                    } else {
                        volatiles.append((clock.seconds, text))
                    }
                }
            } catch {
                volatiles.append((clock.seconds, "(results stopped: \(error.localizedDescription))"))
            }
            return (volatiles, finals)
        }
        // Real time: one 100 ms chunk every 100 ms, as the microphone tap would deliver it.
        for piece in pieces {
            // Each buffer goes to the analyzer once and nothing touches it afterwards.
            nonisolated(unsafe) let buffer = piece.buffer
            builder.yield(AnalyzerInput(buffer: buffer))
            clock.advance(piece.seconds)
            try? await Task.sleep(for: .milliseconds(100))
        }
        builder.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let (volatiles, finals) = await collector.value

        for volatile in volatiles {
            log("apple probe \(name) +\(String(format: "%.1f", volatile.at)) s: \(volatile.text)")
        }
        let finalText = finals.map(\.text).joined(separator: " ")
        let spans = finals.flatMap(\.words)
        log("apple probe \(name) final: \(finalText.isEmpty ? "(nothing)" : finalText); the speech ended at \(String(format: "%.1f", finals.map(\.end).max() ?? 0)) s")

        // When the early reader would first flag the line, against when the sentence ended.
        let settings = CategorySettings.niceDefault
        if let flagged = volatiles.first(where: { EarlyReader.hits(in: $0.text, language: language, settings: settings) > 0 }) {
            log("apple probe \(name): the early reader would flag it at \(String(format: "%.1f", flagged.at)) s of audio, from in-progress text")
        }
        for harsh in WordChoiceReader.harshWords(in: finalText) {
            // The word run that holds the harsh word, or the first run of a harsh word split in two.
            let said = spans.first { word in
                let run = word.text.trimmingCharacters(in: .whitespaces)
                return !run.isEmpty && (run.contains(harsh) || harsh.hasPrefix(run))
            }
            let shown = volatiles.first { $0.text.contains(harsh) }
            let saidText = said.map { String(format: "said %.1f-%.1f s", $0.start, $0.end) } ?? "no word time"
            let shownText = shown.map { String(format: "first in the in-progress text at %.1f s", $0.at) } ?? "never in the in-progress text"
            let gap = (said.flatMap { word in shown.map { $0.at - word.end } }).map { String(format: "; %.1f s from the word's end to the text", $0) } ?? ""
            log("apple probe \(name): '\(harsh)' \(saidText), \(shownText)\(gap)")
        }
    }

    /// The clip cut into chunks of `seconds`, each converted the way the live tap converts its buffers.
    private static func chunks(ofFile path: String, in format: AVAudioFormat, seconds: Double) throws -> [(buffer: AVAudioPCMBuffer, seconds: Double)] {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let source = file.processingFormat
        guard let converter = BufferConverter(from: source, to: format) else { return [] }
        let step = AVAudioFrameCount(source.sampleRate * seconds)
        var pieces: [(buffer: AVAudioPCMBuffer, seconds: Double)] = []
        while file.framePosition < file.length {
            guard let piece = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: step) else { break }
            try file.read(into: piece, frameCount: step)
            guard piece.frameLength > 0 else { break }
            if let converted = converter.convert(piece) {
                pieces.append((converted, Double(piece.frameLength) / source.sampleRate))
            }
        }
        return pieces
    }

    /// Word runs with their audio times, as the live engine reads them.
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

    private static func log(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    /// Seconds of audio fed so far, read by the results task.
    private final class FedClock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0.0
        var seconds: Double { lock.withLock { value } }
        func advance(_ by: Double) { lock.withLock { value += by } }
    }

    private final class Box<Value>: @unchecked Sendable {
        let value: Value
        init(_ value: Value) { self.value = value }
    }
}
#endif
