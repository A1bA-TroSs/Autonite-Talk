decision: go

# Pass 0 decision (2026-11-01)

Danny called go on 2026-11-01 in the Autunite build thread. He said voice recognition works well enough for now. The next risk is word-level reading: whether the app hears his words correctly and judges them correctly. That can only be learned in real use, so the work moves to the main feature (Pass 1).

## Evidence against the gate (`docs/PASS0_FEASIBILITY.md`)

| Gate item | Evidence | Status |
|---|---|---|
| Other called Me, other voice alone | 2026-11-01 run with voice verification: 0 of 11 pieces called Me while the podcast played alone (52–127 s). Before verification, the 2026-10-29 run had the podcast called Me at 0.84–1.00. | Judged from content; **no rows tagged** |
| Other called Me, user talking over a podcast | 2 pieces called Me: 127.7 s at match 0.70 and 166.6 s at 0.58. Who spoke at 127–178 s is unconfirmed. The threshold has since been raised to 0.65 (1edf877), which would hold back the 0.58 piece. | **Open** |
| Coverage | Solo speech: every line called Me (match 0.69–0.82). Talking over the podcast: about 14% of the time committed, the rest held back. | Safe but sparse under overlap |
| Latency | Attribution delay about 0.8–1.3 s after the end of speech | Acceptable for Pass 0 |
| Haptic face-up while recording | Danny felt the pulses, but 0 trials were recorded because the app needed a separate tap (fixed in 4f882e4). The cue is now a 0.6 s rising buzz (a2d4d03). | **Not recorded** |
| Both locales | ko-KR and en-US supported and installed on iPhone15,4, iOS 26.7.2 | Pass |

## Carried into Pass 1

- **Threshold.** Set the no-false-Me threshold from tagged runs (rule of three) before relying on live cues (AC8).
- **Wrong-cue marks.** Collect "mark inaccurate" from the cue card (AC13) to measure word-level misreadings in real use.
- **Haptic.** Record haptic trials on the next device run.
- **Untested.** English speech, and a second live person.
