#if os(iOS)
import AutoniteCore
import SwiftUI

// MARK: Practice

/// Practice alone before a real conversation (research 2026-11-16 §5.5). Each situation shows the
/// settings it uses before it starts, so choosing one is the confirmation.
struct PracticeSheet: View {
    @Bindable var model: Pass1Model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(model.copy(.practiceBody))
                        .foregroundStyle(Palette.liveMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(PracticeScenario.allCases, id: \.self) { scenario in
                        Button {
                            model.showsPractice = false
                            Task { await model.startSession(practice: scenario) }
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(model.copy(scenario.titleKey)).font(.headline)
                                    Text(model.copy(scenario.promptKey))
                                        .font(.subheadline)
                                        .foregroundStyle(Palette.liveMuted)
                                    Text("\(model.copy(registerKey(scenario.settings.register))) · \(model.copy(wordKey(scenario.settings.wordChoice)))")
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(Palette.primary)
                                }
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Image(systemName: "mic.circle.fill").font(.title).foregroundStyle(Palette.primary)
                            }
                            .padding(16)
                            .background(Palette.liveSurface, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .disabled(!model.hasProfile)
                    }
                }
                .padding(16)
            }
            .background(Palette.liveBackground)
            .navigationTitle(model.copy(.practiceTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.copy(.close)) { model.showsPractice = false }
                }
            }
        }
        .foregroundStyle(Palette.liveText)
        .preferredColorScheme(.dark)
    }
}

// MARK: Settings

/// App language, Whisper, the user's word list, and everything kept on this iPhone with a way to
/// delete each (research 2026-11-16 §5.6 and §5.10). The Lab stays reachable for evidence runs.
struct SettingsView: View {
    @Bindable var model: Pass1Model
    @State private var newWord = ""
    @State private var data = Pass1Model.DataSummary()
    @State private var confirmVoiceDelete = false
    @State private var showsLab = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Pass1Model.AppLanguage.allCases, id: \.self) { option in
                        CheckRow(title: appLanguageTitle(option), checked: model.appLanguage == option) { model.setAppLanguage(option) }
                    }
                } header: {
                    Text(model.copy(.appLanguage))
                } footer: {
                    Text(model.copy(.appLanguageNote))
                }
                .listRowBackground(Palette.liveSurface)

                Section {
                    Toggle(model.copy(.whisperUse), isOn: Binding(get: { model.whisperEnabled }, set: { model.setWhisperEnabled($0) }))
                        .tint(Palette.primary)
                        .disabled(model.whisperBusy)
                    if model.whisperEnabled {
                        ForEach(WhisperReader.Model.allCases, id: \.self) { option in
                            CheckRow(title: model.copy(option == .standard ? .whisperStandard : .whisperAccurate),
                                     checked: model.whisperModel == option) { model.setWhisperModel(option) }
                                .disabled(model.whisperBusy)
                        }
                        WhisperStatusRow(model: model)
                    }
                    if data.whisperBytes != nil, !model.whisperBusy {
                        Button(model.copy(.whisperDelete), role: .destructive) {
                            Task {
                                await model.deleteWhisperModels()
                                refresh()
                            }
                        }
                    }
                } header: {
                    Text(model.copy(.whisperTitle))
                } footer: {
                    Text("\(model.copy(.whisperBody))\n\(model.copy(.whisperNetwork))")
                }
                .listRowBackground(Palette.liveSurface)

                Section {
                    HStack {
                        TextField(model.copy(.myWordsPlaceholder), text: $newWord)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit(addWord)
                        Button(model.copy(.myWordsAdd), action: addWord)
                            .buttonStyle(.borderless)
                            .foregroundStyle(Palette.primary)
                            .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    WordListRow(model: model, title: model.copy(.myWordsAdded), words: model.words.added)
                    WordListRow(model: model, title: model.copy(.myWordsMuted), words: model.words.muted)
                } header: {
                    Text(model.copy(.myWordsTitle))
                } footer: {
                    Text(model.copy(.myWordsBody))
                }
                .listRowBackground(Palette.liveSurface)

                Section {
                    DataRow(model: model, title: model.copy(.dataVoice),
                            value: model.hasProfile ? "\(bytes(data.voiceBytes)) · \(model.copy(.dataVoiceDetail))" : bytes(data.voiceBytes),
                            canDelete: model.hasProfile && !model.lab.isRecording) { confirmVoiceDelete = true }
                    DataRow(model: model, title: model.copy(.dataMarks), value: count(data.marks), canDelete: data.marks > 0) {
                        model.deleteMarks()
                        refresh()
                    }
                    DataRow(model: model, title: model.copy(.dataWords), value: count(data.words), canDelete: data.words > 0) {
                        model.deleteWords()
                        refresh()
                    }
                    DataRow(model: model, title: model.copy(.dataWhisper), value: bytes(data.whisperBytes),
                            canDelete: data.whisperBytes != nil && !model.whisperBusy) {
                        Task {
                            await model.deleteWhisperModels()
                            refresh()
                        }
                    }
                    Text(model.copy(.dataRecap))
                        .font(.footnote)
                        .foregroundStyle(Palette.liveMuted)
                } header: {
                    Text(model.copy(.myDataTitle))
                } footer: {
                    Text(model.copy(.myDataBody))
                }
                .listRowBackground(Palette.liveSurface)

                Section {
                    Button(model.copy(.labOpen)) { showsLab = true }
                        .foregroundStyle(Palette.liveText)
                }
                .listRowBackground(Palette.liveSurface)
            }
            .scrollContentBackground(.hidden)
            .background(Palette.liveBackground)
            .navigationTitle(model.copy(.settingsTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.copy(.close)) { model.showsSettings = false }
                }
            }
            .confirmationDialog(model.copy(.deleteVoice), isPresented: $confirmVoiceDelete, titleVisibility: .visible) {
                Button(model.copy(.dataDelete), role: .destructive) {
                    model.showsSettings = false
                    model.deleteVoice()
                }
            }
            .sheet(isPresented: $showsLab) {
                NavigationStack {
                    FeasibilityView(model: model.lab)
                        .navigationTitle(model.copy(.labTitle))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { Button(model.copy(.close)) { showsLab = false } }
                }
            }
            .onAppear(perform: refresh)
            .onChange(of: model.lab.whisperStatus) { _, status in
                if case .downloading = status { return }
                refresh()
            }
            .onChange(of: model.words) { refresh() }
        }
        .foregroundStyle(Palette.liveText)
        .tint(Palette.primary)
        .preferredColorScheme(.dark)
    }

    private func appLanguageTitle(_ option: Pass1Model.AppLanguage) -> String {
        switch option {
        case .followSpeech: model.copy(.appLanguageFollow)
        case .korean: "한국어"
        case .english: "English"
        }
    }

    private func addWord() {
        model.addWord(newWord)
        newWord = ""
    }

    private func refresh() { data = model.dataSummary() }

    private func bytes(_ value: Int64?) -> String {
        value.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? model.copy(.dataNone)
    }

    private func count(_ value: Int) -> String { value > 0 ? "\(value)" : model.copy(.dataNone) }
}

