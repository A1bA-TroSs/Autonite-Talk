import Foundation

/// The five toxicness categories in INTENTIONAL.md section 4. Pass 1 measures the first two.
public enum ReadingCategory: String, Codable, CaseIterable, Sendable {
    case register
    case wordChoice
    case sarcasm
    case manner
    case voiceTone

    public var isMeasured: Bool { self == .register || self == .wordChoice }
}

/// The settings the readers use. Nice by default: 존댓말 expected and gentle word choice.
public struct CategorySettings: Codable, Equatable, Sendable {
    public var register: RegisterSetting
    public var wordChoice: WordChoiceSetting

    public init(register: RegisterSetting, wordChoice: WordChoiceSetting) {
        self.register = register
        self.wordChoice = wordChoice
    }

    public static let niceDefault = CategorySettings(register: .politeExpected, wordChoice: .gentle)
}

/// Relationship presets that propose settings. A preset never takes effect until the user confirms it.
public enum SettingsPreset: String, Codable, CaseIterable, Sendable {
    case senior
    case stranger
    case colleague
    case closeFriend
    /// A conversation where bluntness is the goal, such as delivering a firm no.
    case firmNo

    public var settings: CategorySettings {
        switch self {
        case .senior, .stranger: return .niceDefault
        case .colleague: return CategorySettings(register: .either, wordChoice: .gentle)
        case .closeFriend: return CategorySettings(register: .casualFine, wordChoice: .gentle)
        case .firmNo: return CategorySettings(register: .politeExpected, wordChoice: .bluntFine)
        }
    }
}

/// Session setup (SPEC AC12). The free-text intention is shown and stored but never parsed into a
/// setting. Readers use `confirmed` only, which starts nice by default.
public struct SessionSetup: Codable, Equatable, Sendable {
    public var intentionText: String
    /// Settings a preset proposed, waiting for the user to confirm.
    public private(set) var proposed: CategorySettings?
    public private(set) var confirmed: CategorySettings

    public init(intentionText: String = "", confirmed: CategorySettings = .niceDefault) {
        self.intentionText = intentionText
        self.confirmed = confirmed
    }

    public mutating func propose(_ preset: SettingsPreset) {
        proposed = preset.settings
    }

    public mutating func confirmProposal() {
        guard let proposed else { return }
        confirmed = proposed
        self.proposed = nil
    }

    public mutating func discardProposal() {
        proposed = nil
    }

    /// A control the user sets directly is a confirmation.
    public mutating func confirm(register: RegisterSetting) {
        confirmed.register = register
    }

    public mutating func confirm(wordChoice: WordChoiceSetting) {
        confirmed.wordChoice = wordChoice
    }
}

/// One reading per category for a completed phrase.
public struct PhraseReadings: Equatable, Sendable {
    public let readings: [ReadingCategory: Reading]

    public subscript(category: ReadingCategory) -> Reading { readings[category] ?? .unknown }

    /// The categories that may not fit the settings. A cue is offered only when this is not empty.
    public var mismatches: [ReadingCategory] {
        ReadingCategory.allCases.filter { readings[$0] == .check }
    }
}

/// Reads a phrase in every category against the confirmed settings (SPEC AC7, AC9).
///
/// Weighting table. A `check` from a reader counts as a mismatch unless the setting chose that mode:
///
/// | Category | Setting | `check` counts? |
/// |---|---|---|
/// | register | politeExpected | yes: a 반말 or casual sentence |
/// | register | casualFine, either | never |
/// | wordChoice | gentle | yes: a word from the harsh lexicon |
/// | wordChoice | bluntFine | never |
/// | sarcasm, manner, voiceTone | any | never: always `notMeasured` |
///
/// The readers already apply the setting, so the table is enforced in them and tested here.
public enum PhraseReader {
    public static func read(_ phrase: String, language: SpeechLanguage, settings: CategorySettings) -> PhraseReadings {
        let register = language == .korean
            ? KoreanRegisterReader.read(phrase, setting: settings.register).reading
            : EnglishRegisterReader.read(phrase, setting: settings.register)
        var readings: [ReadingCategory: Reading] = [
            .register: register,
            .wordChoice: WordChoiceReader.read(phrase, setting: settings.wordChoice),
        ]
        for category in ReadingCategory.allCases where !category.isMeasured {
            readings[category] = .notMeasured
        }
        return PhraseReadings(readings: readings)
    }
}
