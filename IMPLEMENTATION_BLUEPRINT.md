# Autunite implementation blueprint

**Purpose:** build instructions for Claude Code. Read `INTENTIONAL.md` for product rules and `DESIGN.md` for visual rules. This file defines screens, settings, records, processing boundaries, and checks. Autunite is a working name. The visual board is a composition reference; its sample copy and “Overall” praise card are not requirements.

## 1. Product boundary

The first app is an iPhone companion for a participant-aware, in-person conversation. The user places the phone screen-up, chooses how they want to speak in this conversation, and starts recording. The app gives sparse live cues only for the user's own wording. At the end it produces a sourced recap and editable action drafts. Support English and Korean UI and speech sessions. Do not build phone-call capture, earbud coaching, personality scoring, automatic calendar writes, or background covert recording.

The two hardest unknowns are **reliable user-speaker attribution** and **useful cue latency**. Build and test those on a real iPhone before wiring a production analysis model. Until attribution is reliable, a live demonstration may use a clearly labeled manual/fixture trigger; real speech must not generate a cue attributed to the wrong person.

## 2. Information architecture and screen contract

| Screen | Required elements | User action and transition | Empty/error state |
|---|---|---|---|
| Onboarding | Purpose; participant awareness; audio/transcript processing and deletion explanation; microphone and speech permissions | Continue to setup only after permissions and acknowledgement | Explain denied permissions with Settings route; no session starts |
| Session setup | Speech language selector (English or Korean); conversation intention editor; optional presets; recording/processing disclosure; haptics on/off | Start opens live session | Empty intention requires user entry or explicit preset selection |
| Live idle | One top Recording dot + label + small waveform + timer; round segmented meter; “Listening”; compact intention row; End Session | Tap intention to edit; End Session stops capture | Speech unavailable/paused/interrupted state is visible; never imply recording continues when stopped |
| Live cue | Same live frame; needle moves in reachable upper range; one short haptic; cue card on user tap | Inspect, dismiss, or mark inaccurate; return to live idle | If analysis is delayed or uncertain, stay quiet; do not display stale cue |
| Processing | Recording stopped indicator; progress stage; retry or partial recap path | Open recap after processing | Preserve recoverable local session if analysis fails |
| Recap | Factual summary, chronological timeline, decisions, commitments, open questions, suggested actions, calendar drafts, optional wording reflection | Open source detail, edit action, review calendar draft, delete session | Empty sections say “None identified,” not invented content |
| Calendar review | Editable event title, date, time, timezone, duration, optional participants, source excerpt and uncertainty | Explicit Save to Calendar | Missing date/time blocks save until user supplies it |
| Sessions/settings | Session list, delete/export controls, UI language, default speech language, haptic preference, processing/retention disclosure | Open past recap or edit preferences | Deletion confirmation explains what is removed |

The app may be implemented as a small tab or stack navigation. The essential flow is Setup → Live → Processing → Recap → Calendar review. Keep a persistent way back to Sessions/Settings outside a live recording.

## 3. Setup fields and their meaning

### Per-session fields

| Field | Initial behavior | Used by |
|---|---|---|
| Speech language | Explicit English or Korean. Remember last choice, but show it before each start. UI language can differ. | Speech recognizer, cue and recap language |
| Conversation intention | User-written one or two sentences about desired tone and relationship, e.g. “Direct and respectful; keep my boundary clear.” | Cue comparison and wording reflection only |
| Optional preset | Starting text such as direct + respectful, collaborative + concise, or empathetic + clear. User can edit. | Prefills intention; never overrides it |
| Conversation label | Optional private title; if blank, use a neutral date label. | Session list and recap title |
| Participant acknowledgement | Explicit check before capture that other participants are aware of recording. | Start gate and audit state |

Do not require the other person's name or infer a relationship. The intention is a session-specific instruction, not a personality profile. Editing it during a session affects only future cues; retain a timestamped intention version so past cues can be explained.

### App-level preferences

| Setting | Behavior |
|---|---|
| UI language | English or Korean; default from device locale only when supported, with manual override. |
| Default speech language | English or Korean; independent from UI language. |
| Haptics | On/off; make visual cue access available either way. Expose intensity only if the hardware path supports a meaningful difference. |
| Privacy and retention | Explain whether audio, transcript, and derived summaries stay local or go to a service. Let the user inspect and delete stored sessions. Do not promise a retention period until it is implemented. |
| Analysis route | Internal capability choice (on-device or disclosed service), not a hidden user-facing toggle. Show the actual route in disclosure before collecting real recordings. |

