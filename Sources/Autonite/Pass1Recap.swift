#if os(iOS)
import AutoniteCore
import SwiftUI

// MARK: Recap

/// The end-of-session recap on the warm-ivory report surface (DESIGN.md): the flagged moments in
/// order, each with its quote, what Whisper heard, and the user's mark. No overall grade.
struct RecapView: View {
    @Bindable var model: Pass1Model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 10) {
                        if model.recap.practice != nil {
                            Label(model.copy(.practiceBadge), systemImage: "figure.wave")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Palette.primary.opacity(0.45), in: Capsule())
                        }
                        Text(model.copy(model.recap.practice == nil ? .recapTitle : .recapPracticeTitle))
                            .font(.largeTitle.weight(.semibold))
                        if let practice = model.recap.practice {
                            Text(model.copy(practice.titleKey)).font(.headline)
                        }
                    }
                    Spacer(minLength: 0)
                    RecapHeaderArt().frame(width: 104, height: 76)
                }
                Text(model.copy(.recapGoal))
                    .foregroundStyle(Palette.reportMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if let intention {
                    Text("“\(intention)”").font(.headline).fixedSize(horizontal: false, vertical: true)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    StatTile(title: model.copy(.recapLength), value: clockText(model.recap.duration))
                    StatTile(title: model.copy(.recapCues), value: "\(model.recap.cueCount)")
                    StatTile(title: model.copy(.recapRegister), value: "\(model.recap.cueCount(.register))")
                    StatTile(title: model.copy(.recapWords), value: "\(model.recap.cueCount(.wordChoice))")
                }
                if model.lab.whisperPending > 0 {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("\(model.copy(.recapChecking)) \(model.lab.whisperPending)")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Palette.reportMuted)
                }
                if model.recap.moments.isEmpty {
                    Text(model.copy(.recapEmpty))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                        .background(Palette.reportSurface, in: RoundedRectangle(cornerRadius: 16))
                }
                ForEach(model.recap.moments) { moment in
                    MomentCard(moment: moment, model: model)
                }
                Text(model.copy(.recapKeptNote))
                    .font(.footnote)
                    .foregroundStyle(Palette.reportMuted)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: model.copy(.recapNewSession)) { model.newConversation() }
            }
            .padding(16)
        }
    }

    private var intention: String? {
        if let practice = model.recap.practice { return model.copy(practice.promptKey) }
        let text = model.setup.intentionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

/// Report-only artwork (DESIGN.md): a few translucent yellow-green facets with one thin gold orbit
/// and one dot. It never appears on the live screen.
private struct RecapHeaderArt: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let facets: [[CGPoint]] = [
                [CGPoint(x: w * 0.30, y: h * 0.70), CGPoint(x: w * 0.52, y: h * 0.18), CGPoint(x: w * 0.66, y: h * 0.62)],
                [CGPoint(x: w * 0.52, y: h * 0.18), CGPoint(x: w * 0.80, y: h * 0.36), CGPoint(x: w * 0.66, y: h * 0.62)],
                [CGPoint(x: w * 0.30, y: h * 0.70), CGPoint(x: w * 0.66, y: h * 0.62), CGPoint(x: w * 0.50, y: h * 0.86)],
            ]
            for (i, facet) in facets.enumerated() {
                var path = Path()
                path.addLines(facet)
                path.closeSubpath()
                context.fill(path, with: .color(Palette.primary.opacity([0.55, 0.35, 0.45][i])))
            }
            let orbit = Path(ellipseIn: CGRect(x: w * 0.06, y: h * 0.28, width: w * 0.88, height: h * 0.44))
            context.stroke(orbit.applying(CGAffineTransform(translationX: -w / 2, y: -h / 2)
                .concatenating(CGAffineTransform(rotationAngle: -0.35))
                .concatenating(CGAffineTransform(translationX: w / 2, y: h / 2))),
                           with: .color(Palette.orbit), lineWidth: 1)
            context.fill(Path(ellipseIn: CGRect(x: w * 0.86, y: h * 0.26, width: 6, height: 6)), with: .color(Palette.orbit))
        }
        .accessibilityHidden(true)
    }
}

private struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.weight(.semibold).monospacedDigit())
            Text(title).font(.footnote).foregroundStyle(Palette.reportMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.reportSurface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

/// One flagged moment: when, which category, the words (Whisper's once it re-read them), and the
/// user's accurate/wrong mark. A wrong mark offers to stop flagging its harsh words.
private struct MomentCard: View {
    let moment: SessionRecap.Moment
    let model: Pass1Model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(clockText(moment.start)).font(.caption.monospacedDigit()).foregroundStyle(Palette.reportMuted)
                if moment.cued {
                    ForEach(moment.categories, id: \.self) { category in
                        chip(model.copy(category == .register ? .recapRegister : .recapWords), cued: true)
                    }
                } else {
                    // Only Whisper heard a harsh word here. It may be a mishearing, so it carries no
                    // category, isn't counted, and is shown dimmed (holdout risk, round 1).
                    Text(model.copy(.recapUnconfirmed)).font(.caption.weight(.medium)).foregroundStyle(Palette.reportMuted)
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: 12) {
                Capsule().fill(moment.cued ? Palette.amber : Palette.reportMuted.opacity(0.3)).frame(width: 4)
                Text("“\(moment.quote)”")
                    .font(moment.cued ? Font.title3.weight(.medium) : Font.body)
                    .foregroundStyle(moment.cued ? Palette.reportText : Palette.reportMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
            Group {
                if !moment.cued {
                    Text("\(model.copy(.recapAppleHeard)): “\(moment.apple)”")
                    Text(model.copy(.recapOnlyWhisper))
                } else if moment.heardDifferently {
                    Text("\(model.copy(.cueFirstHeard)): “\(moment.apple)”")
                    Text(model.copy(.recapDisagree))
                } else if moment.whisper != nil {
                    Label(model.copy(.cueCheckedAgain), systemImage: "checkmark.seal")
                }
            }
            .font(.footnote)
            .foregroundStyle(Palette.reportMuted)
            .fixedSize(horizontal: false, vertical: true)
            if moment.cued {
                HStack(spacing: 8) {
                    verdictButton(.accurate, title: model.copy(.recapAccurate), icon: "hand.thumbsup")
                    verdictButton(.inaccurate, title: model.copy(.recapInaccurate), icon: "hand.thumbsdown")
                }
            }
            if moment.verdict == .inaccurate {
                ForEach(moment.harshWords(PersonalWords(added: model.words.added)), id: \.self) { word in
                    if model.isMuted(word) {
                        Label("“\(word)” · \(model.copy(.recapMuted))", systemImage: "speaker.slash")
                            .font(.subheadline)
                            .foregroundStyle(Palette.reportMuted)
                    } else {
                        Button {
                            model.mute(word)
                        } label: {
                            Label("\(model.copy(.recapMute)): “\(word)”", systemImage: "speaker.slash")
                                .font(.subheadline.weight(.medium))
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(moment.cued ? Palette.reportSurface : Palette.reportSurface.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            if !moment.cued {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.reportMuted.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
    }

    private func chip(_ text: String, cued: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((cued ? Palette.amber : Palette.reportMuted).opacity(cued ? 0.3 : 0.12), in: Capsule())
    }

    private func verdictButton(_ verdict: SessionRecap.Verdict, title: String, icon: String) -> some View {
        let selected = moment.verdict == verdict
        return Button {
            model.markMoment(moment, verdict)
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(selected ? (verdict == .accurate ? Palette.primary : Palette.amber) : Palette.reportMuted.opacity(0.1),
                            in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Seconds as m:ss.
func clockText(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", total / 60, total % 60)
}
#endif
