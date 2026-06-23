# Creation Studio — Subtitle Search (Feature 8) + Supercut Assembler (Feature 9)

*Research brief — 2026-06-22. Author: research pass for the macOS-native "Creation
Studio." Scope: the flagship differentiator — **type a sentence, the app finds the
individual words/phrases spoken across catalog videos and assembles a supercut of
different people saying your custom text** — plus the searchable subtitle index
(feature 8) that powers it. Cites sources inline. Binding constraints honored:
Apple frameworks in-app, CLI subprocess tools (ffmpeg + ML CLIs) OK on Mac, no
third-party Swift packages in-app, and the learning-orientation guardrail
(Decision 033): the result must drop into an EDITABLE timeline, never a one-tap
locked export.*

---

## 0. Where this sits in the existing system

Archive Watch already harvests subtitles (Decision 039 / 039b):

- `tools/enrich_subtitles.py` records archive.org's own ASR/uploader caption files
  on each item as an additive `captions[]` field (`{lang, label, format, url,
  source}`), `captionsChecked` marks resumable progress.
- `tools/build_subtitle_assets.py` converts each item's SRT → **WebVTT** and writes
  `subs/<id>/en.vtt` to GitHub Pages (CORS-served), plus a single-segment HLS set;
  it records `captions[].vttURL` (web) and `subtitleHLS` (Apple) on the item.
- The Swift model (`Catalog.swift`) carries `captions: [Caption]?` and
  `subtitleHLS: String?`. The viewer serves cues at
  `archivewatch.org/subs/<id>/en.vtt`.
- Whisper auto-captioning was **abandoned** (Decision 039b) because old/music-heavy
  audio hallucinated coherent-but-wrong text. Subtitle coverage is now archive.org
  ASR + OpenSubtitles only.

