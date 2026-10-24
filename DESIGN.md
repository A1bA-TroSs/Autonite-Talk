---
version: alpha
name: Autunite
colors:
  primary: "#C7DF70"
  on-primary: "#1A2B22"
  live-background: "#1A2B22"
  live-surface: "#24382C"
  live-text: "#F3F1E7"
  live-muted-text: "#CCD2C5"
  report-background: "#F7F5EE"
  report-surface: "#FFFFFF"
  report-text: "#1D2920"
typography:
  body-md:
    fontFamily: system
    fontSize: 17px
    fontWeight: 400
    lineHeight: 1.4
  headline-lg:
    fontFamily: system
    fontSize: 32px
    fontWeight: 650
    lineHeight: 1.12
rounded:
  card: 16px
  control: 14px
spacing:
  sm: 8px
  md: 16px
  lg: 24px
components:
  live-page:
    backgroundColor: "{colors.live-background}"
    textColor: "{colors.live-text}"
    typography: "{typography.body-md}"
  meter:
    backgroundColor: "{colors.live-surface}"
    textColor: "{colors.live-muted-text}"
    rounded: "{rounded.card}"
  cue-card:
    backgroundColor: "{colors.live-surface}"
    textColor: "{colors.live-text}"
    rounded: "{rounded.card}"
    padding: "{spacing.md}"
  recap-page:
    backgroundColor: "{colors.report-background}"
    textColor: "{colors.report-text}"
    typography: "{typography.body-md}"
  recap-card:
    backgroundColor: "{colors.report-surface}"
    textColor: "{colors.report-text}"
    rounded: "{rounded.card}"
    padding: "{spacing.lg}"
  primary-button:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.control}"
    padding: "{spacing.sm}"
  screen-title:
    textColor: "{colors.live-text}"
    typography: "{typography.headline-lg}"
---

# Autunite visual and interaction design

## Overview

- **Subject:** an iPhone beside a face-to-face conversation, quietly helping the user match their chosen way of speaking.
- **Metaphor:** a calibrated Geiger counter. It registers a *possible wording mismatch*, not radiation, emotional injury, or a person's character.
- **Personality:** attentive rather than intrusive; precise rather than clinical; approachable rather than soft or childish.
- **Materials:** muted moss-green instrument body, ivory paper recap, chartreuse autunite facets reserved for the brand mark, and a fine off-white orbit line.

The layout should look like a real iPhone recording and notes app. The meter is the one signature component. Mineral imagery belongs in the **logo and report header illustration only**, not within the live meter or as decorative live-screen texture.

## Name and logo

