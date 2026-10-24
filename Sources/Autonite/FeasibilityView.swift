import AutoniteCore
import SwiftUI

/// Pass 0 harness. Not the product UI: it exists to gather device evidence.
struct FeasibilityView: View {
    @Bindable var model: FeasibilityModel

    var body: some View {
        VStack(spacing: 0) {
            if model.isRecording {
                RecordingStrip(startedAt: model.startedAt, levelDB: model.levelDB, interrupted: model.state == .interrupted)
            }
            NavigationStack {
                List {
                    deviceSection
                    sessionSection
                    if !model.utterances.isEmpty { utteranceSection }
                    hapticSection
                    reportSection
                }
                .navigationTitle("Pass 0")
            }
        }
        .task { await model.checkLocales() }
    }

    private var deviceSection: some View {
        Section("Device") {
            LabeledContent("Model", value: model.report.deviceModel)
            LabeledContent("iOS", value: model.report.osVersion)
            LabeledContent("SpeechTranscriber", value: model.report.transcriberAvailable ? "available" : "unavailable")
            ForEach(model.report.locales, id: \.language) { check in
                LabeledContent(check.language.displayName) {
                    Text(check.supported ? (check.installedBeforeRun ? "installed" : "downloadable") : "unsupported")
                        .foregroundStyle(check.supported ? Color.primary : Color.red)
                }
            }
        }
    }

    private var sessionSection: some View {
        Section {
            Picker("Speech language", selection: $model.language) {
                ForEach(SpeechLanguage.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .disabled(model.state != .idle)

            if model.isRecording {
                Button("End Session", role: .destructive) { Task { await model.stop() } }
                    .font(.title3.bold())
            } else {
                Button(model.state == .idle ? "Start Session" : "Working…") { Task { await model.start() } }
                    .font(.title3.bold())
                    .disabled(model.state != .idle)
            }
            if !model.volatileText.isEmpty {
                Text(model.volatileText).foregroundStyle(.secondary)
            }
            if let error = model.lastError {
                Text(error).foregroundStyle(.red)
            }
        } header: {
            Text("Session")
        } footer: {
            Text("Start only after everyone present knows the conversation is being recorded. No audio is kept after the session.")
        }
    }

    private var utteranceSection: some View {
        Section {
            ForEach(model.utterances) { utterance in
                UtteranceRow(utterance: utterance) { model.label(utterance.id, as: $0) }
            }
        } header: {
            Text("Utterances: who really spoke?")
        } footer: {
            Text("Tag each line Me or Other. Predictions use the level baseline fitted on the other tags.")
        }
    }

    private var hapticSection: some View {
        Section("Haptic on a table") {
            Picker("Placement", selection: $model.placement) {
                ForEach(FeasibilityReport.Placement.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Button("Play cue pulse") { model.pulse() }
            HStack {
                Button("Felt it") { model.recordHaptic(felt: true) }
                    .buttonStyle(.borderedProminent)
                Spacer()
                Button("Didn't feel it") { model.recordHaptic(felt: false) }
                    .buttonStyle(.bordered)
            }
            Text("\(model.report.hapticTrials.count) trial(s) recorded")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var reportSection: some View {
        Section("Evidence") {
            let latency = model.latency
            LabeledContent("Latency median", value: format(latency.median))
            LabeledContent("Latency p90", value: format(latency.p90))
            let score = model.attribution
            LabeledContent("Labelled", value: "\(score.labelled)")
            LabeledContent("Accuracy when committed", value: percent(score.accuracyWhenCommitted))
            LabeledContent("Coverage", value: percent(score.coverage))
            LabeledContent("Other called Me", value: percent(score.otherAsUserRate))
            TextField("Notes (room, distance, voices)", text: $model.report.notes, axis: .vertical)
            ShareLink(item: model.report.jsonString()) {
                Label("Export report JSON", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func format(_ seconds: Double?) -> String {
        seconds.map { String(format: "%.2f s", $0) } ?? "–"
    }

    private func percent(_ value: Double?) -> String {
        value.map { String(format: "%.0f%%", $0 * 100) } ?? "–"
    }
}

/// The single recording indicator: dot, label, level and elapsed time.
private struct RecordingStrip: View {
    let startedAt: Date?
    let levelDB: Double
    let interrupted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(interrupted ? Color.orange : Color.red)
                .frame(width: 10, height: 10)
            Text(interrupted ? "Interrupted" : "Recording")
                .font(.subheadline.bold())
            GeometryReader { proxy in
                Capsule()
                    .fill(.white.opacity(0.25))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.white)
                            .frame(width: proxy.size.width * normalizedLevel)
                    }
            }
            .frame(height: 6)
            if let startedAt {
                Text(startedAt, style: .timer)
                    .font(.subheadline.monospacedDigit())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.10, green: 0.17, blue: 0.13))
        .accessibilityElement(children: .combine)
    }

    /// Maps -60...0 dBFS onto 0...1.
    private var normalizedLevel: CGFloat {
        CGFloat(min(max((levelDB + 60) / 60, 0), 1))
    }
}

private struct UtteranceRow: View {
    let utterance: Utterance
    let onLabel: (SpeakerLabel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(utterance.text)
            HStack {
                Text(String(format: "%.1f–%.1f s · %.2f s late", utterance.start, utterance.end, utterance.latency))
                if let level = utterance.meanLevelDB {
                    Text(String(format: "%.0f dB", level))
                }
                Spacer()
                Text("guess: \(utterance.predicted.rawValue)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Picker("Speaker", selection: Binding(
                get: { utterance.groundTruth ?? .unknown },
                set: { onLabel($0) }
            )) {
                Text("Me").tag(SpeakerLabel.user)
                Text("Other").tag(SpeakerLabel.other)
                Text("?").tag(SpeakerLabel.unknown)
            }
            .pickerStyle(.segmented)
        }
    }
}
