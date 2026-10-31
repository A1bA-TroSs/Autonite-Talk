# Autunite — product intent and behavior

**Status:** handoff design, 24 October 2026. **Working name:** Autunite. **First platform:** iPhone. **Languages:** English and Korean only, for interface copy and speech recognition.

## 1. Intent

Help a person speak as they intend during an in-person conversation, without making them stare at a transcript. The user puts an iPhone screen-up nearby. The app listens with the participants' knowledge, gives a brief vibration when the user's wording may diverge from a tone they chose for that conversation, and explains the possible reading and a useful next sentence when checked. After the conversation, it provides a factual recap and drafts follow-ups such as calendar events for the user to review.

This is a **conversation translator**: it preserves meaning while offering a different expression. Its default aim is to help the user speak nicely (말 예쁘게), but it must not override a category the user switched off for a conversation, infer another person's feelings as fact, or classify people by MBTI type.

## 2. Decisions already made by the user

- Begin with **face-to-face conversations on iPhone**. Ordinary phone-call capture is outside the first release.
- Give **wording coaching during the conversation**. Produce the detailed summary, action list, and calendar candidates **after the session ends**.
- Keep the phone **screen-up nearby**; use a **brief vibration** to call attention to a useful cue. The user checks the screen to read the reason and a suggested next sentence. No earbud delivery.
- Use a **Geiger-counter-like meter** as the visual metaphor. Like a counter picking up radiation, it reacts to **toxicness in the user's own speech**: word choice, sarcasm (비아냥), register (어체, 존댓말/반말), manner (말투) and voice tone. It does not measure another person's emotions.
- **Nice by default, adjustable** (decided 31 October 2026). The meter reads toxicness against speaking nicely, tuned by the relationship (for example, a senior expects 존댓말). The user can switch a category off for a conversation where bluntness is the goal, such as delivering a firm no.
- Keep the meter visually round, with tick marks only on the upper range the needle can reach. Keep one recording indicator above the meter. Reserve the mineral facets and orbit illustration for the report header; keep them out of the live meter.
- Let the user set a personal tone and the way they want to relate to the other person **for each conversation**. Niceness is the default target, and the user can relax it per category.
- Limit initial interface and speech-recognition languages to **English and Korean**.
- Keep the **two overlapping speech-bubble form** for the logo; give the bubbles mineral-like facets or gradation and add an orbit, matching the FoolsGold and Iolite logo family.

## 3. Proposed first-use flow

1. **Welcome and permissions.** Explain what is captured, what stays on the device or is sent elsewhere, and how to delete it. Ask for microphone and speech permissions when needed. Present a clear recording indicator. The user confirms the other participants know the conversation is being captured before starting.
2. **Set conversation intention.** Choose the speech language, then enter a short description such as “I want to be direct and respectful with my colleague; do not soften the decision.” Optional presets may help, but the user's own words are the source of truth. Keep the intention editable before and during a session.
3. **Start session.** Show recording state, elapsed time, the chosen intention in one line, a legible meter, and a large End Session control. The screen must be understandable from a glance at table distance.
4. **Detect a possible mismatch.** Wait for a completed user phrase and enough neighboring context. Attribute the phrase to the user. Compare it with the chosen intention and possible interpretations. If the evidence is weak, stay quiet. When useful, move the meter briefly and issue one short haptic pulse.
5. **Inspect cue.** On tap, show the exact phrase, one carefully worded possible interpretation, the part of the selected intention it may conflict with, and **one** suggested next sentence. The user can dismiss it or mark it inaccurate. Never require a response during the conversation.
6. **End session.** Stop recording immediately and show a processing state. Produce a recap with the topic sequence, key points, explicit decisions, commitments attributed to the right person, unresolved items, and optional wording reflections.
7. **Review actions.** Distinguish “said explicitly” from “suggested by the app.” Convert a possible appointment into a calendar draft only when date, time, and purpose are sufficiently grounded; ask the user to fill missing details. The user reviews and saves. Do not silently create or modify calendar items.

## 4. Live cue contract

Every cue must contain:

| Field | Rule |
|---|---|
| Trigger phrase | Quote a short, accurate span from the user's completed speech. |
| Selected intention | Show or reference the session setting that makes the cue relevant. |
| Possible reading | Say “may sound…” or “could be read as…,” not “the other person is hurt.” |
| Suggested next line | Preserve the user's meaning; offer one brief sentence that can be spoken next. |
| Confidence | If speaker identity, transcription, or context is uncertain, suppress or soften the cue rather than presenting it as certain. |
| Feedback | Allow dismissing and marking an inaccurate cue after the fact. Do not infer permanent traits from one conversation. |

Example, with intention **Direct + respectful**:

> User: “That won't work.”  
> Cue: “This may sound like a rejection of the whole idea.”  
> Next sentence: “I see the goal. I'm concerned about the timing.”

For a different intention, the same phrase may produce a different cue or none. The meter's movement represents **possible toxicness in the user's own phrase, judged against the session's settings** (nice by default, adjusted by the user). It is not a grade of the user's character or a judgment of the other speaker.

### Toxicness categories and readiness

