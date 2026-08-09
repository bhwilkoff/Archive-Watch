# Subtitles: getting from ~9% to near-total coverage

**Status 2026-08-09.** Owner: *"I am interested in making all titles available
with subtitles, which will likely require multiple different approaches."*

## Where we actually are (measured, not estimated)

| | |
|---|---|
| items with a `captions[]` entry | **12.6%** (3,865 of 30,601) |
| of the tracks the app plays, actually working | **70%** (60 sampled) |
| → films a viewer can actually watch with subtitles | **~9%** |

The 30% failure was three defects, all fixed 2026-08-09 (see the commit and
§0 below): files that were never deployed and returned Pages' `404.html` with
HTTP 200; UTF-16 and **RAR** payloads published as `.vtt`; and no validation of
what was being published. So the real coverage problem is the **87% with no
captions at all**.

Sources today: SubSource and SubDL (keys set) plus uploader files on archive.org.
**OpenSubtitles — the largest human-subtitle database in the world — is not wired
in at all.** The tool `tools/opensubtitles_subtitles.py` exists; no workflow runs
it and no key is configured.

---

## §0 — Integrity first (DONE)

Coverage is meaningless if a track does not render, and a broken CC button reads
to the viewer as "the subtitles are broken" more loudly than an absent one does.

- decode from BYTES with BOM/UTF-16/cp1252 detection; extract ZIPs; refuse
  RAR/7z/gzip (`decode_subtitle`, shared by both writers)
- `validate_vtt` before publish: real cues, spanning the film (rejects <5 cues,
  and tracks ending before 55% or past 125% of runtime)
- a rejected track drops `captions`/`subtitleHLS` so no dead CC button remains
- `subtitles.yml`: a failed asset restore is a hard error, and a SHRUNKEN set is
  refused (the Decision-020 clobber rule — this is what silently deleted ~27% of
  the deployed files)

**Next:** re-run `free_subtitles.py` + `build_subtitle_assets.py` over the
existing captioned set to repair or drop the broken 30%.

---

## §1 — Official/human sources (no ASR): the cheapest real coverage

Human subtitles are always preferable — Decisions 039b and 043 exist because
machine transcripts of archival audio were worse than nothing.

| Source | Status | Notes |
|---|---|---|
| archive.org uploader files | live | the backbone; ~1,700 tracks |
| SubSource | live | ~2,160 tracks |
| SubDL | live | key set |
| **OpenSubtitles** | **NOT WIRED — biggest single win** | largest human DB; REST API; free tier is download-capped, so run it popularity-first and cache. Non-commercial use + attribution fits Decision 010. **Needs an owner API key.** |
| Podnapisi, Addic7ed | not evaluated | smaller; worth adding as additional providers behind the same `Provider` interface `free_subtitles.py` already has |

**Matching is the risk, not availability.** A subtitle matched by title alone
lands on the wrong cut and desyncs. Match on the item's own identity first —
`imdbID` (OpenSubtitles indexes by IMDb id, which we hold for ~47% of films) —
and let `validate_vtt`'s span check catch the rest.

---

## §2 — Apple 26/27: on-device transcription (`SpeechAnalyzer`)

iOS 26 introduced `SpeechAnalyzer` + `SpeechTranscriber`, and — decisively for
us — **tvOS 26 is a supported platform**, alongside iPadOS, macOS and visionOS.
It is on-device only, has no server path, and is designed for long-form audio,
which is exactly the failure mode `SFSpeechRecognizer` had. For a file you drive
it with `AVAudioFile` + `analyzeSequence(from:)`.

Two shapes, and they are not exclusive:

- **On demand, per title.** The viewer opens a film with no captions and taps
  "Generate captions". We already download media to `Caches` for Clip Studio
  (Decision 033), so the audio path exists. Results cache locally per
  `archiveID`.
- **Live, while playing.** An `MTAudioProcessingTap` on the player's audio feeds
  the analyzer and cues render as the film plays — no wait, no storage.