**Working name: Autunite.** It is a real uranium-bearing mineral and has a yellow-green fluorescence that connects naturally to the detection metaphor. Other researched candidates are **Torbernite** (green copper-uranium mineral) and **Carnotite** (yellow uranium-vanadium mineral). A preliminary web and indexed App Store search found no obvious conversation app with these exact names; that is not trademark, domain, or App Store clearance. The owner chooses the final name before release. Geological reference: [USGS mineral table](https://pubs.usgs.gov/bul/1064/report.pdf) and [USGS description of autunite and torbernite](https://pubs.usgs.gov/tei/0229/report.pdf).

The approved concept in `assets/concepts/autunite-icon-approved-concept.png` has these invariants:

1. **Two overlapping speech bubbles**, each still legible as a bubble.
2. A few broad yellow-green mineral facets and restrained gradation **inside** those bubbles.
3. **One thin orbit and one orbit dot** around the pair, echoing the user's FoolsGold and Iolite marks in `assets/references/`.
4. Dark background and a readable silhouette at small iPhone icon sizes.

Do not substitute a standalone mineral cluster, literal radiation trefoil, microphone, starburst, or text mark. The supplied bitmap is an approved *concept*. For production, recreate or clean it for 1024px square export without baking in an iOS corner mask; inspect at 48px and in light/dark contexts.

## Screen architecture

| Screen | Main content | Primary action |
|---|---|---|
| Welcome / permissions | What recording captures, participant awareness, processing and deletion explanation | Continue to setup |
| Session setup | English/Korean speech choice; conversation intention written by user; optional short presets | Start session |
| Live idle | Recording strip with compact waveform, calibrated meter at rest, “Listening,” intention row, elapsed time | End Session |
| Live cue | Same frame; one meter movement and haptic; tapping reveals exact phrase, possible reading, mismatch with intention, one next sentence | Dismiss / mark inaccurate |
| Ending / processing | Recording stopped state, progress and recovery if processing fails | View recap |
| Recap | Factual summary, topic timeline, decisions, commitments, open questions, next actions | Review action |
| Calendar draft | Editable event details, source line from conversation, uncertainty fields | Save in Calendar |
| Sessions / settings | Past sessions, deletion, locale, haptic strength/on-off, processing disclosure | Start new session |

### Live idle

Use the softened green and layout in `assets/concepts/autunite-ui-final-reference.png`. Avoid a near-black green that makes the app feel severe.

At the top, show the recording state clearly, a small waveform strip, and elapsed time. The waveform communicates that capture is active; it is not a transcript. Below, use a segmented **round meter** with a slim indicator inspired by a measuring instrument. Keep the lower ring segments to preserve the circular silhouette. Place fine tick marks **only along the upper arc that the needle can reach**; the lower arc has no tick marks. Its center can say **Listening** with a small line explaining that a cue will appear when useful. Keep the selected conversation intention in a compact row near the bottom. The End Session control is large and unmistakable. The top strip is the single recording indicator; do not repeat “Recording” or add another recording panel below the meter.

Do **not** put mineral shards, crystal images, gradients, or decorative triangles inside or around the live meter. Do not make the meter look like scientific radiation output: no sieverts, counts-per-minute, percentages, or fake precision.

### Live cue

The meter briefly moves toward an amber segment. A short haptic pulse fires if the app is foregrounded and haptics are enabled. The user may inspect the cue by tapping. The cue card contains, in this order:

1. **Your wording:** a short accurate quote.
2. **Possible reading:** a conditional explanation, never certainty about the listener's feelings.
3. **Why it matters here:** how it differs from the user's chosen intention.
4. **Try next:** one sentence preserving the user's point.

The visual reference is illustrative. Its sample text is not a fixed product response. Keep the card to one viewport, avoid multiple simultaneous cues, and do not let a haptic startle or shame the user. The meter rests again after a short moment; the cue remains available until dismissed or superseded.

### Recap and follow-up

Switch to a light warm-ivory reading surface after the session. Use the calmer report composition in the visual reference: title, concise summary, topic timeline, action rows, and a calendar draft. Restore the earlier report's **restrained translucent yellow-green mineral facets with one thin gold orbit and dot in the upper-right header**. This is report-only artwork and must not enter the live meter. The generated board includes sample report text; **do not implement the “Overall” personality praise card**. The actual recap must be factual, sourced from the conversation, and explicit about uncertainty. Each action row says whether it was agreed aloud or suggested by the app. Calendar review opens a native editor or equally clear review screen; save only on user action.

## Color roles, not decoration

The front-matter colors are **proposed starting values**. The visual images take precedence for mood, and accessibility testing may require adjustments. Use semantic roles and variants for light, dark, and increased contrast; do not hard-code raw colors throughout SwiftUI views.

- **Moss green:** live background and surfaces. It should feel calmer than the later near-black green board.
- **Off-white:** live text and orbit line.
- **Chartreuse:** brand/mineral cue and the resting meter's small active area. It is not a universal success score.
- **Amber:** a live wording cue. Pair with a label and needle movement so color is never the only signal.
- **Warm ivory:** recap reading surface.

## Type, motion, and accessibility

- Use native iOS text styles and Dynamic Type. Korean copy needs enough line height and flexible cards; do not freeze English-only widths.
- Touch targets at least 44 by 44 points; respect safe areas and Increase Contrast.
- Support Reduce Motion: when enabled, move the meter instantly rather than animating a sweep. Keep transitions brief otherwise.
- Provide visual cue access if vibration is off or unavailable. Apple notes haptics vary by device and app state; test the foreground, screen-up-on-table use case on hardware. [Apple haptics guidance](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
- The recording indicator remains visible. The screen is placed where the other participant may see it, so live cue text should not reveal an unnecessary personal profile or private inference.

## Draft microcopy to localize

| Intent | English | Korean draft |
|---|---|---|
| Rest | Listening | 듣고 있어요 |
| Cue | Check this wording | 이 표현을 확인해 보세요 |
| Interpretation | This may sound dismissive. | 이 말은 상대의 생각을 일축하는 듯 들릴 수 있어요. |
| Action | Review calendar draft | 일정 초안 확인 |

These are design drafts, not professionally reviewed translations. Review Korean register, honorifics, and tone with native speakers before shipping.

## Visual references and precedence

1. `assets/concepts/autunite-icon-approved-concept.png` — approved logo composition.
2. `assets/concepts/autunite-ui-final-reference.png` — current screen direction: soft green, top recording waveform, round segmented meter with ticks only on its reachable upper arc, and a light recap with report-only mineral/orbit artwork.
3. `assets/references/foolsgold-original.png` and `assets/references/iolite-original.png` — existing mineral-logo family. Do not copy their specific stones into this app.
4. `INTENTIONAL.md` — source of truth for behavior and claims. If generated-image text conflicts with it, follow `INTENTIONAL.md`.

Before translating the board into SwiftUI, get a visual review of the first running iPhone screens. The illustration is a target for composition and mood, not proof that the app works.