## 4. Live meter and cue interaction

The meter is a **visual uncertainty cue**, not a calibrated measurement. Its segmented ring remains visually round. The needle travels only through the **upper reachable arc**. Fine tick marks appear only in that travel range; the lower ring segments remain as an unticked silhouette. There are no radiation units, percentages, emotional-harm scores, mineral facets, or orbit art in the live dial. The top waveform strip is the only Recording label/indicator. The report header alone gets the translucent yellow-green mineral and thin orbit with one dot.

Proposed meter states:

| State | Display | Trigger |
|---|---|---|
| Rest | Neutral upper arc highlight; needle near center; “Listening” | Recording active, no useful cue |
| Candidate, internal | No user-visible change | Completed user phrase enters analysis |
| Cue available | Short needle sweep to amber within upper arc, brief haptic if enabled, compact prompt | Evidence passes attribution and usefulness gates |
| Inspecting | Cue card shows quote, possible interpretation, why it differs from intention, one next sentence | User taps meter/prompt |
| Uncertain/interrupted | Quiet meter with state label; no haptic | Speaker, transcription, context, capture, or model is unreliable |

Trigger pipeline: microphone segment → transcript candidate → completed phrase boundary → speaker attribution → context window → compare with current intention → generate a possible reading and one alternative → confidence/usefulness gate → cue. The gate must reject or defer when speaker identity is unclear, transcription is unstable, the statement is too short or missing context, the app merely dislikes directness, or a near-duplicate cue was recently shown. Coalesce repeated warnings for one thought. Use a short configurable cooldown during testing; set the production value only from observed false-alert burden.

Cue card fields, in order:

1. **Your wording:** an exact short span from the user's speech, with its timestamp.
2. **Possible interpretation:** conditional language (“may sound…”); never state the listener's feelings as fact.
3. **Intention link:** the relevant part of the user's selected intention and why the phrasing may differ.
4. **Try next:** one short spoken sentence that keeps the user's intended point.
5. **Feedback:** Dismiss and Mark inaccurate. Feedback is local session feedback in v1, not a permanent trait.

No constant live transcript is needed on the main screen. If exposed for correction, place it behind an explicit detail action. When the phone is locked or the app is not foregrounded, do not promise the same live haptic or visible meter behavior; document observed device behavior during the feasibility pass.

## 5. Recap: every section and its record

Each asserted recap item should carry a source reference: utterance ID(s) and a timestamp span. Use an explicit status such as **supported**, **needs review**, or **suggested**. Show uncertainty rather than filling gaps. The sample image's “Overall” praise card is excluded.

| Section | What to record | Display rule |
|---|---|---|
| Header | Session title, local date, actual duration, speech language, participant labels if verified | No invented names or roles; place report-only mineral/orbit art here |
| Short summary | 2–4 factual sentences covering the purpose and outcome | Do not grade the user or say the conversation was successful without evidence |
| Topic timeline | Topic label, start/end time, 1–2 factual points, source span | Chronological; merge repeated returns to the same topic only if timeline remains clear |
| Decisions | Exact decision, who agreed if known, timestamp, source | If only proposed, place in open questions or suggestions instead |
| Commitments | Owner, action, due date if spoken, source, certainty | Separate user, other participant, and unknown owner; never assign a promise by guess |
| Open questions | Unresolved question, related topic, owner only if explicit | Do not turn uncertainty into a decision |
| Suggested next actions | Proposed task, rationale, source or “app suggestion,” editable status | Separate from agreed commitments and require user review before export |
| Calendar candidates | Event title, date, time, timezone, duration, participants if spoken, source, missing fields | Open an editable draft; save only after explicit user action |
| Wording reflection | At most a few relevant moments: original phrase, selected intention at that time, possible reading, alternative | No personality grade, emotional diagnosis, or blanket “be warmer” rule |

Suggested recap order: Summary → Timeline → Decisions → Commitments → Open questions → Suggested next actions → Calendar drafts → Wording reflection. If a section is empty, either omit it or show a concise “None identified”; choose consistently in UI review. A user must be able to open the source moment for any decision, commitment, or calendar candidate and correct an attribution before saving an external action.

