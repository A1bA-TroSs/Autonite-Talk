#if os(iOS)
import AutoniteCore
import SwiftUI

/// DESIGN.md colour roles. Proposed starting values; views use these, not raw colours.
enum Palette {
    static let primary = Color(red: 0xC7 / 255, green: 0xDF / 255, blue: 0x70 / 255)
    static let onPrimary = Color(red: 0x1A / 255, green: 0x2B / 255, blue: 0x22 / 255)
    static let liveBackground = Color(red: 0x1A / 255, green: 0x2B / 255, blue: 0x22 / 255)
    static let liveSurface = Color(red: 0x24 / 255, green: 0x38 / 255, blue: 0x2C / 255)
    static let liveText = Color(red: 0xF3 / 255, green: 0xF1 / 255, blue: 0xE7 / 255)
    static let liveMuted = Color(red: 0xCC / 255, green: 0xD2 / 255, blue: 0xC5 / 255)
    static let amber = Color(red: 0.95, green: 0.69, blue: 0.25)
    static let recordingDot = Color(red: 0.55, green: 0.85, blue: 0.30)
    static let stop = Color(red: 0.72, green: 0.25, blue: 0.27)
    static let segment = Color(red: 0x4A / 255, green: 0x62 / 255, blue: 0x50 / 255)
    // The recap's warm-ivory reading surface (DESIGN.md recap-page and recap-card).
    static let reportBackground = Color(red: 0xF7 / 255, green: 0xF5 / 255, blue: 0xEE / 255)
    static let reportSurface = Color.white
    static let reportText = Color(red: 0x1D / 255, green: 0x29 / 255, blue: 0x20 / 255)
    static let reportMuted = Color(red: 0x4E / 255, green: 0x5A / 255, blue: 0x51 / 255)
    /// The thin orbit line and dot in the recap header; report-only artwork.
    static let orbit = Color(red: 0xB8 / 255, green: 0x96 / 255, blue: 0x3E / 255)
}

struct Pass1RootView: View {
    @Bindable var model: Pass1Model

    var body: some View {
        let report = model.route == .recap
        ZStack {
            (report ? Palette.reportBackground : Palette.liveBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                AppHeader(subtitle: model.copy(.appSubtitle), settingsLabel: model.copy(.settingsTitle), report: report) {
                    model.showsSettings = true
                }
                switch model.route {
                case .onboarding: OnboardingView(model: model)
                case .setup: SessionSetupView(model: model)
                case .live: LiveView(model: model)
                case .recap: RecapView(model: model)
                }
            }
        }
        .foregroundStyle(report ? Palette.reportText : Palette.liveText)
        .preferredColorScheme(report ? .light : .dark)
        .sheet(isPresented: $model.showsSettings) {
            SettingsView(model: model)
        }
        // A word marked wrong more than once (MarkReview): offered for muting, never muted unasked.
        .alert(model.copy(.muteOfferTitle), isPresented: Binding(get: { model.muteOffer != nil }, set: { if !$0 { model.muteOffer = nil } }),
               presenting: model.muteOffer) { word in
            Button("\(model.copy(.recapMute)): “\(word)”") { model.acceptMuteOffer(word) }
            Button(model.copy(.muteOfferKeep), role: .cancel) { model.keepFlagging(word) }
        } message: { word in
            Text("“\(word)”\n\(model.copy(.muteOfferBody))")
        }
    }
}

/// "Autunite" title, subtitle and the settings gear, as in the UI reference.
private struct AppHeader: View {
    let subtitle: String
    let settingsLabel: String
    var report = false
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Autunite").font(.system(size: 30, weight: .semibold))
                Text(subtitle).font(.subheadline).foregroundStyle(report ? Palette.reportMuted : Palette.liveMuted)
            }
            Spacer()
            Button(action: openSettings) {
                Image(systemName: "gearshape").font(.title2).frame(width: 44, height: 44)
            }
            .accessibilityLabel(settingsLabel)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

struct PrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Palette.primary, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(Palette.onPrimary)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

