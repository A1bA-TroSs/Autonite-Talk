import Foundation

/// The user's saved voice (SPEC AC3). It is biometric data: it stays on the phone, is written
/// with complete file protection, and one call deletes it.
///
/// Only voiceprints are kept, never audio (rubric M3). FluidAudio's Sortformer diarizer can't take
/// a stored voiceprint into a speaker slot, so instead of priming a slot with saved audio, each
/// conversation finds the user's slot by comparing the slots' speech with these prints
/// (`UserSlotFinder`). SPEC AC3 prefers embeddings only; this meets it without a slot restore.
public struct VoiceProfile: Codable, Equatable, Sendable {
    /// WeSpeaker voiceprint of the enrolment (the mean of the reading and the free speech).
    public var voiceprint: [Float]
    /// Voiceprints of short stretches of the enrolment (different sentences, tones and pitches).
    /// A live piece is compared with each and the closest counts, so the user doesn't have to
    /// speak in one tone to be recognised (Danny, 2026-11-02). Nil in profiles saved before this.
    public var voiceprints: [[Float]]?
    public var createdAt: Date

    public init(voiceprint: [Float], voiceprints: [[Float]]? = nil, createdAt: Date = Date()) {
        self.voiceprint = voiceprint
        self.voiceprints = voiceprints
        self.createdAt = createdAt
    }

    /// Every print to compare speech with: the mean and each stretch.
    public var allPrints: [[Float]] { [voiceprint] + (voiceprints ?? []) }
}

public struct VoiceProfileStore: Sendable {
    public let directory: URL
    private var file: URL { directory.appendingPathComponent("voice-profile.plist") }

    public init(directory: URL) {
        self.directory = directory
    }

    /// The app's own Application Support folder, excluded from backups.
    public static func appDefault() throws -> VoiceProfileStore {
        var folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("VoiceProfile", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        return VoiceProfileStore(directory: folder)
    }

    public func save(_ profile: VoiceProfile) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(profile)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: file, options: .atomic)
        #endif
    }

    /// Reads the profile. A profile saved by an earlier build also holds its enrolment audio; it is
    /// rewritten at once with the prints alone, so no audio stays on disk (rubric M3).
    public func load() throws -> VoiceProfile? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        let profile = try PropertyListDecoder().decode(VoiceProfile.self, from: data)
        if Self.holdsAudio(data) { try save(profile) }
        return profile
    }

    /// Whether saved profile data holds audio samples (keys earlier builds wrote).
    public static func holdsAudio(_ data: Data) -> Bool {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return false }
        return plist["enrollmentAudio"] != nil || plist["sampleRate"] != nil
    }

    /// Deletes the profile and everything else in its folder.
    public func delete() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}

/// What the diarizer must offer to take a stored profile. `VoiceDiarizer` conforms on iOS.
public protocol SpeakerEnrolling {
    /// Starts a new conversation that looks for the user's voice by these prints. Returns false
    /// when the profile holds no print to look with.
    func enroll(_ profile: VoiceProfile) throws -> Bool
}

/// Finds which diarizer slot is the user's, from voiceprints alone (rubric M3: the profile keeps
/// no audio to prime a slot with). The latest clear stretch of each slot is printed and compared
/// with the user's prints. A slot becomes the user's when its match clears
/// `VoiceVerifier.strictThreshold` and beats every other slot by `margin`; until then nothing is
/// called the user's, so no cue can fire. Once found, the slot moves only when another slot
/// clears the same bar, so one odd stretch doesn't move it.
public struct UserSlotFinder: Equatable, Sendable {
    /// Turns shorter than this aren't printed for the search.
    public static let minimumSeconds = 1.0
    /// A print covers at most the last this-many seconds of a turn.
    public static let printSeconds = 3.0
    /// A slot is printed again only after this many more seconds of its speech.
    public static let recheckSeconds = 2.0
    /// How far the user's slot must match above every other slot.
    public static let margin = 0.1

    public private(set) var slot: Int?
    /// Each slot's match, averaged with its previous one so a single stretch can't decide alone.
    public private(set) var matches: [Int: Double] = [:]
    /// Audio time up to which each slot has been printed.
    public private(set) var checkedUntil: [Int: Double] = [:]

    public init() {}

    /// The stretches to print now: for each slot, its latest turn of at least `minimumSeconds`,
    /// cut to its last `printSeconds`, when no other slot talks in that stretch and the slot has
    /// `recheckSeconds` of new speech since its last print.
    public func windows(in turns: [SpeakerTurn]) -> [(slot: Int, window: ClosedRange<Double>)] {
        var latest: [Int: ClosedRange<Double>] = [:]
        for turn in turns where turn.end - turn.start >= Self.minimumSeconds {
            let window = max(turn.start, turn.end - Self.printSeconds)...turn.end
            let crowded = turns.contains { $0.slot != turn.slot && $0.start < window.upperBound && $0.end > window.lowerBound }
            if crowded { continue }
            if let current = latest[turn.slot], current.upperBound >= window.upperBound { continue }
            latest[turn.slot] = window
        }
        return latest.sorted { $0.key < $1.key }.compactMap { slot, window in
            if let last = checkedUntil[slot], window.upperBound - last < Self.recheckSeconds { return nil }
            return (slot, window)
        }
    }

    /// Takes the match of a printed stretch and returns the user's slot, or nil while no slot
    /// clearly sounds like the user.
    @discardableResult
    public mutating func record(slot candidate: Int, window: ClosedRange<Double>, match: Double) -> Int? {
        checkedUntil[candidate] = window.upperBound
        matches[candidate] = matches[candidate].map { ($0 + match) / 2 } ?? match
        guard let best = matches.max(by: { $0.value < $1.value }), best.value >= VoiceVerifier.strictThreshold else { return slot }
        let runnerUp = matches.filter { $0.key != best.key }.map(\.value).max() ?? -1
        if best.value - runnerUp >= Self.margin { slot = best.key }
        return slot
    }
}
