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
}

struct Pass1RootView: View {
    @Bindable var model: Pass1Model

    var body: some View {
        ZStack {
            Palette.liveBackground.ignoresSafeArea()
            switch model.route {
            case .onboarding: OnboardingView(model: model)
            case .setup: SessionSetupView(model: model)
            case .live: LiveView(model: model)
            }
        }
        .foregroundStyle(Palette.liveText)
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
        VStack(spacing: 0) {
            // The single recording indicator (DESIGN.md).
            if model.lab.isRecording {
                RecordingStrip(startedAt: model.lab.startedAt, levelDB: model.lab.levelDB, interrupted: model.lab.state == .interrupted)
            }
            ScrollView {
                VStack(spacing: 20) {
                    MeterView(needle: model.screen.needle, label: centerLabel, detail: centerDetail)
                        .frame(width: 280, height: 280)
                        .onTapGesture { model.screen.openCue() }
                        .accessibilityAddTraits(.isButton)
                    if case .cueOpen(let cue) = model.screen.phase {
                        CueCard(cue: cue, model: model)
                    } else if case .cueWaiting = model.screen.phase {
                        Button(model.copy(.cueAvailable)) { model.screen.openCue() }
                            .foregroundStyle(Palette.amber)
                    }
                    notMeasured
                    if !model.setup.intentionText.isEmpty {
                        Text(model.setup.intentionText)
                            .font(.footnote)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.liveSurface, in: RoundedRectangle(cornerRadius: 14))
                    }
                    if model.screen.phase == .stopped {
                        Text(model.copy(.sessionStopped)).font(.headline)
                        PrimaryButton(title: model.copy(.setupTitle)) { model.backToSetup() }
                    } else {
                        PrimaryButton(title: model.copy(.endSession)) { Task { await model.endSession() } }
                    }
                }
                .padding(16)
            }
        }
    }

    private var centerLabel: String {
        model.screen.phase == .stopped ? model.copy(.sessionStopped) : model.copy(.listening)
    }

    private var centerDetail: String {
        model.screen.phase == .stopped ? "" : model.copy(.listeningDetail)
    }

    private var notMeasured: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.copy(.notMeasuredTitle)).font(.caption.weight(.semibold))
            ForEach([CopyKey.categorySarcasm, .categoryManner, .categoryVoiceTone], id: \.self) { key in
                HStack {
                    Text(model.copy(key))
                    Spacer()
                    Text(model.copy(.notMeasured))
                }
                .font(.caption)
            }
        }
        .foregroundStyle(Palette.liveMuted)
        .padding(12)
        .background(Palette.liveSurface, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct CueCard: View {
    let cue: Cue
    let model: Pass1Model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(.cueYourWording, "“\(cue.phrase)”")
            row(.cuePossibleReading, cue.possibleReading)
            row(.cueWhyHere, cue.whyHere)
            row(.cueTryNext, cue.tryNext)
            HStack {
                Button(model.copy(.cueDismiss)) { model.screen.dismissCue() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(model.copy(.cueMarkInaccurate)) { model.markInaccurate() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(Palette.liveSurface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func row(_ title: CopyKey, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.copy(title)).font(.caption.weight(.semibold)).foregroundStyle(Palette.liveMuted)
            Text(text)
        }
    }
}

/// The round meter: ring segments all round, fine ticks only on the reachable upper arc.
struct MeterView: View {
    let needle: Double
    let label: String
    let detail: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = size / 2 - 8
            ZStack {
                Circle().fill(Palette.liveSurface)
                ForEach(MeterGeometry.segmentAngles(), id: \.self) { start in
                    let span = 360 / Double(MeterGeometry.segmentCount)
                    Path { path in
                        path.addArc(center: center, radius: radius, startAngle: .degrees(start + 1), endAngle: .degrees(start + span - 1), clockwise: false)
                    }
                    .stroke(MeterGeometry.isAmber(start + span / 2) ? Palette.amber.opacity(0.8) : Palette.liveMuted.opacity(0.35), lineWidth: 6)
                }
                ForEach(MeterGeometry.tickAngles(), id: \.self) { angle in
                    Path { path in
                        path.move(to: point(center, radius - 12, angle))
                        path.addLine(to: point(center, radius - 22, angle))
                    }
                    .stroke(Palette.liveMuted, lineWidth: 1.5)
                }
                Path { path in
                    path.move(to: center)
                    path.addLine(to: point(center, radius - 28, MeterGeometry.needleAngle(needle)))
                }
                .stroke(needle > 0.5 ? Palette.amber : Palette.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: needle)
                VStack(spacing: 4) {
                    Text(label).font(.title3.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(Palette.liveMuted).multilineTextAlignment(.center)
                }
                .frame(width: size * 0.55)
                .offset(y: size * 0.12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private func point(_ center: CGPoint, _ r: CGFloat, _ degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + r * cos(radians), y: center.y + r * sin(radians))
    }
}
#endif
