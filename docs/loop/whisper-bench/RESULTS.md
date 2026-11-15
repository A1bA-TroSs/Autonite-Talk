# WhisperKit Korean bench (Mac, 2026-11-16)

Run by the Mac session for the YounLoop run `autunite-reach`; committed as received.

Setup:
- Machine and tool: Apple M4 Mac, `whisperkit-cli` 1.1.1 (Homebrew, MIT), `--language ko`.
- Clip set "ko20": 20 Korean phrases from `say -v Yuna` at rates 150, 190 and 230, 16 kHz mono, mean 1.85 s each. Truth is in `phrases.tsv`; its voice column is unused, and every clip is Yuna.
- What the set covers: 9 swear lines (some mid-sentence, one repeated, one double), 7 polite endings and 13 casual endings.
- Not recorded: Danny was not recorded. Synthetic speech is cleaner than a table-distance microphone, so these are upper bounds on accuracy.
- Scoring: `score.py <model>` checks each line's expected swear in Whisper's text, with spelling variants (씨발 ⇔ 시발 and so on). It is not the app's lexicon.
- Spaces: the bench ignores spaces only to find a swear it knows is present. The app must not do that: "세 시 발표" would read as 시발. The app lists the spaced variants instead.

| Model (WhisperKit variant) | Folder on disk | Swear recall | False swears | Ending accuracy | Warm seconds per clip, one at a time (mean / max) | Real-time factor |
|---|---|---|---|---|---|---|
| tiny (`openai_whisper-tiny`) | 73 MB | 3/9 = 0.33 | 0 | 20/20 | not re-run serially | — |
| base (`openai_whisper-base`) | 143 MB | 3/9 = 0.33 | 0 | 20/20 | not re-run serially | — |
| small (`openai_whisper-small`) | 479 MB | 7/9 = 0.78 | 0 | 20/20 | 0.34 / 0.43 | 0.19 |
| large-v3 turbo (`openai_whisper-large-v3-v20240930_turbo`) | 1.5 GB | 8/9 = 0.89 | 0 | 20/20 | 0.73 / 0.83 | 0.40 |
| large-v3 turbo 4-bit (`openai_whisper-large-v3-v20240930_626MB`), the app's "accurate" option | 606 MB | 8/9 = 0.89 (app word list) | not reported | not reported | 1.11 / 1.20 | 0.60 |

Timing method:
- Times are WhisperKit's per-file `fullPipeline`, from one process over all 20 clips with `--concurrent-worker-count 1`.
- `fullPipeline` excludes model loading: `modelLoading` is reported once per process, 1.1 s for small and 168 s for turbo's first Core ML compile.
- The first run used the default of parallel workers. Contention inflated per-file times to 1.02 s (small) and 2.60 s (turbo), so those numbers are void.
- The serial run produced identical transcripts.

Folder sizes are `du -sh` of the downloaded Core ML folders. The App Store-style download size may be smaller.

## Swear lines per model

- **turbo:** misses only p19 "좆된다" (heard as "존댄다"). It gets "존나 … 존나" twice and "개 짜증나네".
- **small:** misses p06 "존나" (heard as "존다") and p19.
- **base:** misses "존나" as "좋은а", "병신" as "경신", "닥쳐" as "다쳐" and "꺼져" as "거저". It also outputs stray non-Korean tokens (Cyrillic "а" and Japanese "んだ").
- **tiny:** worse than base, with garbled forms such as "깨맛증다래" and "평신".

## Against rubric M7

M7 requires all three: recall ≥ 0.9, ending accuracy ≥ 0.85 and under 1.0 s per clip on this Mac.

- **No model passes M7.** Turbo passes time (0.73 s) and endings but misses recall: 0.89, one clip (p19 좆된다) short of 0.9. Small passes time (0.34 s) but has 0.78 recall. Base and tiny miss two thirds of the swears.
- **Ending accuracy of 1.00 is weak evidence.** The scorer only checks the final -요/-니다/-니까/-세요/-죠, and clean TTS endings are easy.

## What this means for the app (inference unless stated)

