# AGENTS additions for Autunite Pass 1

- Codex builds P7–P8 and reviews Claude-built P1–P6 only.
- Product rules are in repo-root `INTENTIONAL.md`, `IMPLEMENTATION_BLUEPRINT.md`, and `DESIGN.md`; the design is settled.
- Processing stays on the phone: no network calls, cloud services, or third-party AI.
- Readings are per-category distances from the chosen intention, never a toxicity score.
- New copy is warm in Korean and English and never asserts the other person’s feelings.
- Build with `xtool`, never an `.xcodeproj`.
- Phase checks (run from the repo root):
  - P1: `grep -rqE 'func enrollmentScriptsHaveRequiredRegisterSplit' Tests/AutoniteCoreTests && grep -rqE 'func enrollmentFlowRequiresConsentAndRecovery' Tests/AutoniteCoreTests && swift test --filter 'enrollmentScriptsHaveRequiredRegisterSplit|enrollmentFlowRequiresConsentAndRecovery'`
  - P2: `grep -rqE 'func voiceProfileStoreRoundTripAndDelete' Tests/AutoniteCoreTests && grep -rqE 'func voiceProfileStoreRejectsUnconsentedAudio' Tests/AutoniteCoreTests && swift test --filter 'voiceProfileStoreRoundTripAndDelete|voiceProfileStoreRejectsUnconsentedAudio' && xtool dev build`
  - P3: `grep -rqE 'func koreanRegisterThirtyPhraseFixture' Tests/AutoniteCoreTests && swift test --filter 'koreanRegisterThirtyPhraseFixture'`
  - P4: `grep -rqE 'func englishRegisterTwentyPhraseFixture' Tests/AutoniteCoreTests && grep -rqE 'func wordChoiceRespectsBluntIntention' Tests/AutoniteCoreTests && swift test --filter 'englishRegisterTwentyPhraseFixture|wordChoiceRespectsBluntIntention'`
  - P5: `grep -rqE 'func intentionWeightingTableSuppressesChosenModes' Tests/AutoniteCoreTests && grep -rqE 'func unmeasuredCategoriesAlwaysAbstain' Tests/AutoniteCoreTests && swift test --filter 'intentionWeightingTableSuppressesChosenModes|unmeasuredCategoriesAlwaysAbstain'`
  - P6: `grep -rqE 'func readingPipelineRejectsOtherUnknownOverlapAndLowConfidence' Tests/AutoniteCoreTests && swift test --filter 'readingPipelineRejectsOtherUnknownOverlapAndLowConfidence'`
  - P7: `grep -rqE 'func pass1CopyIsBilingualAndAvoidsForbiddenClaims' Tests/AutoniteCoreTests && grep -rqE 'func enrollmentOnboardingRequiresConsent' Tests/AutoniteCoreTests && swift test --filter 'pass1CopyIsBilingualAndAvoidsForbiddenClaims|enrollmentOnboardingRequiresConsent' && xtool dev build`
  - P8: `grep -rqE 'func liveMeterGeometryKeepsLowerTicksAbsent' Tests/AutoniteCoreTests && swift test --filter 'liveMeterGeometryKeepsLowerTicksAbsent' && xtool dev build && SIMCTL_CHILD_AUTONITE_SELFTEST=1 python3 "$HOME/projects/agent-skills/ios-xtool/scripts/xtkit.py" simtest . --sentinel 'autonite selftest succeeded'`
