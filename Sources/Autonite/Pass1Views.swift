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
}

struct Pass1RootView: View {
    @Bindable var model: Pass1Model
    @State private var showingLab = false

    var body: some View {
        ZStack {
            Palette.liveBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                AppHeader(subtitle: model.copy(.appSubtitle)) { showingLab = true }
                switch model.route {
                case .onboarding: OnboardingView(model: model)
                case .setup: SessionSetupView(model: model)
                case .live: LiveView(model: model)
                }
            }
        }
        .foregroundStyle(Palette.liveText)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingLab) {
            NavigationStack {
                FeasibilityView(model: model.lab)
                    .navigationTitle(model.copy(.labTitle))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button(model.copy(.close)) { showingLab = false } }
            }
        }
    }
}

/// "Autunite" title, subtitle and the settings gear, as in the UI reference.
private struct AppHeader: View {
    let subtitle: String
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Autunite").font(.system(size: 30, weight: .semibold))
                Text(subtitle).font(.subheadline).foregroundStyle(Palette.liveMuted)
            }
            Spacer()
            Button(action: openSettings) {
                Image(systemName: "gearshape").font(.title2)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

private struct PrimaryButton: View {
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

// MARK: Onboarding

struct OnboardingView: View {
    @Bindable var model: Pass1Model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker("", selection: $model.language) {
                    Text("한국어").tag(SpeechLanguage.korean)
                    Text("English").tag(SpeechLanguage.english)
                }
                .pickerStyle(.segmented)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(model.copy(.setupTitle)).font(.largeTitle.weight(.semibold))
                Picker("", selection: $model.language) {
                    Text("한국어").tag(SpeechLanguage.korean)
                    Text("English").tag(SpeechLanguage.english)
                }
                .pickerStyle(.segmented)

                Text(model.copy(.intentionPrompt)).font(.headline)
                TextField(model.copy(.intentionPlaceholder), text: $model.setup.intentionText, axis: .vertical)
                    .padding(12)
                    .background(Palette.liveSurface, in: RoundedRectangle(cornerRadius: 14))

                Text(model.copy(.presetsTitle)).font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(SettingsPreset.allCases, id: \.self) { preset in
                            Button(model.copy(presetKey(preset))) { model.setup.propose(preset) }
                                .buttonStyle(.bordered)
                        }
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

                Text(model.copy(.registerTitle)).font(.headline)
                Picker("", selection: Binding(get: { model.setup.confirmed.register }, set: { model.setup.confirm(register: $0) })) {
                    ForEach(RegisterSetting.allCases, id: \.self) { Text(model.copy(registerKey($0))).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(model.copy(.wordChoiceTitle)).font(.headline)
                Picker("", selection: Binding(get: { model.setup.confirmed.wordChoice }, set: { model.setup.confirm(wordChoice: $0) })) {
                    ForEach(WordChoiceSetting.allCases, id: \.self) { Text(model.copy(wordKey($0))).tag($0) }
                }
                .pickerStyle(.segmented)

                PrimaryButton(title: model.copy(.startSession), enabled: model.hasProfile) {
                    Task { await model.startSession() }
                }
                Button(model.copy(.deleteVoice), role: .destructive) { model.deleteVoice() }
                    .frame(maxWidth: .infinity)
                if let message = model.message {
                    Text(message).font(.footnote).foregroundStyle(Palette.liveMuted)
                }
            }
            .padding(16)
        }
    }

    private func presetKey(_ preset: SettingsPreset) -> CopyKey {
        switch preset {
        case .senior: .presetSenior
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
                MeterView(needle: model.screen.needle, label: centerLabel, detail: centerDetail, cue: isCue)
                    .frame(width: 300, height: 300)
                    .contentShape(Circle())
                    .onTapGesture { model.screen.openCue() }
                    .accessibilityAddTraits(.isButton)
                if model.voiceCheckOff {
                    Text(model.copy(.voiceCheckOff))
                        .font(.footnote)
                        .foregroundStyle(Palette.amber)
                        .multilineTextAlignment(.center)
                }
                LastHeardRow(model: model)
                Spacer(minLength: 0)
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

/// What the app heard last and what it did with it, so a missing cue can be explained.
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
            Image(systemName: "scope").font(.title2).foregroundStyle(Palette.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.copy(.intentionCaption)).font(.subheadline).foregroundStyle(Palette.liveMuted)
                Text(intention).font(.headline).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Palette.liveMuted)
        }
        .padding(16)
        .background(Palette.liveSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.liveMuted.opacity(0.15)))
    }

    private var intention: String {
        let text = model.setup.intentionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        let settings = model.setup.confirmed
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
                    caption(.cueYourWording)
                    Text("“\(cue.phrase)”").font(.title3.weight(.medium))
                }
                Spacer()
                Menu {
                    Button(model.copy(.cueMarkInaccurate)) { model.markInaccurate() }
                    Button(model.copy(.cueDismiss)) { model.screen.dismissCue() }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 34, height: 34)
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
            row("arrow.right", .cueTryNext, "“\(cue.tryNext)”")
            HStack {
                Button(model.copy(.cueDismiss)) { model.screen.dismissCue() }
                Spacer()
                Button(model.copy(.cueMarkInaccurate)) { model.markInaccurate() }
                    .foregroundStyle(Palette.amber)
            }
            .font(.subheadline.weight(.medium))
            .padding(.top, 14)
        }
        .padding(22)
        .background(Palette.liveSurface, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28).stroke(Palette.liveMuted.opacity(0.15)))
        .ignoresSafeArea(edges: .bottom)
    }

    private func caption(_ key: CopyKey) -> some View {
        Text(model.copy(key).uppercased()).font(.caption).tracking(1).foregroundStyle(Palette.liveMuted)
    }

    private func row(_ icon: String, _ title: CopyKey, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).frame(width: 26)
            VStack(alignment: .leading, spacing: 6) {
                caption(title)
                Text(text).font(.body)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
    }
}