/// Equal-width options whose labels wrap onto a second line instead of being cut off, since
/// Korean labels run longer than a segmented control allows (DESIGN.md: flexible cards for Korean).
struct OptionPicker<Value: Hashable>: View {
    let options: [Value]
    let selection: Value
    let label: (Value) -> String
    let select: (Value) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button { select(option) } label: {
                    Text(label(option))
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
                        .background(selected ? Palette.primary : Palette.liveSurface, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(selected ? Palette.onPrimary : Palette.liveText)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Lays its children out in rows and wraps to the next row instead of clipping or scrolling.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct SpeechLanguagePicker: View {
    @Bindable var model: Pass1Model

    var body: some View {
        OptionPicker(options: [SpeechLanguage.korean, .english], selection: model.language, label: { $0.displayName }) { model.language = $0 }
    }
}

// MARK: Onboarding

struct OnboardingView: View {
    @Bindable var model: Pass1Model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SpeechLanguagePicker(model: model)
                step
                if let message = model.message {
                    Text(message).foregroundStyle(Palette.liveMuted)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder private var step: some View {
        let flow = model.onboarding.enrollment
        switch flow.step {
        case .consent, .declined:
            Text(model.copy(.welcomeTitle)).font(.largeTitle.weight(.semibold))
            Text(model.copy(.welcomeBody))
            Text(model.copy(.consentTitle)).font(.title2.weight(.semibold))
            Text(model.copy(.consentBody))
            Text(model.copy(.consentStorage)).foregroundStyle(Palette.liveMuted)
            PrimaryButton(title: model.copy(.consentAgree)) { model.answerConsent(true) }
            Button(model.copy(.consentDecline)) { model.answerConsent(false) }
                .frame(maxWidth: .infinity)
        case .placement:
            Text(model.copy(.placementTitle)).font(.title2.weight(.semibold))
            Text(model.copy(.placementBody))
            PrimaryButton(title: model.copy(.placementDone)) { model.confirmPlacement() }
        case .sentence(let i):
            reading(EnrollmentScript.sentences(for: model.language)[i], progress: "\(i + 1) / \(flow.sentenceCount)")
        case .extraSentence(let i):
            reading(EnrollmentScript.sentences(for: model.language)[i], progress: "+\(i + 1)")
        case .freeSpeech:
            Text(model.copy(.freeSpeechTitle)).font(.title3.weight(.semibold))
            recordButton(model.copy(.freeSpeechRecord))
        case .phraseCheck:
            Text(model.copy(.checkTitle)).font(.title2.weight(.semibold))
            Text(model.copy(.checkBody))
            Text("“\(model.checkPhrase)”").font(.title3)
            recordButton(model.copy(.sentenceRecord))
        case .baseline:
            Text(model.copy(.baselineTitle)).font(.title2.weight(.semibold))
            ProgressView()
        case .done:
            Text(model.copy(.enrolmentDone))
        }
    }

    private func reading(_ sentence: String, progress: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.copy(.sentenceTitle)).foregroundStyle(Palette.liveMuted)
            Text(progress).font(.caption.monospacedDigit()).foregroundStyle(Palette.liveMuted)
            Text(sentence).font(.title2)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.liveSurface, in: RoundedRectangle(cornerRadius: 16))
            recordButton(model.copy(.sentenceRecord))
        }
    }

    private func recordButton(_ title: String) -> some View {
        PrimaryButton(title: model.isRecordingClip ? model.copy(.sentenceRecording) : title, enabled: !model.isRecordingClip) {
            Task { await model.recordStep() }
        }
    }
}

// MARK: Session setup

struct SessionSetupView: View {
    @Bindable var model: Pass1Model
    /// The speech level and word choice pickers fold into one row, so the start button and
    /// practice stay in view; the row shows what is set.
    @State private var showsReadingRules = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(model.copy(.setupTitle)).font(.largeTitle.weight(.semibold))
                Text(model.copy(.speechLanguageTitle)).font(.headline)
                SpeechLanguagePicker(model: model)

                Text(model.copy(.intentionPrompt)).font(.headline)
                TextField(model.copy(.intentionPlaceholder), text: $model.setup.intentionText, axis: .vertical)
                    .padding(12)
                    .background(Palette.liveSurface, in: RoundedRectangle(cornerRadius: 14))