**This reverses part of Decision 039b and must be done on the owner's terms.**
That ban was specifically about whisper.cpp hallucinating coherent-but-wrong
dialogue on poor archival audio, which is worse than silence. What changed:
SpeechAnalyzer is a materially stronger engine, and running it per-viewer,
opt-in, clearly labelled "auto-generated" changes the contract — the viewer
knows what they are getting. What has NOT changed: bad audio still produces
confident nonsense, so a quality gate is mandatory (§4).

---

## §3 — Android: the system already does this

There is **no public Android API to transcribe an arbitrary audio file
on-device**. `SpeechRecognizer.createOnDeviceSpeechRecognizer()` (API 33+) forces
on-device recognition but is a microphone pipeline, not a file/stream one — which
is why ANDROID-DESIGN §4.8 already records auto-captions as deferred there.

But **Live Caption (Android 10+) captions media playing on the device**,
including our player, entirely on-device, using Google's own model. It is a
system accessibility feature the user enables — no API, no permission, and it
works with Archive Watch today.

So Android's prong is **discoverability, not engineering**: surface it where a
title has no captions ("No subtitles for this film — Android's Live Caption can
caption it live"), with a deep link to
`Settings.ACTION_ACCESSIBILITY_SETTINGS`. Cheap, honest, and it uses a better
engine than anything we would ship.

Android also gets everything from §4 for free.

---

## §4 — Central generation on macOS-26 runners (serves EVERY platform)

The prong that actually closes the gap for Android, web, and older Apple OSes:
run `SpeechTranscriber` in CI on GitHub's **macOS 26 runners** (free for this
public repo) and publish the results as ordinary `captions[]` — the same path
SubSource output takes. Every client consumes them with no app change.

This is Decision 039a's sharded-runner design with a much better engine. Its
lesson stands: **scale by adding shards, never by raising workers on one
machine.**

**The quality gate is the whole ballgame**, and it is what 039b lacked. It is
built and measured (`tools/caption_quality.py`), and the measurement produced one
result that changes the plan — see "the limit" below.

- reject on **repetition** — the hallucination signature is a low unique/total
  token ratio and repeated n-grams ("ALRIGHT ALRIGHT ALRIGHT", "why why why")
- reject on **coverage** — a transcript whose cues span far less than the runtime
  means the recognizer gave up (`validate_vtt` already does this)
- reject on **confidence**, where the API exposes it per result
- **never** transcribe a title flagged `isSilentFilm` — Decision 043's exact
  failure was fabricated dialogue over silent films
- label the track "English (auto-generated)" and sort it BELOW any human track

### What the gate actually catches (measured, both directions)

The first version used unique/total token ratio and **failed both ways**: real
human subtitles for *His Girl Friday* scored 0.126 while the known-bad *White
Zombie* ASR scored 0.292 — type-token ratio falls with LENGTH, so a long rich
transcript looks worse than a short empty one. It is not a quality measure.

What separates cleanly on the same real files is DENSITY — a recognizer failing
on poor audio goes sparse rather than filling the film with nonsense:

| file | words/min | cues/min | verdict |
|---|---|---|---|
| White Zombie (archive ASR) | 14 | 3.0 | REJECT |
| Carnival of Souls (archive ASR) | 49 | 8.8 | REJECT |
| His Girl Friday (human) | 187 | 38.2 | ACCEPT |
| The Stranger (human) | 102 | 23.6 | ACCEPT |

### THE LIMIT — read this before approving prong 5

**A transcript that is FLUENT AND WRONG is not detectable from the text.** White
Zombie's ASR — the file that got auto-captions banned — reads as ordinary English
that simply is not what the film says. It happens to be caught here because it is
also sparse, but nothing in the text would have revealed the error if the
recognizer had been confidently verbose. No lexical statistic can.

So the defence cannot be text statistics alone. It has to be:
1. **the recognizer's own confidence** — SpeechAnalyzer reports it; whisper.cpp
   effectively did not, which is a real difference between 039b's attempt and this one;
