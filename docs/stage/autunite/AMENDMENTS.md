# Amendments to the Pass 1 spec (approved by Danny 2026-11-01)

The spec was approved on 2026-10-29, before two inputs:

- Danny's decision of 2026-10-31: the meter reads toxicness in the user's own speech, nice by default and adjustable (INTENTIONAL.md, PR #3).
- The competitor and technique teardown of 2026-10-31 (vault `S-autunite-speaker-teardown`), and the Pass 0 podcast run of 2026-10-29.

Danny approved these on 2026-11-01. They are folded into `SPEC.md`, `PLAN.md` and `phases.json`, and `APPROVED.json` holds the new hashes. M4's build check is `scripts/ci_check.sh`.

## M1. Nice by default (AC7, AC12)

- Session setup starts from a relationship preset that is nice by default. For example, senior or stranger means 존댓말 expected and gentle word choice, and close friend means 반말 fine and gentle word choice.
- The user can relax any category for one conversation, such as blunt is fine for delivering a firm no. AC7 is unchanged: a relaxed category never produces a mismatch.
- New check: with the default preset and no user change, a 반말 phrase to a senior gives `check`. After the user confirms "반말 fine", the same phrase gives `aligned`.

## M2. Category names match INTENTIONAL.md (AC9)

The not-yet-measured slots are sarcasm (비아냥), manner (말투) and voice tone. Each stays `notMeasured` until a bilingual evaluation set shows it works, and none is advertised before then.

## M3. Own-speech gate uses voice verification (AC3, AC8)

- The diarizer's slot is not an identity. In the Pass 0 run of 2026-10-29, a louder podcast voice drifted into the user's slot at confidence 0.84 to 1.00.
- A segment counts as the user only when all of the following hold:
  - the diarizer puts it in the user's slot and no other slot overlaps it;
  - it has at least 1.5 s of speech;
  - its WeSpeaker voiceprint matches the enrolled voiceprint above a threshold.
- The threshold is set from tagged runs: zero false Me across N other-voice segments, reported with the rule-of-three bound 3/N.
- AC3: the profile stores the enrolment voiceprint (FluidAudio `extractSpeakerEmbedding`), which is enough for verification. Priming the diarizer slot still needs enrolment audio. If that audio is stored, it falls under the AC3 fallback (consent, complete file protection, one-call delete).

## M4. Build route (preconditions)

- Danny's Mac has no Xcode, and none is needed. CI on GitHub Actions `macos-26` runs `swift test`, the xtool build and the Simulator self-test on every push.
- Replace the "Xcode.app installed and selected" precondition with "the phase's checks pass in CI on the pushed branch".
- Keep the Pass 0 `decision: go` precondition.

## M5. Recap engine (out of scope here, recorded for Pass 2)

- The iPhone 15 (non-Pro) cannot run Apple Foundation Models.
- The free fallback is Qwen3 1.7B 4-bit through MLX Swift (Apache-2.0). It has not been measured.
- The recap is built in chunks with utterance ids. Speaker owner comes from the attribution labels, never from the language model.

## Deferred from the teardown

These are not in Pass 1:

- a second overlap opinion (LS-EEND);
- AS-norm score normalisation with a Korean and English cohort;
- multi-condition enrolment;
- a trained personal VAD;
- offline re-diarization before the recap.

Revisit them if the Pass 0 tagged runs show the simple gate misses too much of the user's speech or lets other voices through.
