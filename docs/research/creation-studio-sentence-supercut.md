# Research — the Sentence Supercut (type a line, the corpus speaks it)

Supercut v1 (shipped): search a PHRASE → every clip in the catalog where it's spoken → an editable
pile of candidates. This brief is the inverse and far harder problem the owner wants next: **type an
ARBITRARY line of text and assemble a supercut that SPEAKS it, word-by-word, using only clips that
contain those words** ("Now you're speaking my language", the auto-tune-the-news / political
word-collage genre). The output is a sentence stitched from many films.

## The genre & prior art

- "Word-by-word" / "sentence collage" supercuts (e.g. assembling a politician's sentence from
  hundreds of clips of single words; movie-dialogue mashups that recite a poem).
- The craft variable that separates *usable* from *gibberish* is **how few cuts** it takes and **how
  cleanly each word is isolated**. A 6-word line cut from 6 different films is jarring; the same line
  where "I love you" came from ONE film and only "public domain" needed two more reads far better.

## The three sub-problems

1. **Where is each word spoken?** (the index)
2. **What are its exact boundaries?** (so the cut contains *only* that word)
3. **Which utterance, and how few?** (selection + minimizing cuts)

### 1. The index — word locations

| Option | How | Cost | Quality |
|---|---|---|---|
| Cue-level (have it) | `subtitle.sqlite` cues: text + line time range | free | line, not word |
| Proportional split | word i of N in a cue → `start + i/N·dur` | free | rough; pauses/rate break it |
| On-device speech | SpeechTranscriber per chosen cue → per-word `audioTimeRange` (have it: `WordTiming`) | slow (per clip) | precise, validated vs caption (Rule 6b) |
| **CI forced alignment** | align the KNOWN caption text to audio (wav2vec2 / MFA) → a word table | heavy batch | precise, instant at query, scales |

Key insight: **forced ALIGNMENT ≠ transcription.** Decision-039b retired *transcription* (whisper
hallucinated unknown text). Aligning the caption we ALREADY hold to the audio cannot hallucinate —
it only places known words in time. So a CI word index is safe and is the eventual scale answer.

### 2. Boundaries

Tight cuts need word-level times (speech/alignment), not proportional. A 0.1–0.2 s pad each side
keeps the consonant onset/offset. Snap to zero-crossings later for click-free joins.

### 3. Selection — the quality algorithm (LONGEST-MATCH)

Greedy longest-match coverage, NOT word-at-a-time:
- Walk the input left→right. At position *i*, find the LONGEST contiguous sub-phrase `words[i..j]`
  that appears as whole words in some cue. Use that ONE clip; advance to `j+1`.
- Falling back to single words only when no longer run exists → **fewest cuts, smoothest result.**
- Rank competing utterances of the same phrase by: shorter cue (word more isolated) → larger phrase
  fraction of the cue → clearer/popular title. Keep alternates so the user can swap.
- A word with NO match is an explicit GAP the user resolves (pick a near-spelling, split, type a
  synonym, record it) — never silently dropped (Rule 5a learning gate).

## Chosen feature set (phased)

**Phase A — Sentence composer on what we already have (this iteration).**
- New "Compose a sentence" mode in the supercut sheet. Type a line → greedy LONGEST-MATCH over the
  cue index (whole-word phrase search) → for each matched run, get its tight range via `WordTiming`
  (SpeechTranscriber on the cached cue window), proportional fallback if no model → assemble the
  runs in order into an EDITABLE timeline. Missing words are surfaced as gaps with the option to
  drop/keep/substitute. Per-run alternates selectable.
- Reuses everything built: cue index (+ full-corpus CI index), `WordTiming`, the editable timeline.
- Cost: one cache + one speech pass per RUN (longest-match keeps runs few). A deliberate action with
  progress, not interactive.

**Phase B — CI forced-aligned word index (scale + instant).**
- A Linux CI pipeline force-aligns each captioned film's caption to its audio (wav2vec2 via
  torchaudio, no hallucination) → a `words(word, archiveID, sourceURL, start, end)` table + an
  `ngram` table for fast longest-match lookup. Published like `subtitle.sqlite`; the composer queries
  it instead of running speech at compose time → instant, whole-catalog, no per-clip wait.

**Phase C — polish.** zero-crossing/forced-faststart joins, per-word audio-level normalization,
alternate-take carousel, "read it back" preview before committing, phonetic nearest-match for gaps.

## Non-negotiables
- Editable result, never one-tap final (Rule 5a). Provenance + rights gate unchanged.
- Alignment-not-transcription keeps Decision-039b satisfied.
- Phase A ships on-device with zero new infra; Phase B is the CI scale-up.