                Text(model.copy(.presetsTitle)).font(.headline)
                // Wrapping rows, so every preset is in view and none is cut off at the edge.
                FlowLayout(spacing: 8) {
                    ForEach(SettingsPreset.allCases, id: \.self) { preset in
                        Button(model.copy(presetKey(preset))) { model.setup.propose(preset) }
                            .buttonStyle(.bordered)
                    }
                }
                if let proposed = model.setup.proposed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.copy(.proposalPending)).font(.footnote)
                        Text("\(model.copy(registerKey(proposed.register))) · \(model.copy(wordKey(proposed.wordChoice)))")
                        HStack {
                            Button(model.copy(.proposalConfirm)) { model.setup.confirmProposal() }
                                .buttonStyle(.borderedProminent)
                            Button(model.copy(.proposalDiscard)) { model.setup.discardProposal() }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(12)
                    .background(Palette.liveSurface, in: RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    withAnimation(.snappy) { showsReadingRules.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.copy(.readingRulesTitle)).font(.headline)
                            Text("\(model.copy(registerKey(model.setup.confirmed.register))) · \(model.copy(wordKey(model.setup.confirmed.wordChoice)))")
                                .font(.subheadline)
                                .foregroundStyle(Palette.liveMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(showsReadingRules ? 180 : 0))
                            .foregroundStyle(Palette.liveMuted)
                    }
                    .padding(16)
                    .frame(minHeight: 44)
                    .background(Palette.liveSurface, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                if showsReadingRules {
                    Text(model.copy(.registerTitle)).font(.subheadline.weight(.semibold))
                    OptionPicker(options: RegisterSetting.allCases, selection: model.setup.confirmed.register,
                                 label: { model.copy(registerKey($0)) }) { model.setup.confirm(register: $0) }
                    Text(model.copy(.wordChoiceTitle)).font(.subheadline.weight(.semibold))
                    OptionPicker(options: WordChoiceSetting.allCases, selection: model.setup.confirmed.wordChoice,
                                 label: { model.copy(wordKey($0)) }) { model.setup.confirm(wordChoice: $0) }
                }

                PrimaryButton(title: model.copy(.startSession), enabled: model.hasProfile) {
                    Task { await model.startSession() }
                }
                Button { model.showsPractice = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "figure.wave").font(.title2).foregroundStyle(Palette.primary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.copy(.practiceTitle)).font(.headline)
                            Text(model.copy(.practiceBody)).font(.subheadline).foregroundStyle(Palette.liveMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(Palette.liveMuted)
                    }
                    .padding(16)
                    .background(Palette.liveSurface, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(!model.hasProfile)
                Button(model.copy(.deleteVoice), role: .destructive) { model.deleteVoice() }
                    .frame(maxWidth: .infinity)
                if let message = model.message {
                    Text(message).font(.footnote).foregroundStyle(Palette.liveMuted)
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $model.showsPractice) {
            PracticeSheet(model: model)
        }
    }

    private func presetKey(_ preset: SettingsPreset) -> CopyKey {
        switch preset {
        case .senior: .presetSenior
        case .junior: .presetJunior
        case .stranger: .presetStranger
        case .colleague: .presetColleague
        case .closeFriend: .presetCloseFriend
        case .firmNo: .presetFirmNo
        }
    }
}

func registerKey(_ setting: RegisterSetting) -> CopyKey {
    switch setting {
    case .politeExpected: .registerPolite
    case .casualFine: .registerCasualFine
    case .either: .registerEither
    }
}

func wordKey(_ setting: WordChoiceSetting) -> CopyKey {
    setting == .gentle ? .wordChoiceGentle : .wordChoiceBlunt
}

// MARK: Live

struct LiveView: View {
    @Bindable var model: Pass1Model

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 16) {
                // The single recording indicator (DESIGN.md).
                LiveRecordingStrip(model: model)
                MeterView(needle: model.screen.needle, label: centerLabel, detail: centerDetail, cue: isCue,
                          level: model.showsRecording ? min(max((model.lab.levelDB + 55) / 35, 0), 1) : 0)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 380, maxHeight: .infinity)
                    .layoutPriority(1)
                    .contentShape(Circle())
                    .onTapGesture { model.screen.openCue() }
                    .accessibilityAddTraits(.isButton)
                if model.voiceCheckOff {
                    Text(model.copy(.voiceCheckOff))
                        .font(.footnote)
                        .foregroundStyle(Palette.amber)
                        .multilineTextAlignment(.center)
                }
                if model.whisperAppleOnly {
                    Text(model.copy(.whisperAppleOnly))
                        .font(.footnote)
                        .foregroundStyle(Palette.liveMuted)
                        .multilineTextAlignment(.center)
                }
                LiveNowRow(model: model)
                LastHeardRow(model: model)
                IntentionRow(model: model)
                if model.screen.phase == .stopped {
                    PrimaryButton(title: model.copy(.setupTitle)) { model.backToSetup() }
                } else {
                    EndSessionButton(title: model.copy(.endSession)) { Task { await model.endSession() } }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            if case .cueOpen(let cue) = model.screen.phase {
                CueCard(cue: cue, model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: model.screen.phase)
    }

    private var isCue: Bool {
        switch model.screen.phase {
        case .cueWaiting, .cueOpen: true
        default: false
        }
    }

    private var centerLabel: String {
        if model.screen.phase == .stopped { return model.copy(.sessionStopped) }
        return isCue ? model.copy(.checkAlignmentTitle) : model.copy(.listening)
    }

    private var centerDetail: String {
        if model.screen.phase == .stopped { return "" }
        return isCue ? model.copy(.checkAlignmentDetail) : model.copy(.listeningDetail)
    }
}

/// Rounded strip: green dot, "Recording", a compact waveform from recent levels, elapsed time.
private struct LiveRecordingStrip: View {
    let model: Pass1Model
    @State private var levels: [Double] = Array(repeating: 0, count: 28)

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(model.lab.state == .interrupted ? Palette.amber : Palette.recordingDot)
                .frame(width: 12, height: 12)
            Text(model.showsRecording ? model.copy(.recording) : model.copy(.sessionStopped))
                .font(.subheadline)
            HStack(alignment: .center, spacing: 2) {
                ForEach(levels.indices, id: \.self) { i in
                    Capsule()
                        .fill(Palette.primary.opacity(0.35 + 0.65 * levels[i]))
                        .frame(width: 2, height: 4 + 22 * levels[i])
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 28)
            if let startedAt = model.recordingStartedAt, model.showsRecording {
                Text(startedAt, style: .timer)
                    .font(.subheadline.monospacedDigit())
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Palette.liveSurface.opacity(0.8), in: Capsule())
        .overlay(Capsule().stroke(Palette.liveMuted.opacity(0.12)))
        .onChange(of: model.lab.levelDB) { _, db in
            levels.removeFirst()
            levels.append(min(max((db + 60) / 60, 0), 1))
        }
        .accessibilityElement(children: .combine)
    }
}

/// What is being said right now, whether it sounds like the user, and a running verdict.
private struct LiveNowRow: View {
    let model: Pass1Model

    var body: some View {
        if !model.liveText.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(model.copy(.liveNow)).foregroundStyle(Palette.liveMuted)
                    Spacer()
                    chip(model.lab.liveVoiceVerified == true ? model.copy(.voiceYou) : model.copy(.voiceChecking),
                         color: model.lab.liveVoiceVerified == true ? Palette.primary : Palette.liveMuted)
                    chip(model.liveFlagged ? model.copy(.liveFlagged) : model.copy(.liveClean),
                         color: model.liveFlagged ? Palette.amber : Palette.primary)
                }
                .font(.caption)
                Text("“\(String(model.liveText.suffix(60)))”")
                    .font(.subheadline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Palette.liveSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
            .animation(.easeOut(duration: 0.15), value: model.liveFlagged)
        }
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

/// What the app heard last and what it did with it, so a missing cue can be explained. Whisper's
/// words belong on the cue card and in the recap, so the live screen stays calm.
private struct LastHeardRow: View {
    let model: Pass1Model

    var body: some View {
        if let heard = model.lastHeard {
            VStack(spacing: 4) {
                Text("\(model.copy(.lastHeard)): “\(heard)”")
                    .lineLimit(2)
                if let result = model.lastResult {
                    Text(model.copy(result))
                        .foregroundStyle(result == .resultCue ? Palette.amber : Palette.liveMuted)
                }
            }
            .font(.footnote)
            .foregroundStyle(Palette.liveMuted)
            .multilineTextAlignment(.center)
        }
    }
}

private struct IntentionRow: View {
    let model: Pass1Model

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: model.practice == nil ? "scope" : "figure.wave").font(.title2).foregroundStyle(Palette.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.copy(model.practice == nil ? .intentionCaption : .practiceBadge))
                    .font(.subheadline).foregroundStyle(Palette.liveMuted)
                Text(intention).font(.headline)
                    .lineLimit(model.practice == nil ? 1 : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Palette.liveMuted)
        }
        .padding(16)
        .background(Palette.liveSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.liveMuted.opacity(0.15)))
    }

    private var intention: String {
        if let practice = model.practice { return model.copy(practice.promptKey) }
        let text = model.setup.intentionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        let settings = model.sessionSettings
        return "\(model.copy(registerKey(settings.register))) · \(model.copy(wordKey(settings.wordChoice)))"
    }
}

