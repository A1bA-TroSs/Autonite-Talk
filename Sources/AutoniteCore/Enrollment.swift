import Foundation

/// Voice enrolment for Pass 1 (SPEC AC1, AC2): biometric consent, then scripted reading and
/// free speech, so the app can tell the user's voice from everyone else's.
public enum EnrollmentScript {
    /// Draft sentences from the approved proposal ("Voice enrollment design"), used unchanged.
    public static let english = [
        "Could you walk me through the numbers again before Thursday?",
        "I hear you, but I'd rather change the plan than rush it.",
        "That's fair. Let's keep the budget where it is for now.",
        "Honestly, I wasn't trying to sound sharp with you earlier.",
        "Which version should we show the vendor on Monday?",
        "Give me a minute; I think the bigger issue is the schedule.",
        "Sure, go ahead. I'll check with Joe and get back to you.",
        "We both want this to work, so tell me what feels wrong.",
    ]

    /// 1-4 in 존댓말 (2 is 하십시오체, the rest 해요체), 5-8 in 반말.
    public static let korean = [
        "내일 회의 자료는 제가 오전까지 정리해서 보내 드릴게요.",
        "그 부분은 조금 더 확인해 보고 다시 말씀드리겠습니다.",
        "팀장님, 일정이 빠듯해서 금요일은 어려울 것 같아요.",
        "혹시 쓰신 보고서를 같이 볼 수 있을까요?",
        "아까 내가 좀 딱딱하게 말했지? 미안, 그런 뜻 아니었어.",
        "그냥 네 생각을 솔직하게 듣고 싶어서 물어본 거야.",
        "주말에 시간 괜찮으면 같이 밥이나 먹자.",
        "의자 좀 저쪽으로 치워 줄래? 짐 놓을 데가 없어.",
    ]

    public static let freeSpeechPrompt = (english: "Tell me how your week went.", korean: "이번 주 어떻게 보냈는지 들려주세요.")
    public static let freeSpeechSeconds = 20.0...30.0

    /// The proposal names no list for the check, so these are short, neutral phrases the user has
    /// not read during enrolment. One is chosen at random and said from about 1 m away.
    public static let checkPhrases = (
        english: ["The coffee here is pretty good.", "Let's meet near the station.", "I left my umbrella at home."],
        korean: ["여기 커피 꽤 괜찮네요.", "역 근처에서 만나요.", "우산을 집에 두고 왔어요."]
    )

    public static func sentences(for language: SpeechLanguage) -> [String] {
        language == .korean ? korean : english
    }

    /// The sentence ends in a polite ending (요 or 니다), ignoring trailing punctuation.
    public static func endsPolite(_ sentence: String) -> Bool {
        let core = sentence.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        return core.hasSuffix("요") || core.hasSuffix("니다")
    }
}

public enum EnrollmentStep: Equatable, Sendable {
    case consent
    case declined
    case placement
    /// Reading scripted sentence `index`, 0-based.
    case sentence(Int)
    case freeSpeech
    case phraseCheck
    /// One of the two extra sentences recorded after a failed check, 0 or 1.
    case extraSentence(Int)
    case baseline
    case done
}

/// The enrolment state machine. Every path to `done` passes through consent.
public struct EnrollmentFlow: Equatable, Sendable {
    public static let extraSentenceCount = 2

    public private(set) var step: EnrollmentStep = .consent
    public private(set) var consented = false
    public let sentenceCount: Int

    public init(sentenceCount: Int = EnrollmentScript.korean.count) {
        self.sentenceCount = sentenceCount
    }

    public mutating func answerConsent(_ agreed: Bool) {
        guard step == .consent || step == .declined else { return }
        consented = agreed
        step = agreed ? .placement : .declined
    }

    public mutating func confirmPlacement() {
        guard consented, step == .placement else { return }
        step = .sentence(0)
    }

    public mutating func finishSentence() {
        guard consented else { return }
        switch step {
        case .sentence(let i):
            step = i + 1 < sentenceCount ? .sentence(i + 1) : .freeSpeech
        case .extraSentence(let i):
            step = i + 1 < Self.extraSentenceCount ? .extraSentence(i + 1) : .phraseCheck
        default:
            return
        }
    }

    /// Accepts free speech only within 20-30 s; otherwise the step repeats. Returns whether it was accepted.
    @discardableResult
    public mutating func finishFreeSpeech(seconds: Double) -> Bool {
        guard consented, step == .freeSpeech, EnrollmentScript.freeSpeechSeconds.contains(seconds) else { return false }
        step = .phraseCheck
        return true
    }

    /// A passed check moves on to the baseline; a failed one asks for two more sentences.
    public mutating func finishPhraseCheck(passed: Bool) {
        guard consented, step == .phraseCheck else { return }
        step = passed ? .baseline : .extraSentence(0)
    }

    public mutating func finishBaseline() {
        guard consented, step == .baseline else { return }
        step = .done
    }

    /// Withdrawing consent ends enrolment; the caller deletes anything recorded so far.
    public mutating func withdrawConsent() {
        consented = false
        step = .declined
    }
}
