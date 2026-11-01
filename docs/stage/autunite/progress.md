# Progress

Append-only. The runner writes phase starts, failures and passes; the agent adds one line per phase on what it did and what the next phase should know.

- P1 (2026-11-01, cloud): `AutoniteCore/Enrollment.swift` has the proposal's 8+8 sentences unchanged, a 3-phrase random check list per language (the proposal names none), and `EnrollmentFlow`, where every path to done passes consent and a failed check asks for 2 extra sentences. Next: P2 stores the enrolment voiceprint, plus audio if needed to prime the Sortformer slot.
- P2 (2026-11-01, cloud): `VoiceProfile` and `VoiceProfileStore` (plist, `.completeFileProtection` on iOS, excluded from backup, `delete()` removes the folder). AC3 fallback taken: FluidAudio 0.18's Sortformer `enrollSpeaker` needs audio, so the profile stores the enrolment audio plus the WeSpeaker voiceprint. `VoiceDiarizer` conforms to `SpeakerEnrolling`. Onboarding (P7) must disclose that the audio is kept. The Pass 0 harness still enrols in memory only.
