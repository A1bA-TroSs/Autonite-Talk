# PLAN.md — Autunite Pass 1

Pass 1 starts after Xcode is installed and selected, xtool is installed, and `docs/evidence/PASS0_DECISION.md` records `decision: go`. The current machine selects CommandLineTools, and the decision file is absent.

| Phase | Deliverable | Acceptance criteria |
|---|---|---|
| P1 | Enrollment scripts and consent-gated flow | AC1–AC2 |
| P2 | Protected profile that survives relaunch, restores into the diarizer and deletes cleanly | AC3 |
| P3 | Korean register reader and 30-phrase fixture | AC4 |
| P4 | English register reader and bilingual word-choice lexicon | AC5–AC6 |
| P5 | Confirmed category settings, weighting and three `notMeasured` slots | AC7, AC9, AC12 logic |
| P6 | Completed-phrase pipeline gated to the user's own speech | AC8 |
| P7 | Enrollment and session setup UI, setting confirmation and bilingual copy | AC11, AC12 UI |
| P8 | DESIGN.md live states, meter, cue card, haptic, build and Simulator self-test | AC10, AC13 |

Consent and profile restore come before the UI that depends on them. Readers and confirmed settings are tested before live speech reaches them. The final phase connects the gated pipeline to the settled screen design.

Risks: [inference] FluidAudio may require stored enrollment audio to restore a speaker; AC3 permits that on-phone fallback under biometric consent, with the choice recorded in `progress.md` and disclosed in onboarding. The lexicon needs a redistributable licence. Model and speech-asset downloads may occur before first use; no user data leaves the phone. Real-device matching, haptic feel, live-screen layout and register usefulness remain end gates.
