# Runbook — Whisper subtitle generation (Decision 039 Phase 4)

Generate English subtitles for catalog films that have **no** archive.org
captions, by transcribing each film's own audio with whisper.cpp on an Apple
Silicon Mac. The films are public domain, so we own the output freely (no API
cap). This is the **coverage backbone**; OpenSubtitles (Phase 3) is the quality
layer on top of the popular head.

This mirrors the cover-generation protocol (Decision 023/024): a Mac-first,
resumable, popularity-first batch that runs unattended under `caffeinate`. It is
**not** a CI job — whisper.cpp + Metal is Apple-Silicon only, and the per-film
audio pull is bandwidth-heavy.

## One-time setup

```sh
brew install whisper-cpp ffmpeg
mkdir -p ~/.cache/whisper
# small.en — the quality/speed sweet spot (~10-20x realtime with Metal on M-series)
curl -L https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin \
  -o ~/.cache/whisper/ggml-small.en.bin
```

(`base.en` is ~2x faster at lower quality; `medium.en` is higher quality but
~3x slower. small.en is the default.)

## Run the batch

```sh
cd ~/Documents/GitHub/Archive-Watch
python3 tools/catalog_release.py fetch          # pull the live full catalog locally

# Popularity-first, resumable, unattended. Tune --workers to your bandwidth
# (downloads overlap so the GPU stays fed); --limit 0 = the whole eligible set.
caffeinate -i nohup python3 tools/whisper_subtitles.py \
  --workers 4 --model ~/.cache/whisper/ggml-small.en.bin \
  > whisper_run.log 2>&1 &

tail -f whisper_run.log                          # watch progress
```

- **Resumable**: already-captioned items are filtered out, so re-running after a
  crash/stop skips everything built so far. `tools/whisper_manifest.jsonl` logs
  every item's status (gitignored).
- **Targets**: playable, not `excluded`, not already captioned, **not
  silent-film** (no dialogue) or tv-series. `--min-pop N` floors by popularity;
  `--types feature-film,animation` restricts content types.
- **Throughput** (measured, M3, small.en, 4 workers): ~30-45 films/hour (bandwidth-bound; ~8 of 12 built per test batch, failures are transient + retried),
  ~300 MB downloaded per film. The popular few thousand finish in ~a day; the
  full ~16k-talkie tail is a multi-day run. Stop and resume anytime.

## Publish what's been generated

The generator writes `subs/<id>/` (VTT + HLS) locally and updates `catalog.json`
in place. Publish via the **same path** the CI subtitle pipeline uses:

```sh
# 1. Accumulate into the rolling subtitle-assets release (union with prior subs)
mkdir -p subs
gh release download subtitle-assets -p 'subs.tar.gz' -O prior.tar.gz && tar xzf prior.tar.gz && rm prior.tar.gz
tar czf subs.tar.gz subs
gh release upload subtitle-assets subs.tar.gz --clobber

# 2. Publish the catalog (carries the new captions + subtitleHLS) + rebuild
python3 tools/remediate_catalog.py
python3 tools/catalog_release.py publish
gh workflow run deploy-pages.yml                 # serve /subs on Pages
gh workflow run publish-db.yml                   # rebuild the app DB
```

You can publish mid-run (the generator flushes `catalog.json` every 25 items) —
each publish makes the latest generated subs live. The app auto-fetches the new
DB on next launch.

## Verify

```sh
# A generated item carries source:"whisper" + a live HLS:
python3 -c "import json;c=json.load(open('catalog.json'));i=next(x for x in c['items'] if x['archiveID']=='House_On_Haunted_Hill.avi');print(i['captions'],i['subtitleHLS'])"
curl -s https://archivewatch.org/subs/House_On_Haunted_Hill.avi/en.vtt | head
```

On device: relaunch the app, wait ~60s for the DB refresh, open the film — the
native CC button appears and English captions display (default-on).

## Notes / gotchas

- **`[BLANK_AUDIO]`/`[MUSIC]` cues are filtered** — only speech reaches the
  screen (see `clean_vtt`).
- **Quality** is machine transcription — good (clearly above archive.org ASR),
  not human-perfect. OpenSubtitles (`opensubtitles_subtitles.py`, Phase 3)
  upgrades the marquee titles to human subs where you have a key.
- **`whisperGenerated: true`** marks these items so Phase 3 `--upgrade` can later
  replace them with a human track.
- **Never transcribe an `excluded` item** — the rights gate (Decision 027) is
  upstream; the candidate filter already drops them.
