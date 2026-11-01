import Foundation

/// The user's saved voice (SPEC AC3). It is biometric data: it stays on the phone, is written
/// with complete file protection, and one call deletes it.
///
/// FluidAudio's Sortformer diarizer can only enrol a speaker slot from audio, not from a stored
/// embedding, so the profile keeps the enrolment audio alongside the voiceprint. That is the AC3
/// fallback, recorded in progress.md and disclosed at consent.
public struct VoiceProfile: Codable, Equatable, Sendable {
    /// Mono enrolment samples, used only to prime the diarizer's slot for the user.
    public var enrollmentAudio: [Float]
    public var sampleRate: Double
    /// WeSpeaker voiceprint of the enrolment, compared with each slot-Me piece (`VoiceVerifier`).
    public var voiceprint: [Float]
    public var createdAt: Date

    public init(enrollmentAudio: [Float], sampleRate: Double, voiceprint: [Float], createdAt: Date = Date()) {
        self.enrollmentAudio = enrollmentAudio
        self.sampleRate = sampleRate
        self.voiceprint = voiceprint
        self.createdAt = createdAt
    }
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
        let data = try PropertyListEncoder().encode(profile)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: file, options: .atomic)
        #endif
    }

    public func load() throws -> VoiceProfile? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try PropertyListDecoder().decode(VoiceProfile.self, from: Data(contentsOf: file))
    }

    /// Deletes the profile and everything else in its folder.
    public func delete() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}

/// What the diarizer must offer to take a stored profile. `VoiceDiarizer` conforms on iOS.
public protocol SpeakerEnrolling {
    /// Primes a slot with the user's voice and returns it, or nil when the audio held no speech.
    func enroll(_ profile: VoiceProfile) throws -> Int?
}