**The gap this brief addresses:** those VTT cues are **line-level** — one
`00:01:04.120 → 00:01:07.300` cue spans an entire spoken line. Feature 8 (find the
scene/video that says a phrase) works directly on line-level cues. **Feature 9 (cut
a single word out of one person's mouth and stitch a new sentence) does not** — it
needs **word-level** start/end timestamps, which our caption files do not carry.
This brief's central recommendation is how to add a word-timing layer cheaply on
the Mac without reintroducing the 039b hallucination problem.

---

## 1. Prior art — videogrep, the supercut genre, Whisper supercuts

### 1.1 videogrep (Sam Lavigne) — the canonical implementation

**videogrep** (`github.com/antiboredom/videogrep`) is the 10-year-proven reference:
"searches through dialog in video files and makes 'supercuts' based on what it
finds," parsing subtitle timestamps and splicing with `moviepy` + ffmpeg
([repo](https://github.com/antiboredom/videogrep);
[lav.io design post](https://lav.io/2014/06/videogrep-automatic-supercuts-with-python/)).

- **Input:** `.srt`, `.vtt`, or `.json` transcripts named to match the video; if
  none exists, `--transcribe` runs offline STT via **Vosk** and emits word-timed
  JSON ([tutorial](https://lav.io/notes/videogrep-tutorial/)).
- **The load-bearing distinction — `--search-type`:**
  - `sentence` (default): regex-matches the query against each cue's text and
    returns **that whole cue's** start/end. A search for "fire" yields the entire
    line "put out the fire before dark," not the word.
  - `fragment`: "Generates clips containing the exact word or phrase of your search
    query" — **but only works when the transcript carries per-word timestamps.** The
    code guards on `if "words" not in transcript[0]`; plain `.srt` (and most
    archive.org ASR) lacks word timing, so fragment mode silently can't operate
    ([videogrep.py source](https://github.com/antiboredom/videogrep/blob/master/videogrep/videogrep.py)).
- **`--padding`:** "Padding in seconds to add to the start and end of each clip,"
  default `0`. It exists precisely because hard cuts at cue boundaries clip word
  onsets/tails and sound abrupt.
- **Export:** concatenated mp4/mp3, individual clips, `.m3u`/`.edl`, WebVTT, and
  **`.xml`/`.fcpxml` NLE timelines** for Final Cut / Premiere / Resolve — i.e. it
  can hand cut decisions to an editor rather than render a locked file.
- **Lavigne's own caveat:** "The accuracy of the edits is completely reliant on the
  accuracy of the subtitle tracks." Part-of-speech pattern matching existed in old
  versions and was **removed** as unused.

**What videogrep does well:** validates the whole concept; the cue→ffmpeg splice
pipeline; NLE-timeline export (a model for our editable-result guardrail). **Its
limits, which are exactly our design problem:** (a) default `sentence` mode is
cue-level — can't isolate a word; (b) `fragment` (word) mode needs word-timed
transcripts we don't have; (c) edit quality is bounded by subtitle accuracy; (d) no
audio-artifact smoothing beyond raw padding.

### 1.2 The supercut genre — why word-level matters

A supercut "obsessively isolates a single element... an action, a word or phrase"
into a rhythmic montage (term coined by Andy Baio, 2008)
([Wikipedia](https://en.wikipedia.org/wiki/Supercut);
[Know Your Meme](https://knowyourmeme.com/memes/supercut)). For "different people
say **my** sentence," phrase search alone is insufficient — it can only find
sentences the source already spoke. Constructing a sentence the source **never said**
requires cutting and re-sequencing at the **individual-word** boundary (pull "I" from
one film, "love" from another, "this" from a third). This is the **Bad Lip Reading /
Songify** recombination mechanic, where the comedic payoff *is* the seams — but the
more accurate the per-word timing, the more convincing (or controllably absurd) the
constructed utterance. The audio-cut artifact (clipped onsets, prosody jumps) is the
genre's permanent quality frontier, mitigated but never eliminated.

### 1.3 yt-dlp + Whisper / WhisperX supercuts

The modern pipeline replaces Vosk with **Whisper**: pull media + auto-captions with
`yt-dlp --write-auto-sub`, or transcribe locally. The decisive upgrade for
word-level supercuts is **WhisperX** (`github.com/m-bain/whisperx`), which adds
"accurate word-level timestamps via forced alignment" using a wav2vec2 phoneme model
on top of Whisper ([repo](https://github.com/m-bain/whisperx);
[Interspeech 2023 paper](https://www.isca-archive.org/interspeech_2023/bain23_interspeech.pdf)).
Practitioners export the per-word JSON and cut on those boundaries
([Sacha Chua, word-level editing](https://sachachua.com/blog/2024/09/using-whisperx-to-get-word-level-timestamps-for-audio-editing-with-emacs-and-subed-record/)).
**Key limit:** words without dictionary characters ("2014.", "£13.60") "cannot be
aligned and therefore are not given a timing" — numerics/symbols drop out.
WhisperX is **GPU-dependent**, which contradicts our Mac-native, no-CUDA goal.

---

## 2. The hard problem — word-level timing

Line-level cues give the **transcript text** but not per-word boundaries. We need,
per word: `archiveID`, the word string (normalized), `start`/`end` seconds, and
ideally a confidence. Two families solve this:

- **Forced alignment** (text → audio): we already have the line text, so this is the
  *easier, hallucination-proof* path — the word sequence is fixed; the aligner only
  decides where each known word falls.
- **Recognition** (audio → text + timing): re-transcribes from scratch; can emit
  word timing directly but risks inventing words on poor audio (the 039b failure).

### 2.1 Option matrix

| Option | Word timing? | Needs transcript? | On-device | Burden / risk |
|---|---|---|---|---|
| **WhisperX** | Yes (wav2vec2 align) | No (transcribes) | Local but **GPU** | PyTorch+CUDA; drops numerics; GPU contradicts goal |
| **Montreal Forced Aligner (MFA)** | Yes — **phone-level** (gold) | **Yes** (+ pron. dict) | Local, CPU | Kaldi/Conda + dictionary; OOV needs G2P; **won't hallucinate** (sequence fixed) |
| **aeneas** | Yes (fragment = word) | **Yes** | Local, CPU, light | DTW vs TTS audio; lower accuracy on music/noise; AGPL (pipeline-only OK) |
| **gentle** | Yes (word+phone) | Yes | Local | **Unmaintained since 2023** — avoid as primary |
| **whisper.cpp `--dtw`** | Partial (token DTW) | No | CPU/Metal | Timing "consistently off" per maintainers — avoid as primary |
| **SFSpeechRecognizer** | ~Yes (segment≈phrase, often word) | No | Yes | ~1-min/request cap, legacy model weak on old audio |
| **SpeechTranscriber (macOS 26)** | **Yes — `audioTimeRange` per run** | No | **Yes, native** | macOS 26 + Apple-Silicon; recognition → hallucination risk on bad audio |

Sources: [WhisperX](https://github.com/m-bain/whisperx) ·
[MFA docs](https://montreal-forced-aligner.readthedocs.io/en/latest/user_guide/index.html)
+ [MFA Interspeech paper](https://montrealcorpustools.github.io/Montreal-Forced-Aligner/images/MFA_paper_Interspeech2017.pdf) ·
[aeneas](https://github.com/readbeyond/aeneas) ·
gentle (`github.com/lowerquality/gentle`, last release 2023-03) ·
[whisper.cpp discussion #2307](https://github.com/ggml-org/whisper.cpp/discussions/2307) ·
[SFTranscriptionSegment](https://developer.apple.com/documentation/speech/sftranscriptionsegment) ·
[SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber).

### 2.2 The Apple-native advantage — SpeechTranscriber / SpeechAnalyzer (macOS 26)

The new `SpeechAnalyzer` + `SpeechTranscriber` stack (WWDC25 session 277, iOS 26 /
macOS 26) is the Mac differentiator and emits **word-level timing natively**:

```swift
let transcriber = SpeechTranscriber(
    locale: Locale(identifier: "en_US"),
    transcriptionOptions: [],
    reportingOptions: [],            // batch: skip .volatileResults
    attributeOptions: [.audioTimeRange])     // ← per-word CMTimeRange
let analyzer = SpeechAnalyzer(modules: [transcriber])

let file = try AVAudioFile(forReading: audioURL)
if let last = try await analyzer.analyzeSequence(from: file) {
    try await analyzer.finalizeAndFinish(through: last)
}
for try await result in transcriber.results where result.isFinal {
    for run in result.text.runs {
        if let r = run.audioTimeRange {            // CMTimeRange
            emit(word: String(result.text[run.range].characters),
                 start: r.start.seconds, end: r.end.seconds)
        }
    }
}
```

- **Word timing confirmed:** with `attributeOptions: [.audioTimeRange]`, the result
  is an `AttributedString` whose **each run carries an `audioTimeRange` (`CMTimeRange`)**;
  Apple states it directly in WWDC25 277 ("Each run has an audioTimeRange attribute
  represented as CMTimeRange")
  ([session](https://developer.apple.com/videos/play/wwdc2025/277/);
  [audioTimeRange](https://developer.apple.com/documentation/speech/speechtranscriber/resultattributeoption/audiotimerange)).
- **On-device, zero app weight:** the model lives in system storage (not the app
  bundle, not the app's memory), installed per-locale via
  `AssetInventory.assetInstallationRequest(supporting:)` → `downloadAndInstall()`;
  check `SpeechTranscriber.supportedLocales` / `installedLocales`.
- **Built for long-form** (lectures/meetings/films), **no per-request length cap**,
  ~2.2× faster than MacWhisper Large-V3-Turbo on Apple Silicon
  ([callstack](https://www.callstack.com/blog/on-device-speech-transcription-with-apple-speechanalyzer);
  [blakecrosley](https://blakecrosley.com/blog/speech-framework-vs-sfspeechrecognizer)).
- **40+ locales** incl. `en_US`/`en_GB`. Sample: Apple's **SwiftTranscriptionSampleApp**
  ([Bringing advanced speech-to-text…](https://developer.apple.com/documentation/speech/bringing-advanced-speech-to-text-capabilities-to-your-app)).
- **Legacy fallback** `SFSpeechRecognizer`: `SFTranscriptionSegment` gives
  `.timestamp`/`.duration`/`.substring`/`.alternativeSubstrings`/`.confidence`, but
  Apple defines a segment as a *phrase* (not contractually per-word) and historically
  caps ~1 min/request — poor for feature-length batch.

### 2.3 Recommended word-timing approach

**Hybrid: recognize with SpeechTranscriber, then VALIDATE against the known caption
text — and keep MFA as the rough-audio aligner.** This directly answers 039b.

1. **Default — SpeechTranscriber (native, on-device, no dependency).** Run it over
   each captioned film's extracted audio. It is zero-third-party (honors the
   no-Swift-package rule and mirrors the existing on-device Apple-Vision cover
   pipeline, Decision 024), fast, and emits `audioTimeRange` per word.
2. **Hallucination guard via the transcript we already have.** Because we hold a
   trusted line-level caption, align the recognizer's word stream to the caption
   text (token-level diff / Needleman-Wunsch). Words that **agree** with the caption
   keep their `audioTimeRange` and are indexed; words that **diverge** (recognizer
   invented them — the 039b failure) are dropped or flagged low-confidence and never
   used as supercut sources. This is the validation 039b wished it had: the caption
   is ground truth for *what* was said; the recognizer supplies *when*.
3. **Rough-audio tail → MFA (offline batch).** For films where the recognizer
   agrees poorly with the caption (noisy nitrate, music beds), run **MFA** with our
   caption text + audio + the LibriSpeech ARPAbet dictionary. As a true forced
   aligner with a fixed word sequence it **cannot hallucinate** and gives
   phone/word precision; it's the quality floor for the hard tail. (aeneas is the
   lighter fallback if MFA's dictionary/Kaldi install isn't worth it.)
4. **Restrict to captioned items only** (we have ground truth there). Silent films
   and uncaptioned content are out of scope for word-timing by construction
   (§6).

Avoid as primaries: gentle (unmaintained), whisper.cpp `--dtw` (timing off),
WhisperX (GPU). Run word-timing as a **macOS CLI/agent batch** (like covers), not
in-app — the in-app code only *reads* the resulting index and assembles.

---

## 3. The matching algorithm — text → clip candidates

Given the user's typed sentence, produce an ordered list of clip candidates per
output word/phrase position, against a **word-level index** spanning many films.

### 3.1 Tokenize + normalize

- Lowercase; strip punctuation; expand a small contraction map ("don't"→"do not"
  optionally, but prefer matching the contraction as one token if indexed that way);
  collapse whitespace. Keep a `display` form for the UI and a `match` form for the
  index. Numerics are a known weak spot (WhisperX drops them; recognizers spell them
  out) — normalize "5"↔"five" both directions when matching.

### 3.2 Greedy longest-phrase-first matching

Maximize naturalness by reusing **contiguous multi-word phrases actually spoken by
one person** before falling back to single words (fewer seams = better supercut).

```
i = 0
while i < tokens.count:
    matched = false
    for L in stride(from: maxPhrase, through: 1, by: -1):   # try longest first
        phrase = tokens[i ..< i+L]
        cands = index.lookupContiguous(phrase)   # same archiveID, adjacent words,
                                                 # small inter-word gap tolerance
        if !cands.isEmpty:
            segments.append(Segment(phrase, cands)); i += L; matched = true; break
    if !matched:
        segments.append(Segment(tokens[i], single: lookupWord(tokens[i])))  # may be empty
        i += 1
```

- `lookupContiguous(phrase)`: words from the **same `archiveID`** whose indices are
  consecutive and whose inter-word gap is below a threshold (e.g. < 0.35 s — so we
  don't span an edit/scene cut). This is the connected-word problem; the classic
  one-stage dynamic-programming framing applies if exactness is wanted
  ([one-stage DP, Ney 1984](https://www.researchgate.net/publication/3177528_The_Use_of_a_One-Stage_Dynamic_Programming_Algorithm_for_Connected_Word_Recognition)),
  but greedy longest-first is sufficient and fast for v1.
- **Missing words:** if a token has zero candidates even at L=1, surface it in the
  UI as an **unfilled slot** (the editable timeline shows a gap the user can record,
  type-as-caption, or accept as silence). Never silently drop — that violates the
  "support agency / clarity" guardrail. Offer near-miss suggestions (stem match,
  homophone, the word inside a longer phrase).

### 3.3 Ranking candidates per slot

For each fillable slot, rank takes so the *default* assembly is good but every
alternative is one tap away in the editor:

1. **Clarity / confidence** — recognizer/aligner confidence; agreement with caption
   text (validated words rank above flagged ones).
2. **Clean boundaries** — inter-word gap before and after the word (a word flanked
   by short silences cuts cleaner than one mid-stream); penalize words at a cue edge
   where the neighbor is unknown.
3. **Speaker / source variety** — penalize reusing the same `archiveID` (or same
   detected face/voice) on adjacent output words, to get the "different people"
   payoff. Track used sources across the assembly.
4. **Shot length / framing** — prefer candidates whose surrounding shot is long
   enough to show a face (optional: reuse the Vision face score from the cover
   pipeline, Decision 024); avoid sub-200 ms slivers.
5. **Phrase length bonus** — a 3-word contiguous phrase outranks three single words
   for those positions (already handled by greedy longest-first, but also rank
   longer phrase *alternatives* higher).

### 3.4 Coarticulation / boundary padding (the audio-cut quality lever)

Word boundaries from any aligner fall **inside** coarticulated transitions — the
onset of a word is shaped by the preceding sound, and cutting exactly at the
timestamp clips a phoneme and sounds abrupt
([coarticulation as a word-boundary cue, Springer](https://link.springer.com/article/10.3758/BF03193922)).
Mitigations, all exposed as editable parameters (not baked):

- **Asymmetric padding:** extend each clip a few tens of ms before the word onset
  and after the offset (start − ~40–80 ms, end + ~40–120 ms), snapping to the
  nearest local energy minimum if available. This is videogrep's `--padding` lesson,
  refined: pad to *silence*, not a fixed constant.
- **Micro audio crossfade** (5–15 ms) at each join via AVFoundation audio mix ramps
  to hide the click at concatenation.
- **Prefer phrase-internal cuts:** when a word is taken from inside a contiguous
  phrase the user is reusing, no internal cut is needed at all — another reason
  longest-first wins.
- **Boundary candidates:** prefer takes where the word is bounded by a pause
  (utterance-initial/final), which coarticulate least.

These are quality heuristics; none should block assembly. The user can override
padding per clip in the timeline.

---

## 4. The searchable subtitle INDEX (Feature 8) + word-timing store

Two indexes, both inside the existing **no-backend, SQLite-on-Release / Pages**
model (Decisions 017–019, 029) — additive, never a server.

### 4.1 Line-level FTS5 (Feature 8 — "pull up relevant scenes/videos")

A `subtitle_cues` FTS5 table over every cue line, so a phrase search returns the
exact film **and timecode** of the scene that says it.

```sql
CREATE VIRTUAL TABLE subtitle_fts USING fts5(
    text,                              -- the cue line
    archiveID UNINDEXED,
    startMs   UNINDEXED,
    endMs     UNINDEXED,
    tokenize = 'unicode61 remove_diacritics 2'
);
-- after load: INSERT INTO subtitle_fts(subtitle_fts) VALUES('optimize');
```

- Search `subtitle_fts MATCH 'put out the fire'` → rows with `archiveID`+`startMs`
  → deep-link the player to that timecode + show the scene. This is feature 8's
  whole job and needs only **line-level** cues we already have.
- **Where it lives:** built by a new pipeline tool (`tools/build_subtitle_index.py`)
  from the same VTT files `build_subtitle_assets.py` already produces; emitted as a
  **separate `subtitle.sqlite`** (it's large and only needed by the search/Studio
  surface, so keep it off the main `catalog.sqlite` hot path). Apple clients
  download it from the catalog Release (raw-DEFLATE `.zz`, on-device inflate, like
  `catalog.sqlite.zz` — Decision 019). The **web** viewer queries it in place over
  HTTP **range requests** via `sql.js-httpvfs` — verified viable on GitHub Pages
  with **FTS5 compiled into the WASM build** (`-DSQLITE_ENABLE_FTS5`), fetching only
  the pages a query touches; run `('optimize')` before deploy and index well
  ([phiresky/sql.js-httpvfs](https://github.com/phiresky/sql.js-httpvfs);
  [compiling FTS5 into sql.js](https://blog.ouseful.info/2022/04/06/compiling-full-text-search-fts5-into-sqlite-wasm-build/);
  [GitHub Pages walkthrough](https://dev.to/recca0120/query-sqlite-on-github-pages-with-sqljs-httpvfs-11do)).
  This is exactly the "upgrade path" Decision 029 reserved (flip Pages → Actions,
  deploy a chunked SQLite as a Pages artifact, never in git).

### 4.2 Word-level table (Feature 9 source of truth)

A companion table in the same `subtitle.sqlite`, populated only for items that
passed the §2.3 word-timing pass:

```sql
CREATE TABLE words (
    archiveID TEXT,
    word      TEXT,        -- normalized match form
    seq       INTEGER,     -- ordinal within the film (for contiguous-phrase lookup)
    startMs   INTEGER,
    endMs     INTEGER,
    conf      REAL,        -- aligner/recognizer confidence (validated vs caption)
    gapBefore INTEGER,     -- ms of silence before (boundary-cleanliness ranking)
    gapAfter  INTEGER
);
CREATE INDEX idx_words_word ON words(word);
CREATE INDEX idx_words_seq  ON words(archiveID, seq);   -- contiguous-phrase scans
```

- `lookupWord(w)` → `SELECT … FROM words WHERE word = ?` (capped, ranked).
- `lookupContiguous([w1,w2,w3])` → candidates of `w1`, then check `words` at
  `seq+1`, `seq+2` in the same `archiveID` with gap tolerance. The `idx_words_seq`
  index makes this cheap and range-request-friendly for the web path.
- Keep this table **append-only and additive** as the word-timing batch drains the
  catalog (popularity-first), mirroring the captions rollout. Items not yet
  processed simply have no rows — search degrades gracefully (§6).

### 4.3 Serving & size

- The word table is the big one. Estimate ~8–10k words/film × thousands of films →
  tens of millions of rows. Keep it in its **own DB**, shard or chunk for the web
  VFS, and **publish only the popular head first** (the same popularity-first
  discipline as covers/whisper). The supercut feature is most compelling on
  recognizable, well-captioned films anyway.
- All within the published-artifact rule: **consumers only**, no client writes to
  the shared DB; additive schema; merge-guarded builds (Decisions 017/018/020).

---

## 5. Assembly — an EDITABLE AVMutableComposition (the guardrail)

The supercut is **built as a draft timeline the user edits**, never a one-tap locked
export. This is the Decision 033 learning-orientation guardrail and the difference
between "a tool that makes someone more human" and a slot-machine.

### 5.1 Composition model (native AVFoundation, no third-party package)

- One `AVMutableComposition` with a video track + audio track. For each chosen take,
  insert `[start−padBefore, end+padAfter]` of the source asset's time range. Source
  assets stream via the existing `ResilientStreamLoader` (Decisions 021/031/034) or
  download a small clip window to `Caches` (the proxy approach the Clip Studio engine
  already uses, Decision 033). Use **proxy clips** (low-res, fast-scrubbing) for the
  editing session; re-render from source on final export.
- `AVMutableVideoComposition` for the reframe (1:1 / 9:16 / 16:9, reusing the Clip
  Studio reframe math) and any per-clip look; `AVMutableAudioMix` for the
  micro-crossfades (§3.4).

### 5.2 The editor surface (the guardrail in UI terms)

The assembled draft lands in a timeline where the user can, before anything is
exported:

- **Reorder** words/phrases (drag).
- **Swap takes** — each slot shows its ranked alternatives (§3.3); tap to swap which
  person says that word. This is the core "agency" affordance.
- **Retime / re-pad** each clip (adjust the §3.4 boundary padding per cut; nudge
  in/out).
- **Fill unmatched slots** — record/caption/accept-silence for words with no
  candidate (§3.2).
- **Add the provenance credit** — every export burns `archivewatch.org · Public
  Domain` and embeds each source's `archive.org/details/{id}` in `AVMetadataItem`s,
  per Decision 033. A multi-source supercut credits **all** sources used.
- Export to Photos / share sheet as MP4 (and GIF), exactly like Clip Studio v1.

videogrep's `.fcpxml` export is the philosophical precedent: hand the cut decisions
to an editor rather than emit a finished file. Here the editor is in-app and native.

### 5.3 Rights gate

Same as Clip Studio (Decision 033): only `Catalog.Item.isClippable` items
(playable + PD/CC/absent rightsStatus) may be a supercut source; the affordance is
hidden, not disabled, otherwise. Defense-in-depth over Decision 027's upstream
exclusion.

---

## 6. Metadata gaps — don't promise subtitles that aren't there

Search and supercut must degrade honestly so the user never types a sentence and
gets a silent "no results" that's actually a coverage gap.

- **Already have:** `captions` (nil = no caption known), `captionsChecked` (scanned
  yet?), `subtitleHLS`/`captions[].vttURL` (built yet?). Add a **`wordTimed`** flag
  (and `wordTimedChecked`) set by the §2.3 batch so Feature 9 knows which items can
  source words.
- **Silent / music-only:** `contentType == "silent-film"` / `isSilentFilm` already
  exist (`build_sqlite.py`). These have **no dialogue** — exclude from both subtitle
  search and word-timing; if a silent appears in a Feature-8 result it's a caption
  artifact (intertitles) and should be down-ranked or labeled.
- **Home movies / ephemera / newsreels:** flag as likely-no-clean-dialogue; allow
  but warn that coverage is sparse.
- **Unprocessed:** an item with `captionsChecked == false` is *unknown*, not
  *empty*. The UI should say "X films searched so far" (the popular head), and
  surface coverage as it grows — the same honest framing the web viewer uses for the
  index.
- **Per-item caption quality:** archive.org ASR can be wrong (039b). For Feature 9,
  the §2.3 caption-vs-recognizer agreement score *is* a quality signal — only
  high-agreement words become supercut sources, so bad captions can't poison the
  output.

Surface all four content states (loading / empty / error / unprocessed) per the
`universal-feature-states` discipline — especially the "not yet processed" state,
which is unique to this growing index.

---

## 7. Recommended build order

1. **Feature 8 first** (cheapest, immediately useful): `tools/build_subtitle_index.py`
   → `subtitle.sqlite` FTS5 over existing VTT cues; wire search into the viewer
   (deep-link to timecode) and the web path via `sql.js-httpvfs`. No word timing
   needed.
2. **Word-timing batch** (`tools/build_word_timing.swift` CLI or agent): macOS
   SpeechTranscriber + caption-validation, popularity-first, append to the `words`
   table; MFA for the rough tail. Sets `wordTimed`.
3. **Feature 9 assembler:** matching algorithm (§3) over the `words` table →
   ranked candidates → `AVMutableComposition` draft → **editable timeline** (§5).
4. **Quality polish:** boundary padding to silence, micro-crossfades, speaker-variety
   ranking, face-score integration.

---

## 8. Sources

- videogrep: [repo](https://github.com/antiboredom/videogrep) ·
  [source](https://github.com/antiboredom/videogrep/blob/master/videogrep/videogrep.py) ·
  [design post](https://lav.io/2014/06/videogrep-automatic-supercuts-with-python/) ·
  [tutorial](https://lav.io/notes/videogrep-tutorial/)
- Supercut genre: [Wikipedia](https://en.wikipedia.org/wiki/Supercut) ·
  [Know Your Meme](https://knowyourmeme.com/memes/supercut)
- WhisperX: [repo](https://github.com/m-bain/whisperx) ·
  [Interspeech 2023](https://www.isca-archive.org/interspeech_2023/bain23_interspeech.pdf) ·
  [word-level editing](https://sachachua.com/blog/2024/09/using-whisperx-to-get-word-level-timestamps-for-audio-editing-with-emacs-and-subed-record/)
- MFA: [docs](https://montreal-forced-aligner.readthedocs.io/en/latest/user_guide/index.html) ·
  [Interspeech paper](https://montrealcorpustools.github.io/Montreal-Forced-Aligner/images/MFA_paper_Interspeech2017.pdf)
- aeneas: [repo](https://github.com/readbeyond/aeneas) · [site](https://www.readbeyond.it/aeneas/)
- whisper.cpp word timing: [discussion #2307](https://github.com/ggml-org/whisper.cpp/discussions/2307)
- Apple SpeechAnalyzer/SpeechTranscriber: [WWDC25 277](https://developer.apple.com/videos/play/wwdc2025/277/) ·
  [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber) ·
  [audioTimeRange](https://developer.apple.com/documentation/speech/speechtranscriber/resultattributeoption/audiotimerange) ·
  [supportedLocales](https://developer.apple.com/documentation/speech/speechtranscriber/supportedlocales) ·
  [Bringing advanced speech-to-text](https://developer.apple.com/documentation/speech/bringing-advanced-speech-to-text-capabilities-to-your-app) ·
  [SpeechAnalyzer guide](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide) ·
  [benchmark](https://blakecrosley.com/blog/speech-framework-vs-sfspeechrecognizer)
- SFSpeechRecognizer: [SFTranscriptionSegment](https://developer.apple.com/documentation/speech/sftranscriptionsegment)
- SQLite-over-HTTP / FTS5: [phiresky/sql.js-httpvfs](https://github.com/phiresky/sql.js-httpvfs) ·
  [FTS5 in sql.js](https://blog.ouseful.info/2022/04/06/compiling-full-text-search-fts5-into-sqlite-wasm-build/) ·
  [GitHub Pages walkthrough](https://dev.to/recca0120/query-sqlite-on-github-pages-with-sqljs-httpvfs-11do)
- Connected-word / coarticulation: [one-stage DP (Ney)](https://www.researchgate.net/publication/3177528_The_Use_of_a_One-Stage_Dynamic_Programming_Algorithm_for_Connected_Word_Recognition) ·
  [coarticulation & word boundaries](https://link.springer.com/article/10.3758/BF03193922)