/// The round meter: thick ring segments all round, fine ticks only on the reachable upper arc,
/// a slim needle that rests straight up and swings to amber on a cue.
struct MeterView: View {
    let needle: Double
    let label: String
    let detail: String
    var cue = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let ring = size * 0.085
            let radius = size / 2 - size * 0.09
            let span = 360 / Double(MeterGeometry.segmentCount)
            let active = MeterGeometry.segment(containing: MeterGeometry.needleAngle(needle))
            ZStack {
                ForEach(MeterGeometry.segmentAngles(), id: \.self) { start in
                    Path { path in
                        path.addArc(center: center, radius: radius, startAngle: .degrees(start + 3), endAngle: .degrees(start + span - 3), clockwise: false)
                    }
                    .stroke(color(for: start, active: active), style: StrokeStyle(lineWidth: ring, lineCap: .round))
                }
                ForEach(MeterGeometry.tickAngles(), id: \.self) { angle in
                    let major = Int((angle - MeterGeometry.tickRange.lowerBound).rounded()) % 35 == 0
                    Path { path in
                        path.move(to: point(center, radius + ring / 2 + 6, angle))
                        path.addLine(to: point(center, radius + ring / 2 + (major ? 16 : 11), angle))
                    }
                    .stroke(MeterGeometry.isAmber(angle) && cue ? Palette.amber : Palette.liveMuted.opacity(major ? 0.9 : 0.55), lineWidth: major ? 2 : 1)
                }
                Path { path in
                    path.move(to: center)
                    path.addLine(to: point(center, radius + ring / 2, MeterGeometry.needleAngle(needle)))
                }
                .stroke(Palette.liveText, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: needle)
                Circle()
                    .fill(Palette.liveText)
                    .frame(width: 10, height: 10)
                    .position(center)
                VStack(spacing: 8) {
                    Text(label).font(.title2.weight(.semibold))
                    Text(detail).font(.subheadline).foregroundStyle(Palette.liveMuted).multilineTextAlignment(.center)
                }
                .frame(width: size * 0.6)
                .position(x: center.x, y: center.y + size * 0.2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private func color(for start: Double, active: Double?) -> Color {
        guard start == active else { return Palette.segment.opacity(0.75) }
        return needle > 0.5 ? Palette.amber : Palette.primary
    }

    private func point(_ center: CGPoint, _ r: CGFloat, _ degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + r * cos(radians), y: center.y + r * sin(radians))
    }
}
#endif