| Category | Read from | Status |
|---|---|---|
| Register (어체: 존댓말/반말 shift against the relationship) | Transcript (Korean verb endings) | First release |
| Word choice (insults, profanity, harsh words) | Transcript | First release |
| Sarcasm (비아냥) | Transcript plus context; prosody helps | Behind an evaluation gate: no validated Korean detector |
| Manner (말투) and sharp or stiff phrasing | Transcript plus prosody | Behind an evaluation gate |
| Voice tone | Prosody (pitch, loudness, rate) | Behind an evaluation gate: no validated Korean model |

A category behind the gate does not fire live cues until a bilingual evaluation set shows it works. Do not advertise it before then.

## 5. Meter behavior

- Rest state is quiet and legible. A detected mismatch produces a brief movement; the meter then returns toward rest. It is not a cumulative “bad conversation” score.
- Show a qualitative label such as **Aligned**, **Check wording**, or **Review cue**. Do not show fake scientific units or claim to quantify emotional harm.
- Trigger haptics sparingly. Coalesce repeated warnings for one thought. Never interrupt continuously or punish the user for being direct when directness was their selected goal.
- The cue screen is optional to inspect; the user stays in the real conversation.
- Respect haptics settings and provide a visual fallback. A phone lying on a table may not be felt; verify this with real devices.

## 6. Post-session artifact

The recap should present, in order:

1. **What was discussed:** a short factual summary and chronological topic changes.
2. **What was decided:** decisions only when explicitly supported by the transcript.
3. **Who committed to what:** separate the user's commitments from the other person's; include dates only if spoken or confirmed.
4. **Open questions:** uncertainty or unresolved decisions.
5. **Suggested next actions:** clearly labeled as suggestions, with source moments where possible.
6. **Calendar drafts:** appointment candidates with editable title, date, time, timezone, and participants; save only after user review.
7. **Optional reflection:** up to a few relevant wording moments, framed against that session's intention rather than a personality grade.

The transcript may be available on demand for correction, but it is not the default recap view. If a date, speaker, or promise is uncertain, display that uncertainty rather than filling it in.

## 7. Language and speech rules

- UI localization: English and Korean, including permission explanations, live cues, recap labels, error messages, and accessibility labels.
- Session speech language: explicit English or Korean selection. Do not assume UI language and speech language are identical.
- At session start, check whether the selected speech model/locale is available on that device and whether a model download or network connection is required. Explain an unavailable state before recording begins.
- English/Korean code-switching is **unproven** for the first release. Test it with real conversations; do not advertise seamless mixed-language recognition until it passes.
- Maintain a bilingual evaluation set with natural directness, honorifics, ambiguity, interruptions, and overlapping speech. Korean politeness and English directness must be judged in context, not through word lists alone.

## 8. Explicit exclusions for the first release

- Phone-call recording, Zoom/meeting-bot integrations, earbud or spoken coaching.
- Diagnosing personality, MBTI type, emotion, mental state, deception, or relationship health.
- Claiming to know how the other person actually felt.
- Autonomous calendar creation or external messages without the user's final review.
- Continuous cloud recording, long-term personal profiling, and cross-session memory unless separately designed and consented to.

## 9. Build and validation loop for Claude Code

This is a bounded implementation sequence, not authorization for unattended deployment.

| Pass | Deliverable | Evidence required before next pass |
|---|---|---|
| **0. Feasibility spike** | On-device capture and live transcript for one English and one Korean sample; test speaker attribution, screen-on recording, and haptic on a table. | Real-device recordings, measured cue latency, supported locale check, and a list of failures. Stop if attribution or timing cannot support a trustworthy cue. |
| **1. Interaction prototype** | Session setup, meter idle/trigger/inspect states, manual or fixture-driven cue, end-session recap layout. | iPhone screenshots and a short real-device interaction run. Check glanceability, false vibration burden, Dynamic Type, and both languages. |
| **2. MVP pipeline** | Speech segmentation, cautious cue generation, grounded recap, action extraction, calendar editor. | Consent-based two-person sessions in both languages; review cue precision, attribution, recap provenance, and calendar data before relying on them. |
| **3. Polish** | Error and recovery states, accessibility, privacy controls, retention/deletion, app icon export, App Store materials. | Test light/dark/Increase Contrast, interruption behavior, consent indication, and deletion. The user reviews the name and final visuals before launch. |

During each pass: implement one vertical slice, record observed evidence, fix the highest-impact failure, and repeat at most three focused design iterations before asking for a product decision. Do not substitute a generated screenshot for a running app.

## 10. Open decisions for the owner

- Final product name and trademark/App Store availability. **Autunite is a working title**, not clearance.
- Exact retention period and whether any analysis may use a cloud service. The app must disclose the chosen path before real recordings are collected.
- Which iPhone and minimum iOS version to support, based on English/Korean speech availability and real-device performance.
- Whether an unrecognized second speaker should be labeled “Unknown” or handled through user correction in the recap.

## 11. Source notes

- Apple [Speech framework](https://developer.apple.com/documentation/speech/) supports live speech input; [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber) exposes locale and device availability checks. Locale support must be checked on actual targets.
- Apple [Core Haptics guidance](https://developer.apple.com/documentation/corehaptics/preparing-your-app-to-play-haptics) and [haptic design guidance](https://developer.apple.com/design/human-interface-guidelines/playing-haptics) support brief, intentional feedback; availability varies by device and state.
- Apple [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) require explicit consent and a clear indication of recording.
- Apple [EventKit guidance](https://developer.apple.com/documentation/eventkit/creating-events-and-reminders) requires user confirmation before modifying Calendar data.
