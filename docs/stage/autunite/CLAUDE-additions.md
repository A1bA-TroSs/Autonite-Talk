## Pass 1 (idea pipeline package `docs/stage/autunite/`)

- Phase checks run from the repo root; `swift test` needs Xcode.app selected (`xcode-select -p`), not CommandLineTools.
- App build: `xtool dev build`; Simulator self-test: `SIMCTL_CHILD_AUTONITE_SELFTEST=1 python3 ~/projects/agent-skills/ios-xtool/scripts/xtkit.py simtest . --sentinel "autonite selftest succeeded"`.
- Everything stays on the phone: no network calls, no cloud or third-party AI (Danny, 2026-10-29).
- Readings are distances from the user's chosen intention by category, never a toxicity score; a category the user chose is never flagged.
- Only register and word choice are measured in Pass 1; sarcasm, tone/manner and sharp/stiff report `notMeasured`.
- The voiceprint is biometric data: embeddings only, complete file protection, one-call delete, separate consent.
- Copy is warm, in Korean and English; never state the other person's feelings as fact.
