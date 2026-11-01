import Foundation

/// A reading of one category for one completed user phrase (SPEC AC4-AC9).
public enum Reading: String, Codable, Sendable {
    /// Fits the session's setting.
    case aligned
    /// May not fit the setting; worth a cue.
    case check
    /// Not enough evidence to say. Never cues.
    case unknown
    /// The category has no validated detector yet (sarcasm, manner, voice tone).
    case notMeasured
}

/// What the session expects for register. Nice by default: a senior or stranger means 존댓말 expected.
public enum RegisterSetting: String, Codable, CaseIterable, Sendable {
    case politeExpected
    case casualFine
    case either
}

/// Korean speech levels the reader tells apart.
public enum KoreanRegister: String, Codable, Sendable {
    /// 하십시오체: 합니다, 합니까, 하십시오.
    case formal
    /// 해요체: 해요, 하죠.
    case polite
    /// 반말 (해체 and spoken 해라체): 해, 했어, 하자, 했지.
    case casual
}

public struct RegisterResult: Equatable, Sendable {
    public let reading: Reading
    /// The register of each sentence that had a clear final ending, in order.
    public let found: [KoreanRegister]
}

/// Reads 존댓말/반말 from Korean verb endings. Only sentence-final endings count: a sentence that
/// ends in a connective (…하고, …해서, …는데) or a bare noun says nothing, so the reader abstains
/// rather than guess. Rules stay on the phone.
public enum KoreanRegisterReader {
    public static func read(_ phrase: String, setting: RegisterSetting) -> RegisterResult {
        let found = sentences(in: phrase).compactMap(register(ofSentence:))
        guard !found.isEmpty else { return RegisterResult(reading: .unknown, found: []) }
        switch setting {
        case .politeExpected:
            return RegisterResult(reading: found.contains(.casual) ? .check : .aligned, found: found)
        case .casualFine, .either:
            return RegisterResult(reading: .aligned, found: found)
        }
    }

    /// Splits on sentence punctuation; text after the last mark counts as a sentence too.
    static func sentences(in phrase: String) -> [String] {
        phrase.split(whereSeparator: { ".?!…\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The register of the sentence's last word, or nil when its ending is not clearly final.
    public static func register(ofSentence sentence: String) -> KoreanRegister? {
        let words = sentence.split(whereSeparator: { $0.isWhitespace || $0 == "," })
        guard let last = words.last.map({ String($0).trimmingCharacters(in: .punctuationCharacters) }),
              let final = last.last, isHangul(final) else { return nil }

        if fillers.contains(last) { return nil }
        if politeWords.contains(last) { return .polite }
        if isFormal(last) { return .formal }
        if final == "요" || final == "죠" { return .polite }
        if connectives.contains(where: { last.hasSuffix($0) }) { return nil }
        if casualEndings.contains(where: { last.hasSuffix($0) }) { return .casual }
        return nil
    }

    /// 습니다/ㅂ니다, 습니까/ㅂ니까 and 십시오: 니다 or 니까 counts only after a syllable with final ㅂ
    /// or 습, so 아니다 and 그러니까 are not formal.
    static func isFormal(_ word: String) -> Bool {
        if word.hasSuffix("십시오") || word.hasSuffix("시오") { return true }
        guard word.hasSuffix("니다") || word.hasSuffix("니까") else { return false }
        let chars = Array(word)
        guard chars.count >= 3 else { return false }
        let before = chars[chars.count - 3]
        return before == "습" || finalConsonant(of: before) == 17 // ㅂ
    }

    /// Endings that continue a sentence, so the sentence is not complete.
    static let connectives = ["니까", "는데", "은데", "인데", "지만", "면서", "려고", "도록", "어서", "아서", "해서", "라서", "가지고", "고", "서", "면", "며"]

    /// Final 반말 endings. Checked after connectives, so 해서 is not read as 해.
    static let casualEndings = [
        "거든", "잖아", "구나", "어때",
        "어", "아", "야", "여", "지", "냐", "니", "자", "래", "대", "해", "네", "다", "까", "게", "걸", "군",
        "봐", "줘", "돼", "써", "켜", "놔", "져", "워",
    ]

    /// Hesitations that end a fragment but carry no register.
    static let fillers: Set<String> = ["어", "아", "음", "그", "저", "자", "이제", "막"]

    /// One-word polite answers whose endings would otherwise read as 반말.
    static let politeWords: Set<String> = ["네", "예"]

    static func isHangul(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0xAC00...0xD7A3).contains(v)
    }

    /// The final-consonant (jongseong) index of a Hangul syllable, 0 when it has none.
    static func finalConsonant(of c: Character) -> Int? {
        guard let v = c.unicodeScalars.first?.value, (0xAC00...0xD7A3).contains(v) else { return nil }
        return Int(v - 0xAC00) % 28
    }
}
