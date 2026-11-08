import Foundation

/// Every user-facing Pass 1 string, in Korean and English (SPEC AC11). Warm and conditional:
/// the copy may say how a phrase *might* sound, never what the other person feels.
public enum CopyKey: String, CaseIterable, Sendable {
    // Onboarding
    case welcomeTitle, welcomeBody
    case consentTitle, consentBody, consentStorage, consentAgree, consentDecline, consentDeclined
    case placementTitle, placementBody, placementDone
    case sentenceTitle, sentenceRecord, sentenceRecording
    case freeSpeechTitle, freeSpeechRecord, freeSpeechTooShort
    case checkTitle, checkBody, checkPassed, checkFailed
    case baselineTitle, baselineBody, enrolmentDone, deleteVoice, voiceDeleted
    // Session setup
    case setupTitle, intentionPrompt, intentionPlaceholder, presetsTitle
    case presetSenior, presetStranger, presetColleague, presetCloseFriend, presetFirmNo
    case proposalPending, proposalConfirm, proposalDiscard
    case registerTitle, registerPolite, registerCasualFine, registerEither
    case wordChoiceTitle, wordChoiceGentle, wordChoiceBlunt
    case startSession
    // Live
    case listening, listeningDetail, endSession, notMeasuredTitle, notMeasured
    case categorySarcasm, categoryManner, categoryVoiceTone
    case cueAvailable, cueYourWording, cuePossibleReading, cueWhyHere, cueTryNext, cueDismiss, cueMarkInaccurate, cueMarked
    case readingRegisterCasual, readingWordChoiceHarsh
    case whyRegisterPolite, whyWordChoiceGentle
    case nextRegisterFallback, nextWordChoice
    case sessionStopped
    // Live screen frame (UI reference) and what the last phrase did
    case appSubtitle, recording, intentionCaption, intentionNone, checkAlignmentTitle, checkAlignmentDetail
    case lastHeard, resultCue, resultAligned, quietUnsure, quietOther, quietOverlap, quietVoice, quietNoWords, voiceCheckOff
    case labTitle, close
    // Live readout while the user is still talking
    case liveNow, voiceYou, voiceChecking, liveFlagged, liveClean
}

public enum Copy {
    public static func text(_ key: CopyKey, _ language: SpeechLanguage) -> String {
        (language == .korean ? korean[key] : english[key]) ?? key.rawValue
    }

    /// Phrasings that state another person's feelings or judge the user. No copy may contain them.
    public static let forbidden = [
        "상대가 화났", "상대방이 화났", "기분 나빠했", "상처받았", "무례한 사람", "나쁜 사람",
        "they are upset", "they're upset", "they are angry", "they're angry", "you hurt them", "you are rude", "you're rude",
    ]