## 6. Calendar draft rules

Extraction may propose a draft only from a real scheduling statement. Classify it as **explicitly agreed**, **tentative**, or **app-suggested**. Require a date, time, and purpose before enabling Save; timezone is explicit when crossing zones and otherwise derived from device timezone with a visible edit control. Duration defaults may be offered but clearly marked as defaults. Participant names are added only if the user entered them or the speech evidence is clear. The user can discard, edit, or save the draft. Ask calendar permission at save time. Never create an event when the recap first appears.

## 7. Data and processing model

Recommended local entities (names are illustrative):

| Entity | Minimum fields |
|---|---|
| Session | ID, created/ended timestamps, title, UI/speech language, consent acknowledgement, processing route, status, current intention version |
| IntentionVersion | Text, timestamp, optional preset origin |
| Utterance | ID, session ID, start/end time, text, speaker label (`user`, `other`, `unknown`), attribution confidence, transcript revision state |
| Cue | ID, source utterance IDs, intention version, original span, possible reading, alternative, trigger time, status/feedback |
| RecapItem | ID, kind, text, source utterance IDs, evidence status, editable correction fields |
| CalendarDraft | ID, linked recap item, title, date/time/timezone/duration, participants, missing fields, review/save state |

Keep audio capture, speech transcription, speaker attribution, cue analysis, recap generation, persistence, and calendar writing behind separate interfaces. This lets Claude Code start with fixtures and replace providers after the real-device spike. Persist recording and transcript state safely enough to recover after interruption, but do not retain raw audio indefinitely by accident. Define the actual retention/deletion behavior before any real user data is collected and make it visible in onboarding/settings. If using a remote analysis service, disclose the destination and transmitted data and require appropriate consent; never embed service secrets in the app.

Recommended iOS stack to validate against the chosen minimum OS: SwiftUI for screens, AVFoundation for microphone capture, Apple's Speech APIs for supported recognition, Core Haptics or supported UIKit feedback for brief pulses, a local persistence layer, and EventKit for explicit calendar saves. These are architecture candidates, not proof that English/Korean recognition, diarization, or low latency work on target devices.

## 8. Implementation order and evidence

1. **Real-device feasibility:** recording with a clear visible state; one English and one Korean session; on-device locale availability; microphone interruption; haptic on a table; speaker attribution against two voices. Record measured latency and failures. Do not feed uncertain other-speaker phrases into live coaching.
2. **UI shell with fixtures:** implement all screens and meter states with deterministic sample data. Compare screenshots to the provided board at normal size and Dynamic Type. Verify full round ring, upper-only ticks, report-only mineral/orbit, and a single top recording indicator.
3. **Live vertical slice:** connect capture → transcription → user phrase attribution → cautious cue. Keep an internal fixture switch for testing. Log cue provenance and rejection reasons without exposing private speech in routine diagnostics.
4. **Recap vertical slice:** generate and render every section using utterance source links. Test uncertain speaker/date and missing sections. Provide corrections before action export.
5. **Calendar and privacy:** editable draft, explicit save, permission request, deletion, processing disclosure, recovery after failure.
6. **Bilingual and accessibility pass:** review Korean honorifics and English copy; test Dynamic Type, VoiceOver, Reduce Motion, Increase Contrast, and haptics-off fallback.

Do not proceed from a feasibility spike to claims of reliable coaching merely because one demonstration worked. Keep observed results and remaining gaps in a short implementation report for the owner.

## 9. Acceptance checks for the first reviewable prototype

- A user can choose English or Korean, enter a session-specific intention, acknowledge recording, start and stop a visible recording session.
- With fixtures, the round dial keeps its lower ring silhouette without lower ticks; the top reachable arc has ticks; a cue briefly moves the needle and can be inspected without taking over the conversation.
- A cue references the user's actual completed phrase, acknowledges uncertainty, links to the active intention, and proposes one next sentence. Uncertain speaker attribution produces no live cue.
- The recap has separate sourced sections for topics, decisions, commitments, open questions, suggested actions, and calendar candidates. It does not present the image's “Overall” praise as a feature.
- A calendar candidate opens an editable draft and writes nothing until the user saves it.
- Mineral facets and orbit appear in the logo and report header only; the live meter contains no crystal imagery.
- Device evidence states what works in English and Korean, the observed latency and haptic behavior, and which features still use fixtures.
