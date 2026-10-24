# Claude Code handoff

Copy this folder into or alongside the iOS project, then give Claude Code the following task. Keep the five Markdown files and supplied concept images together so the references resolve.

---

Build the first iPhone prototype of **Autunite**, a provisional-name in-person conversation coach. Read `README.md`, `INTENTIONAL.md`, `IMPLEMENTATION_BLUEPRINT.md`, and `DESIGN.md` in full before changing code. Treat the conversation decisions in `INTENTIONAL.md` as requirements, the screen/settings/data/recap contracts in `IMPLEMENTATION_BLUEPRINT.md` as the implementation plan, and the visual tokens and generated screen board in `DESIGN.md` as proposed design material. The approved logo composition is the two overlapping mineral-faceted speech bubbles with one orbit and dot.

First inspect the repository and its existing iOS conventions. If this is an empty repository, create a native SwiftUI project using a reasonable current deployment target only after checking the English and Korean speech-recognition capabilities on the target device/SDK. Do not assume a speech API supports both locales, offline processing, mixed-language input, speaker attribution, or the required haptics until verified.

Implement in bounded passes:

1. **Feasibility pass:** microphone capture with visible recording state, live English and Korean transcription in separate sessions, real-device foreground haptic, and a speaker-attribution experiment. Record observed device, locale availability, latency, and failure conditions. If the app cannot confidently identify the user's utterance, suppress live cue delivery and report that blocker before building the full coaching pipeline.
2. **Interaction pass:** implement the screen and settings contracts in `IMPLEMENTATION_BLUEPRINT.md`, including session setup, top recording waveform, round meter with upper-only ticks, “Listening” rest state, haptic-driven cue inspection, End Session, processing, and recap shells. Use fixtures where AI processing is not yet connected. Render and review screenshots on an iPhone simulator and test haptics on real hardware.
3. **Behavior pass:** compare completed user phrases with the selected intention, generate cautious possible-interpretation cues and one next sentence, and implement every sourced recap section and editable calendar draft specified in `IMPLEMENTATION_BLUEPRINT.md`. Never create calendar events automatically.
4. **Hardening pass:** English and Korean localization, consent and recording indication, interrupted-audio recovery, deletion and processing disclosures, accessibility, light/dark/increased-contrast layouts, and real conversation evaluation.

For each pass, implement one vertical slice, run the relevant test or device check, inspect the resulting UI or transcript, fix the largest observed issue, and document evidence. Limit visual refinement to three focused rounds before requesting a product decision. Report what ran and what remains unverified. Do not claim that a generated image proves a feature works.

Important behavior boundaries:

- The live meter represents possible **distance from the user's selected conversation intention**, not warmth, an MBTI category, a radiation measurement, or the other participant's actual feelings.
- Keep live guidance sparse: a brief vibration, a glanceable meter change, then an optional cue card. Detailed recap and calendar work happen after the session.
- Show the exact user phrase and a conditional possible reading. When transcription, speaker identity, or context is weak, stay quiet or show uncertainty.
- The recording is participant-aware, with a clear recording state and consent flow. Do not design covert capture.
- Only English and Korean UI and speech modes are in first-release scope. Mixed-language recognition is a test item, not a promised feature.
- The generated UI board is illustrative. Its sample recap copy, especially any “Overall” praise, is not product logic. Follow the factual recap contract in `INTENTIONAL.md`.
- The supplied icon is a concept bitmap. Recreate a clean, small-size-safe app icon from the approved composition; do not replace it with a standalone mineral, radiation trefoil, or microphone.

At the end of the first feasibility pass, provide a concise report: device and iOS version, locale availability for English and Korean, observed latency, speaker-attribution quality, haptic behavior on a table, privacy/processing choices, and the next implementation step. Ask only for a decision that changes the product or requires access to an external service.

---

## Files Claude should inspect

- `INTENTIONAL.md` — product behavior and validation contract.
- `IMPLEMENTATION_BLUEPRINT.md` — screens, settings, processing, record fields, recap sections, and acceptance checks.
- `DESIGN.md` — logo, screen architecture, mood, and UI rules.
- `assets/concepts/autunite-icon-approved-concept.png` — approved icon composition.
- `assets/concepts/autunite-ui-final-reference.png` — proposed screen board with a top recording strip, a round meter whose lower arc has no tick marks, and mineral/orbit artwork only in the report header. Do not add a second recording indicator.
- `assets/references/foolsgold-original.png` and `assets/references/iolite-original.png` — previous logo family.

## Unresolved items Claude should not silently decide

- Final name and availability.
- Cloud versus local analysis and retention policy for real conversation data.
- Minimum supported iPhone/iOS determined by verified bilingual speech and haptic performance.
- Whether natural code-switching works well enough to support.
