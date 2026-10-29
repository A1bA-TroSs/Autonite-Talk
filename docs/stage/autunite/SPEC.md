# Autunite Pass 1: Korea-first register reading — spec

Source: approved Stage 1 proposal `Claude outputs/ideas/autunite/01-research/proposal.md` (Danny approved 2026-10-29, path "Path 1: Korea-first, register lead"; verdicts 2026-10-29-043, -044, -047, -050). Product rules: `~/projects/autonite-talk/INTENTIONAL.md`, `IMPLEMENTATION_BLUEPRINT.md`, `DESIGN.md` (the design scheme is settled and is not redesigned here).

## Goal

After this build, Autunite on an iPhone does three new things, on top of the Pass 0 harness and its enrollment experiment (commit 1ea7aa4):

1. **Voice enrollment onboarding.** At first setup the user gives separate biometric consent, then reads scripted sentences and speaks freely, so the app keeps an on-device voice profile and measures only the user's own speech.
2. **A live, per-category reading of the user's own completed phrases**, weighed against the tone the user chose for this conversation. This build ships the two categories that are detectable from text — **register** (존댓말/반말 shifts in Korean; formality shifts in English) and **word choice** — and leaves sarcasm, tone/manner and sharp/stiff phrasing as visible "not yet measured" slots.
3. **The live screen** shows these readings on the round meter defined in `DESIGN.md`, with one short haptic on a mismatch, and only for speech attributed to the user.

Korean is the first speech language; English follows the same code path. Everything stays on the phone. Danny wants this to test whether the Korea-first register reading is useful before investing in the remaining categories.

## Non-goals

- Sarcasm, tone/manner and sharp/stiff detection (slots only, labelled not yet measured).
- Recap, commitments, calendar drafts (unchanged from the blueprint; not touched in this build).
- Sending any user data off the phone: no cloud model, third-party AI, account, analytics or payment. The only network use allowed is downloading models and speech assets before the first session (FluidAudio Sortformer and embedding models, Apple SpeechTranscriber locale assets); no audio, text, voiceprint or reading ever leaves the phone. Ruling 2026-10-29: Danny's "keep it on the user's phone" is about user data.
- A universal toxicity score, a moral grade, or any judgement of the other person.
- Redesigning visuals, the logo or the meter (DESIGN.md is settled).
- Android, watch, earbuds, phone-call capture.

## Acceptance criteria

Each criterion names the check that shows it. Mac checks need Xcode installed (precondition). Device criteria are end-gate items.

- **AC1 Enrollment script.** The app ships the 8 Korean and 8 English draft enrollment sentences from the proposal's enrollment design (Korean 1-4 존댓말, 5-8 반말). Check: a unit test asserts both lists have 8 entries, and the Korean list has 4 sentences ending in a polite ending (`요` or `니다`) and 4 without.
- **AC2 Enrollment flow state machine.** Consent, placement, 8 sentences, 20-30 s free speech, random-phrase check, baseline, done; "record two more sentences" after a failed check; no path reaches done without consent. Check: unit tests on the state machine in AutoniteCore.
- **AC3 Voice profile storage and restore.** The profile persists across relaunch and identifies the user without re-enrolling. Preferred: embeddings only, restored into the FluidAudio diarizer. If the FluidAudio API cannot restore a speaker slot from a stored embedding, store the enrollment audio (the ~10 s the existing harness already enrols from, plus the scripted reading) on the phone instead, under the same biometric consent, and say so in progress.md. Either way: app storage with complete file protection, nothing leaves the phone, one call deletes it. Check: unit tests on the profile store (write, relaunch-read, delete leaves nothing) and on the diarizer adapter accepting the stored profile.
- **AC4 Register reading (Korean).** Given a completed user phrase and the session's register intention (for example 존댓말 expected), the reader returns `aligned`, `check` or `unknown`. Check: unit tests over a fixture of at least 30 Korean phrases covering 하십시오체, 해요체, 반말 and mixed endings, with expected outputs; all pass.
- **AC5 Register reading (English).** Same contract for formality shifts in English. Check: unit tests over at least 20 fixture phrases; all pass.
- **AC6 Word-choice reading.** On-device lexicon-based reading for harsh words in Korean and English, weighed by intention. Check: unit tests over fixtures; a phrase flagged under a "gentle" intention is not flagged under a "blunt is fine" intention.
- **AC7 Intention weighting.** A category the user marked as intended (for example "direct", "formal", "반말 is fine") never produces a mismatch for that category. Check: unit tests for each category and intention combination in the weighting table.
- **AC8 Own speech only.** No reading or haptic is produced for a segment not attributed to the user with confidence of at least 0.6 (existing `CueGate`), or for overlapped speech. Check: unit tests feeding `other`, `unknown` and overlapped segments.
- **AC9 Not-yet-measured slots.** Sarcasm, tone/manner and sharp/stiff appear as slots that always report `notMeasured`. Check: unit test.
- **AC10 Wiring.** The app builds and the Simulator self-test reaches its sentinel with the enrollment and reading paths compiled in. Check: `xtool dev build` and the repo's `simtest` command with sentinel `autonite selftest succeeded`.
- **AC12 Intention to settings.** Session setup keeps the user's free-text intention and adds a short per-category setting the user confirms: register (존댓말 expected / 반말 fine / either) and word choice (gentle / blunt is fine), with presets that fill both. The live readers use only these confirmed settings; the free text is shown and stored, never parsed into a setting without the user confirming it. Check: unit tests from setup state through the reader (a confirmed "반말 fine" stops register mismatches; an unconfirmed preset does not change readings).
- **AC13 Live states per DESIGN.md.** The live screen has the single top recording strip, the round meter with upper-only ticks, and a cue card on tap showing the user's exact phrase, a conditional reading ("may sound…"), the intention it relates to, and one suggested next sentence. Check: unit tests on the live view-model states (idle, reading, cue card contents, recording stopped) plus an end-gate screen review on device.
- **AC11 Copy.** Every new user-facing string exists in Korean and English, warm in voice, and none states the other person's feelings as fact. Check: a unit test that every new string key has both localizations, and a test that rejects strings containing a fixed list of forbidden phrasings (for example "상대가 화났", "they are upset").

## Decided

- Path 1, Korea-first, register lead (Danny, round 3; verdict 2026-10-29-047).
- Five categories shown, each weighed against the chosen intention; chosen directness is not flagged (Danny, round 2; verdict 2026-10-29-044).
- Voice enrollment at setup with scripted sentences plus a speech-habit baseline (Danny, round 1; verdict 2026-10-29-043).
- Name Autunite; data stays on the user's phone only; warm copy; free and open source for now (Danny, round 4; verdict 2026-10-29-050).
- The design scheme in DESIGN.md is settled (Danny, 2026-10-29).
- Free components only (Danny, 2026-10-29, per commit 1ea7aa4); FluidAudio for voice embeddings.
- Build with xtool, never an `.xcodeproj` (repo CLAUDE.md).

## Left to the builder

- The register reader's method (verb-ending rules, a small on-device classifier, or both), as long as the AC4 and AC5 fixtures pass.
- The harsh-word lexicon's source and size, if its licence allows open-source redistribution.
- Exact weighting values in the intention table, documented in code.
- Where enrollment UI sits in the existing harness navigation.
- How the random-phrase check is chosen from a fixed list.