/// A choice row with a checkmark; its title wraps rather than being cut off.
private struct CheckRow: View {
    let title: String
    let checked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if checked { Image(systemName: "checkmark").foregroundStyle(Palette.primary) }
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(Palette.liveText)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

private struct WhisperStatusRow: View {
    let model: Pass1Model

    var body: some View {
        switch model.lab.whisperStatus {
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 6) {
                Text("\(model.copy(.whisperDownloading)) · \(Int((fraction * 100).rounded()))%")
                ProgressView(value: fraction).tint(Palette.primary)
            }
        case .preparing:
            HStack(spacing: 10) {
                ProgressView()
                Text(model.copy(.whisperPreparing)).fixedSize(horizontal: false, vertical: true)
            }
        case .failed(let error):
            VStack(alignment: .leading, spacing: 6) {
                Text(model.copy(.whisperFailed)).foregroundStyle(Palette.amber)
                Text(error).font(.footnote).foregroundStyle(Palette.liveMuted)
                downloadButton
            }
        default:
            if model.whisperReady {
                Label(model.copy(.whisperReady), systemImage: "checkmark.circle.fill").foregroundStyle(Palette.primary)
            } else {
                downloadButton
            }
        }
    }

    /// The only way a model download starts; the size is in the option label above it.
    private var downloadButton: some View {
        Button {
            model.downloadWhisper()
        } label: {
            Label(model.copy(.whisperDownload), systemImage: "arrow.down.circle")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Palette.primary)
    }
}

private struct WordListRow: View {
    let model: Pass1Model
    let title: String
    let words: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(Palette.liveMuted)
            if words.isEmpty {
                Text(model.copy(.myWordsNone)).foregroundStyle(Palette.liveMuted)
            }
            ForEach(words, id: \.self) { word in
                HStack {
                    Text(word)
                    Spacer()
                    Button {
                        model.resetWord(word)
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3).frame(width: 44, height: 36)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Palette.liveMuted)
                    .accessibilityLabel("\(model.copy(.dataDelete)) \(word)")
                }
            }
        }
    }
}

private struct DataRow: View {
    let model: Pass1Model
    let title: String
    let value: String
    let canDelete: Bool
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fixedSize(horizontal: false, vertical: true)
                Text(value).font(.footnote.monospacedDigit()).foregroundStyle(Palette.liveMuted)
            }
            Spacer(minLength: 8)
            if canDelete {
                Button(model.copy(.dataDelete), role: .destructive, action: delete)
                    .buttonStyle(.borderless)
            }
        }
    }
}
#endif
