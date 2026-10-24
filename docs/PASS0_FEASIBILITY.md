# Pass 0: feasibility spike

This answers the two hardest unknowns in `IMPLEMENTATION_BLUEPRINT.md` §1 on a real iPhone before any coaching is built: **can the app tell the user's words from the other person's**, and **is cue latency usable**. It also checks English and Korean availability and whether the cue haptic is felt on a table while recording.

The app in `Sources/Autonite` is a test harness, not the product UI.

## What was checked before writing code

| Question | Finding | Source | Still to verify on device |
|---|---|---|---|
| On-device English and Korean transcription | `SpeechTranscriber` (iOS 26+) lists `ko_KR` among supported locales, with assets downloaded through `AssetInventory`. | [SpeechAnalyzer docs](https://developer.apple.com/documentation/speech/speechanalyzer), [iOS 26 SpeechAnalyzer guide](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide) | Whether both locales are offered on the test iPhone, download size and time |
| Native speaker diarization | None found in SpeechAnalyzer. A developer who reviewed the WWDC 2026 catalog reported the same and planned to use FluidAudio. | [Apple forums 829751](https://developer.apple.com/forums/thread/829751) | Whether the iOS 27 SDK adds anything |
| Third-party diarization | FluidAudio (Apache 2.0, iOS 17+, Core ML) has streaming diarization; it reports 26% DER for 5 s chunks. | [FluidAudio](https://github.com/FluidInference/FluidAudio) | Accuracy on two voices at a table, in Korean and English |
| Haptics while recording | iOS silences haptics during recording unless `setAllowHapticsAndSystemSoundsDuringRecording(true)` is set. The engine sets it. | AVAudioSession API | Whether the pulse is felt face-up on a table |

A 26% diarization error rate is far too high for a cue that must never fire on the other person's words. So attribution is the experiment that decides whether the product works, and Pass 0 measures it before adding any model.

## What the harness does

- **Locale check.** At launch: is `SpeechTranscriber` available, and is each language supported and already installed?
- **Session.** Pick English or Korean, then Start Session. Assets download if needed. One recording strip at the top shows a dot, the level and a timer. Pass 0 keeps no audio after the session.
- **Transcript evidence.** For each finalized segment: text, time range, **latency** (wall-clock time from the end of the speech to the final result) and mean input level.
- **Attribution experiment.** Tag each line **Me** or **Other**. A baseline predictor guesses the speaker from input level: the phone sits nearer the user, so the user should be louder, and the audio session uses `.measurement` mode to turn off automatic gain control. The baseline is scored leave-one-out against the tags. It abstains when the voices aren't at least 3 dB apart. `CueGate` would fire a cue only on `user` with confidence ≥ 0.6.
- **Haptic trial.** Choose a placement, play the cue pulse, then record Felt it or Didn't feel it. Each trial also records whether a session was recording.
- **Interruptions.** These are counted and recorded. Pass 0 does not resume capture after one.
- **Export.** The full report goes out as JSON through the share sheet.

## Build and run

You need a Mac with Xcode 26 or later (for the iOS 26 SDK) and an iPhone running iOS 26 or later. Plug the iPhone in over USB.

```bash
swift test                 # AutoniteCore logic, runs on the Mac
brew install xtool-org/tap/xtool
xtool setup
xtool auth                 # Danny enters his own Apple ID; agents never do
xtool dev                  # build, sign, install and launch on the iPhone
```

Speech assets don't work in the Simulator, so use a real device.

## Protocol

Run each step in English, then again in Korean. Use two people at a table, with the phone face-up about 40 cm from the user and about 1 m from the other person. Both people agree to the recording first.

1. **Locales.** Screenshot the Device section before downloading anything.
2. **Turn-taking.** Talk for about 3 minutes, taking clear turns with roughly 20 utterances each. Tag every line.
3. **Hard case.** Talk for about 2 minutes with interruptions, overlapping speech and the other person leaning in. Tag every line.
4. **Haptics.** Run at least 3 trials per placement, both while recording and while idle.
5. **Interruption.** During a session, call the phone or trigger Siri, and note what the strip shows.
6. **Mixed language.** Optionally, try one English/Korean code-switching passage in each mode. Note it, but don't treat it as a gate.
7. **Export.** Export the JSON and commit it as `docs/evidence/<date>-<device>.json`.

## Decision gate before Pass 1

| Evidence | Go | Stop and decide |
|---|---|---|
| Other called Me (turn-taking) | 0 of ~20 at confidence ≥ 0.6 | Any. A cue on the other person's words is the failure the handoff forbids |
| Coverage (turn-taking) | Most user lines committed | Mostly abstaining: live cues would almost never fire |
| Latency p90 | Short enough that a cue lands within the same exchange (target to be set from this data) | A cue arrives after the topic has moved on |
| Haptic face-up while recording | Felt in most trials | Not felt: a visual-only cue becomes the main path |
| Both locales | Supported on the target device | One is missing: a product decision on scope or minimum device |

If level-based attribution fails the gate, the next experiment is speaker-embedding enrollment: the user records a short voice sample and each utterance is matched against it, using FluidAudio's embeddings. That uses the same harness and the same score.

## Not in Pass 0

Cue generation, the meter, the recap, the calendar, localization of the harness UI, and resuming after an interruption.