    public static let english: [CopyKey: String] = [
        .welcomeTitle: "Speak the way you mean to",
        .welcomeBody: "Autunite listens beside you and gives a gentle buzz when your wording might not match how you want to come across. Everything stays on this iPhone.",
        .consentTitle: "May Autunite learn your voice?",
        .consentBody: "To react only to your own words, Autunite keeps a voice profile of you. This is biometric data, separate from permission to record a conversation.",
        .consentStorage: "Your voice profile and the short reading you record stay on this iPhone, protected, and never leave it. You can delete them at any time.",
        .consentAgree: "Yes, learn my voice",
        .consentDecline: "Not now",
        .consentDeclined: "That's fine. Without a voice profile, Autunite stays quiet and gives no cues.",
        .placementTitle: "Place your phone",
        .placementBody: "Set your iPhone screen-up where it will sit during a conversation, about 40 cm away.",
        .placementDone: "It's in place",
        .sentenceTitle: "Read this aloud, in your usual voice",
        .sentenceRecord: "Record",
        .sentenceRecording: "Listening…",
        .freeSpeechTitle: "Now just talk for about 25 seconds: tell me how your week went.",
        .freeSpeechRecord: "Start talking",
        .freeSpeechTooShort: "That was a little short. Let's try once more, 20 to 30 seconds is perfect.",
        .checkTitle: "One quick check",
        .checkBody: "Lean back, about 1 m from the phone, and say this:",
        .checkPassed: "Got it, that sounded like you.",
        .checkFailed: "That one was hard to hear. Two more short sentences will help.",
        .baselineTitle: "Saving your voice",
        .baselineBody: "Setting up your profile on this iPhone.",
        .enrolmentDone: "All set. Autunite now knows your voice.",
        .deleteVoice: "Delete my voice profile",
        .voiceDeleted: "Your voice profile is deleted.",
        .setupTitle: "Before you talk",
        .intentionPrompt: "How do you want to come across?",
        .intentionPlaceholder: "For example: calm and respectful, but clear",
        .presetsTitle: "Who are you talking with?",
        .presetSenior: "Someone senior",
        .presetStranger: "Someone new",
        .presetColleague: "A colleague",
        .presetCloseFriend: "A close friend",
        .presetFirmNo: "Saying a firm no",
        .proposalPending: "This preset suggests the settings below. They apply once you confirm.",
        .proposalConfirm: "Use these settings",
        .proposalDiscard: "Keep my settings",
        .registerTitle: "Speech level",
        .registerPolite: "Polite expected",
        .registerCasualFine: "Casual is fine",
        .registerEither: "Either",
        .wordChoiceTitle: "Word choice",
        .wordChoiceGentle: "Gentle",
        .wordChoiceBlunt: "Blunt is fine",
        .startSession: "Start session",
        .listening: "Listening",
        .listeningDetail: "A cue appears here only when it may help.",
        .endSession: "End session",
        .notMeasuredTitle: "Not measured yet",
        .notMeasured: "not measured yet",
        .categorySarcasm: "Sarcasm",
        .categoryManner: "Manner",
        .categoryVoiceTone: "Voice tone",
        .cueAvailable: "Tap to see a possible wording cue",
        .cueYourWording: "Your wording",
        .cuePossibleReading: "Possible reading",
        .cueWhyHere: "Why it matters here",
        .cueTryNext: "Try next",
        .cueDismiss: "Dismiss",
        .cueMarkInaccurate: "This cue was wrong",
        .cueMarked: "Thanks, noted. This helps Autunite learn.",
        .readingRegisterCasual: "This may come across as more casual than you planned.",
        .readingWordChoiceHarsh: "A word here may sound sharper than you mean it.",
        .whyRegisterPolite: "You chose polite speech for this conversation.",
        .whyWordChoiceGentle: "You chose gentle word choice for this conversation.",
        .nextRegisterFallback: "Could I put that another way?",
        .nextWordChoice: "Let me say that more carefully: I see it a bit differently.",
        .sessionStopped: "Session ended",
        .appSubtitle: "In-person conversation coach",
        .recording: "Recording",
        .intentionCaption: "Conversation intention",
        .intentionNone: "Not set",
        .checkAlignmentTitle: "Check alignment",
        .checkAlignmentDetail: "This may not match your intention.",
        .lastHeard: "Last heard",
        .resultCue: "Cue given",
        .resultAligned: "Fits your settings",
        .quietUnsure: "No cue: not sure it was your voice",
        .quietOther: "No cue: sounded like the other person",
        .quietOverlap: "No cue: two voices overlapped",
        .quietVoice: "No cue: didn't match your saved voice",
        .quietNoWords: "No cue: no words heard",
        .voiceCheckOff: "Voice check isn't running, so no cues can be given. End the session and start again.",
        .labTitle: "Lab",
        .close: "Close",
        .liveNow: "Hearing now",
        .voiceYou: "Your voice",
        .voiceChecking: "Checking voice",
        .liveFlagged: "Something to watch",
        .liveClean: "Fine so far",
    ]