- **Whisper as a re-pass keeps up with talk on an M4:** turbo at 0.40× real time, small at 0.19×.
- **An A16 is slower than an M4 (inference).** If it is 2-3× slower, turbo would run near or above real time on an iPhone 15 during continuous speech. Small would keep up.
- **Whisper still stays off the live cue path.** Apple's first result arrives in 0.3-0.5 s, and the voice gate already waits for evidence.
- **Recommended:**
  - small as the in-session default (479 MB);
  - turbo as the accurate option, which may finish its re-reads after the session ends (queued);
  - base not used for swear correction: it misheard the swears it missed as harmless words (경신, 다쳐, 거저) and adds stray tokens.
- **Unverified:** iPhone 15 timings. They need the on-device self-test, or Danny's phone.

## App word-list re-score (Mac session, 2026-11-16)

The same Whisper transcripts, scored with a Python port of the app's `WordChoiceReader.hits` at commit ac39882 instead of `score.py`'s variants. Numbers as reported by the Mac session.

| Model | Swear recall with the app's word list |
|---|---|
| tiny | 3/9 = 0.33 |
| base | 4/9 = 0.44 |
| small | 8/9 = 0.89 |
| large-v3 turbo (1.5 GB) | 8/9 = 0.89 |
| large-v3 turbo 4-bit (606 MB) | 8/9 = 0.89 |

- **Every model misses p19 "좆된다".** Whisper writes "존댄다" (small, 4-bit turbo) or "좋댄다" (turbo). The TTS voice may have mispronounced it.
- **"존댄다" is not added to the word list.** It is also the contraction of 존대한다 ("uses honorifics"), which comes up in exactly the conversations Autunite is for, so it would cue falsely.
- **Small now catches p06** through "어이없", not through "존나".
- **Every model flags p08 "그건 니가 알아서 해"** through "알아서 해". That is a deliberate entry, but it shows the entry fires on neutral phrasing.
- **4-bit turbo is slower than the 1.5 GB build on the M4:** 1.11 s mean per 1.85 s clip against 0.73 s, likely from 4-bit dequantisation (inference). Its first Core ML compile takes about 3.5 min. It gains no recall over small on this set and takes about 3× the time.
- **M7 still fails for every model** at 0.89, one clip short of 0.9.

## Reproduce

```
say -v Yuna -r {150,190,230} ...   # one clip per line of phrases.tsv
afconvert -f WAVE -d LEI16@16000 ...
whisperkit-cli transcribe --model <m> --language ko --audio-folder ko20 --concurrent-worker-count 1 --report --report-path rep-<m>
python3 score.py <m>
```

## Vocabulary prompt test (2026-11-16, on the cloud session's request)

The prompt was the app's single-word Korean harsh entries in source order, joined with ", ", passed as `--prompt` (whisperkit-cli 1.1.1). It was not chosen from the bench. Same ko20 clips, warm, one worker.

| Model | Prompt | Recall (expected-word / app lexicon) | False swears | Ending accuracy | Warm s per clip, mean / max |
|---|---|---|---|---|---|
| small | none | 0.78 / 0.89 | 0 | 20/20 | 0.34 / 0.43 |
| small | lexicon | 0.89 / 0.89 | 0 | 20/20 | 1.98 / 2.07 |
| 626MB | none | 0.89 / 0.89 | 0 | 20/20 | 1.11 / 1.20 |
| 626MB | lexicon | 0.89 / 0.89 | 0 | 20/20 | 2.67 / 2.74 |

**Verdict: drop the prompt.**
- It doesn't recover p19 on either model. Small still writes "좋댄다" and 626MB "존댄다".
- It adds no false swears. Both scorers still flag only p08 "알아서 해", the app's own deliberate entry.
- It makes small about 6× slower (0.34 → 1.98 s) and 626MB about 2.4× slower (1.11 → 2.67 s), over M7's 1.0 s bound.
- It damaged small's ordinary text:
  - p05 "아니라요" became "아니다요"
  - p13 "좀" became "종"
  - p15 "과제" became "바제"
  - p17 "아 씨 짜증나" became "씨따증나"
- The one gain, p06 "존나" (expected-word recall 0.78 → 0.89 on small), the app lexicon already caught through "어이없".
- M7 stays a measured gap: 8/9 swear lines.