private struct EndSessionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3).frame(width: 18, height: 18)
                Text(title).font(.title3.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(Palette.stop, in: RoundedRectangle(cornerRadius: 18))
            .foregroundStyle(.white)
        }
    }
}

/// The cue sheet: exact wording (amber bar), possible reading, why it matters here, one next
/// sentence, and controls to dismiss or mark the cue wrong (DESIGN.md order).
struct CueCard: View {
    let cue: Cue
    let model: Pass1Model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Capsule().fill(Palette.amber).frame(width: 4)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        caption(.cueYourWording)
                        if cue.count > 1 {
                            // Close hits share one card and one buzz (CuePacer); the count says how many.
                            Text("×\(cue.count)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Palette.amber, in: Capsule())
                                .foregroundStyle(Palette.onPrimary)
                                .accessibilityLabel("\(cue.count)")
                        }
                    }
                    Text("“\(cue.phrase)”").font(.title3.weight(.medium))
                    if let first = cue.firstHeard {
                        Text("\(model.copy(.cueFirstHeard)): “\(first)”")
                            .font(.footnote)
                            .foregroundStyle(Palette.liveMuted)
                    }
                    if cue.checkedAgain {
                        Label(model.copy(.cueCheckedAgain), systemImage: "checkmark.seal")
                            .font(.footnote)
                            .foregroundStyle(Palette.primary)
                    }
                }
                Spacer()
                Menu {
                    Button(model.copy(.cueMarkInaccurate)) { model.markInaccurate() }
                    // The user's word list (research 2026-11-16 §5.6): a word that fits them can be
                    // muted right here.
                    ForEach(model.harshWords(on: cue), id: \.self) { word in
                        Button("\(model.copy(.recapMute)): “\(word)”", systemImage: "speaker.slash") { model.muteFromCard(word) }
                    }
                    Button(model.copy(.cueDismiss)) { model.screen.dismissCue() }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                        .background(Palette.liveMuted.opacity(0.15), in: Circle())
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 16)
            Divider().overlay(Palette.liveMuted.opacity(0.2))
            row("bubble.left", .cuePossibleReading, cue.possibleReading)
            Divider().overlay(Palette.liveMuted.opacity(0.2))
            row("scope", .cueWhyHere, cue.whyHere)
            Divider().overlay(Palette.liveMuted.opacity(0.2))
            row("arrow.right", .cueTryNext, "“\(cue.tryNext)”", standsOut: true)
            if let note = cue.note {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "lightbulb").font(.title3).frame(width: 26).foregroundStyle(Palette.primary)
                    Text(note).font(.subheadline).foregroundStyle(Palette.liveMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 6)
            }
            HStack {
                Button(model.copy(.cueDismiss)) { model.screen.dismissCue() }
                    .frame(minHeight: 44)
                Spacer()
                Button(model.copy(.cueMarkInaccurate)) { model.markInaccurate() }
                    .frame(minHeight: 44)
                    .foregroundStyle(Palette.amber)
            }
            .font(.subheadline.weight(.medium))
            .padding(.top, 8)
        }
        .padding(22)
        .background(Palette.liveSurface, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28).stroke(Palette.liveMuted.opacity(0.15)))
        .ignoresSafeArea(edges: .bottom)
    }

    private func caption(_ key: CopyKey) -> some View {
        Text(model.copy(key).uppercased()).font(.caption).tracking(1).foregroundStyle(Palette.liveMuted)
    }

    /// One field of the card. At a glance the eye goes from the quote to the next sentence, which
    /// stands out; the reading and the reason stay, in DESIGN.md order, but quieter.
    private func row(_ icon: String, _ title: CopyKey, _ text: String, standsOut: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).frame(width: 26)
                .foregroundStyle(standsOut ? Palette.primary : Palette.liveMuted)
            VStack(alignment: .leading, spacing: 6) {
                caption(title)
                Text(text)
                    .font(standsOut ? Font.body.weight(.semibold) : Font.subheadline)
                    .foregroundStyle(standsOut ? Palette.primary : Palette.liveMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, standsOut ? 14 : 10)
    }
}