    public static let korean: [CopyKey: String] = [
        .welcomeTitle: "마음먹은 대로 말할 수 있게",
        .welcomeBody: "오토나이트는 옆에서 조용히 듣다가, 내 말이 원하는 느낌과 조금 달라질 수 있을 때 살짝 진동으로 알려 드려요. 모든 것은 이 아이폰 안에만 있어요.",
        .consentTitle: "내 목소리를 익혀도 될까요?",
        .consentBody: "내 말에만 반응하려면 오토나이트가 내 목소리 프로필을 저장해야 해요. 이는 생체 정보이며, 대화 녹음 동의와는 따로 받아요.",
        .consentStorage: "목소리 프로필과 짧은 낭독 녹음은 보호된 상태로 이 아이폰에만 남고, 밖으로 나가지 않아요. 언제든 삭제할 수 있어요.",
        .consentAgree: "네, 제 목소리를 익혀 주세요",
        .consentDecline: "다음에 할게요",
        .consentDeclined: "괜찮아요. 목소리 프로필이 없으면 오토나이트는 신호를 보내지 않고 조용히 있어요.",
        .placementTitle: "휴대폰을 놓아 주세요",
        .placementBody: "대화할 때처럼 화면이 위로 오게, 40cm쯤 떨어진 곳에 아이폰을 놓아 주세요.",
        .placementDone: "놓았어요",
        .sentenceTitle: "평소 목소리로 소리 내어 읽어 주세요",
        .sentenceRecord: "녹음",
        .sentenceRecording: "듣고 있어요…",
        .freeSpeechTitle: "이제 25초쯤 편하게 말해 주세요. 이번 주 어떻게 보냈는지 들려주세요.",
        .freeSpeechRecord: "말하기 시작",
        .freeSpeechTooShort: "조금 짧았어요. 20~30초면 딱 좋아요. 한 번만 더 해 볼까요?",
        .checkTitle: "마지막 확인",
        .checkBody: "휴대폰에서 1m쯤 몸을 뒤로 젖히고 이렇게 말해 주세요:",
        .checkPassed: "좋아요, 본인 목소리로 들렸어요.",
        .checkFailed: "이번엔 잘 들리지 않았어요. 짧은 문장 두 개만 더 읽어 주세요.",
        .baselineTitle: "목소리를 저장하고 있어요",
        .baselineBody: "이 아이폰에 프로필을 만들고 있어요.",
        .enrolmentDone: "준비됐어요. 이제 오토나이트가 내 목소리를 알아요.",
        .deleteVoice: "내 목소리 프로필 삭제",
        .voiceDeleted: "목소리 프로필을 삭제했어요.",
        .setupTitle: "대화를 시작하기 전에",
        .intentionPrompt: "어떤 느낌으로 말하고 싶나요?",
        .intentionPlaceholder: "예: 차분하고 예의 있게, 하지만 분명하게",
        .presetsTitle: "누구와 이야기하나요?",
        .presetSenior: "윗사람",
        .presetStranger: "처음 보는 사람",
        .presetColleague: "동료",
        .presetCloseFriend: "친한 친구",
        .presetFirmNo: "단호하게 거절할 때",
        .proposalPending: "이 프리셋은 아래 설정을 제안해요. 확인해야 적용돼요.",
        .proposalConfirm: "이 설정으로 할게요",
        .proposalDiscard: "지금 설정 유지",
        .registerTitle: "높임말",
        .registerPolite: "존댓말",
        .registerCasualFine: "반말도 괜찮아요",
        .registerEither: "상관없어요",
        .wordChoiceTitle: "단어 선택",
        .wordChoiceGentle: "부드럽게",
        .wordChoiceBlunt: "직설적이어도 괜찮아요",
        .startSession: "대화 시작",
        .listening: "듣고 있어요",
        .listeningDetail: "도움이 될 때만 여기에 신호가 떠요.",
        .endSession: "대화 끝내기",
        .notMeasuredTitle: "아직 측정하지 않아요",
        .notMeasured: "아직 측정 전",
        .categorySarcasm: "비아냥",
        .categoryManner: "말투",
        .categoryVoiceTone: "목소리 톤",
        .cueAvailable: "눌러서 말투 신호를 확인해 보세요",
        .cueYourWording: "내가 한 말",
        .cuePossibleReading: "이렇게 들릴 수도 있어요",
        .cueWhyHere: "지금 이 대화에서는",
        .cueTryNext: "이렇게 이어 가 보세요",
        .cueDismiss: "닫기",
        .cueMarkInaccurate: "이 신호는 틀렸어요",
        .cueMarked: "알려 주셔서 고마워요. 더 정확해지는 데 도움이 돼요.",
        .readingRegisterCasual: "생각했던 것보다 편하게 들릴 수도 있어요.",
        .readingWordChoiceHarsh: "이 단어가 생각보다 날카롭게 들릴 수도 있어요.",
        .whyRegisterPolite: "이번 대화는 존댓말로 하기로 했어요.",
        .whyWordChoiceGentle: "이번 대화는 부드러운 단어를 쓰기로 했어요.",
        .nextRegisterFallback: "제가 다시 말씀드려 볼게요.",
        .nextWordChoice: "제 말이 좀 세게 들렸다면, 다시 말해 볼게요. 저는 조금 다르게 생각해요.",
        .sessionStopped: "대화가 끝났어요",
        .appSubtitle: "대면 대화 코치",
        .recording: "녹음 중",
        .intentionCaption: "대화 의도",
        .intentionNone: "설정 안 함",
        .checkAlignmentTitle: "말투 확인",
        .checkAlignmentDetail: "의도와 조금 다를 수 있어요.",
        .lastHeard: "마지막으로 들은 말",
        .resultCue: "신호를 보냈어요",
        .resultAligned: "설정과 맞아요",
        .quietUnsure: "신호 없음: 내 목소리인지 확실하지 않아요",
        .quietOther: "신호 없음: 상대방 목소리로 들렸어요",
        .quietOverlap: "신호 없음: 목소리가 겹쳤어요",
        .quietVoice: "신호 없음: 저장된 내 목소리와 달랐어요",
        .quietNoWords: "신호 없음: 들린 말이 없어요",
        .voiceCheckOff: "목소리 확인이 꺼져 있어서 신호를 보낼 수 없어요. 대화를 끝내고 다시 시작해 주세요.",
        .labTitle: "실험실",
        .close: "닫기",
        .liveNow: "지금 듣는 말",
        .voiceYou: "내 목소리",
        .voiceChecking: "목소리 확인 중",
        .liveFlagged: "주의할 말이 있어요",
        .liveClean: "지금까지 괜찮아요",
    ]
}