2. **an audio-suitability precheck** — never transcribe an item flagged
   `isSilentFilm`, and skip tracks with no speech energy (ffmpeg VAD), which is
   how "fabricated dialogue over a silent film" is prevented rather than detected;
3. **labelling** — "auto-generated", ranked below any human track, so the viewer
   knows what they are reading.

Two bad samples is also not a threshold study. Before prong 5 runs at scale, the
gate should be calibrated against a larger archive-ASR corpus (thousands of
`.asr.srt` files are still on archive.org, free to fetch) and spot-checked for
false positives on genuinely quiet films, which are the population most at risk
of being wrongly rejected.

---

## Recommended order

1. **§0 re-run** — repair/drop the broken 30%. No decisions needed. *(engineering)*
2. **OpenSubtitles** — the largest coverage win available without ASR.
   *(needs an owner API key)*
3. **Android Live Caption discoverability** — near-zero cost, real coverage today.
   *(engineering)*
4. **Apple on-device, opt-in** — tvOS/iOS/macOS 26+, per-title, clearly labelled.
   *(needs the owner to accept a partial reversal of Decision 039b)*
5. **Central macOS-26 generation** behind the §4 quality gate — the long tail,
   for every platform. *(largest build; do last, once the gate is proven on §4)*

Sources: [SpeechAnalyzer platform availability + `analyzeSequence`](https://www.theswift.dev/posts/transcribe-audio-with-speechanalyzer-in-swift/) ·
[SpeechAnalyzer vs SFSpeechRecognizer](https://blakecrosley.com/blog/speech-framework-vs-sfspeechrecognizer) ·
[Android Live Caption captions on-device media](https://support.google.com/accessibility/android/answer/9350862) ·
[how Live Caption works on-device](https://www.androidauthority.com/how-live-caption-works-android-10-1048376/) ·
[Android on-device SpeechRecognizer](https://picovoice.ai/blog/android-speech-recognition/)

---

## §6 — The OpenSubtitles API key (OWNER, one-time, free)

The app needs ONE Api-Key. It identifies the APPLICATION, ships in the bundle,
and the viewer never sees it. It is **not** where the download quota lives:

| limit | scope | notes |
|---|---|---|
| **downloads** | **per signed-in user** | each viewer's own allowance; the API reports it as `allowed_downloads` and the app displays that rather than a hardcoded number |
| request rate | per Api-Key (shared) | ~1–5 requests/**second**; 429 + `x-ratelimit-*`. Handled with token reuse (~20h) and Retry-After backoff |

So one shared key is fine, and viewers still only enter a username and password.

### Getting it

1. Sign in (or register free) at **https://www.opensubtitles.com**
2. Profile → **API Consumers** → **New Consumer**
3. Name it (e.g. "Archive Watch"), submit → it issues an **Api-Key** string

### Giving it to the app

It goes where every other key in this project goes — `Secrets.xcconfig` at the
repo root, which is **gitignored** and already holds `TMDB_BEARER_TOKEN`,
`OMDB_KEY`, `FANART_TV_KEY`, `THETVDB_API_KEY`. Add one line:

```
OPENSUBTITLES_API_KEY = <the key>
```

`AppVersion.xcconfig` does `#include? "Secrets.xcconfig"`, both Info.plists now
carry `OPENSUBTITLES_API_KEY = $(OPENSUBTITLES_API_KEY)`, and
`SubtitleAccount.apiKey` reads it from the bundle — the same path
`TMDbClient` uses. **Do not paste the key into chat or a commit.**

⚠️ **The cloud App Store build will not have it.** `appstore-build.yml` checks
out a fresh tree, and `Secrets.xcconfig` is gitignored — which means the App
Store builds have never carried the TMDb key either, and subtitle search would
be dark in shipped builds for the same reason. To ship it, add the key as a
GitHub repo secret and have the workflow write `Secrets.xcconfig` before
building. Worth doing for TMDB_BEARER_TOKEN at the same time.

Until a key exists the feature is simply absent: `SubtitleAccount.isAvailable`
is false and Settings says so rather than offering a sign-in that cannot work.