/// The round meter: thick ring segments all round, fine ticks only on the reachable upper arc,
/// a slim needle that rests straight up and swings to amber on a cue.
struct MeterView: View {
    let needle: Double
    let label: String
    let detail: String
    var cue = false
    /// Voice level 0...1 while listening; the needle twitches with it.
    var level = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let ring = size * 0.1
            let radius = size / 2 - size * 0.1
            let span = 360 / Double(MeterGeometry.segmentCount)
            let angle = needle > 0.5 ? MeterGeometry.needleAngle(needle) : MeterGeometry.listeningAngle(level: level)
            let active = MeterGeometry.segment(containing: angle)
            ZStack {
                ForEach(MeterGeometry.segmentAngles(), id: \.self) { start in
                    let lit = start == active
                    let shape = RingSegment(center: center, inner: radius - ring / 2, outer: radius + ring / 2,
                                            start: start + 2.2, end: start + span - 2.2)
                    shape
                        .fill(LinearGradient(colors: fill(lit: lit), startPoint: .top, endPoint: .bottom))
                        .overlay(shape.stroke(Color.white.opacity(lit ? 0.35 : 0.12), lineWidth: 1))
                        .shadow(color: lit ? glow : .clear, radius: lit ? 10 : 0)
                }
                ForEach(MeterGeometry.tickAngles(), id: \.self) { angle in
                    let major = Int((angle - MeterGeometry.tickRange.lowerBound).rounded()) % 35 == 0
                    Path { path in
                        path.move(to: point(center, radius + ring / 2 + 6, angle))
                        path.addLine(to: point(center, radius + ring / 2 + (major ? 16 : 11), angle))
                    }
                    .stroke(MeterGeometry.isAmber(angle) && cue ? Palette.amber : Palette.liveMuted.opacity(major ? 0.9 : 0.55), lineWidth: major ? 2 : 1)
                }
                // A rotated bar, so the swing animates (a Path would jump).
                Capsule()
                    .fill(Palette.liveText)
                    .frame(width: radius + ring / 2, height: 2.5)
                    .offset(x: (radius + ring / 2) / 2)
                    .rotationEffect(.degrees(angle))
                    .position(center)
                    // Slow and soft while listening; a fast slam to the right on a cue.
                    .animation(reduceMotion ? nil : (needle > 0.5 ? .spring(response: 0.18, dampingFraction: 0.55) : .easeInOut(duration: 0.45)), value: angle)
                Circle()
                    .fill(Palette.liveText)
                    .frame(width: 10, height: 10)
                    .position(center)
                // Kept inside the ring: the ring's inner edge is 0.35 × size from the centre, and at
                // the text's lowest line (about 0.25 × size down) the chord is about 0.49 × size wide.
                VStack(spacing: 6) {
                    Text(label).font(.title2.weight(.semibold))
                    Text(detail).font(.subheadline).foregroundStyle(Palette.liveMuted).multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .minimumScaleFactor(0.8)
                .frame(width: size * 0.46)
                .position(x: center.x, y: center.y + size * 0.15)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var glow: Color { (needle > 0.5 ? Palette.amber : Palette.primary).opacity(0.6) }

    /// Translucent segments with a lighter top edge, as in the reference; the lit one glows.
    private func fill(lit: Bool) -> [Color] {
        guard lit else { return [Palette.segment.opacity(0.95), Palette.segment.opacity(0.55)] }
        let base = needle > 0.5 ? Palette.amber : Palette.primary
        return [base, base.opacity(0.75)]
    }

    private func point(_ center: CGPoint, _ r: CGFloat, _ degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + r * cos(radians), y: center.y + r * sin(radians))
    }
}
#endif

#if os(iOS)
/// One annular sector of the meter ring, with square ends so neighbours leave clean gaps.
struct RingSegment: Shape {
    let center: CGPoint
    let inner: CGFloat
    let outer: CGFloat
    let start: Double
    let end: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: .degrees(end), endAngle: .degrees(start), clockwise: true)
        path.closeSubpath()
        return path
    }
}
#endif
