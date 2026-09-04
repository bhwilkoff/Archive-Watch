# Which copy of a film we ship — observed issues

Findings from the Roku playback audit (2026-09-03/04). This is a RECORD, not a
work plan: the Roku build is the active priority and only the first item below
has been fixed. Each entry says what was measured and how, so the next person
does not have to re-derive it.

## 1. Restricted items shipped as playable — FIXED (Decision 104)

`cubanc_000437` ("Heart to Heart") shipped on every platform and would not
play. archive.org states why, in metadata the pipeline already fetches:

    access-restricted-item: true
    collection: [bancroftlibraryucberkeley, californiarevealed, stream_only, americana]
    cubanc_000437_access.HD.ia.mp4   private: true   (derivative)
    cubanc_000437_access.HD.mp4      private: true   (original)

`pick_video` ranked a private file as the best derivative and baked its URL.
Nothing downstream could catch it, because the storage node answers 403 and
403 is deliberately TRANSIENT (Decision 088 — throttling must never demote a
film). Fixed in the shared picker so ingest cannot admit one either;
`tools/test_private_derivative.py` locks it.

**Rate:** 1 genuinely unplayable film in 31 audited (~3%). The one other
"failure" in that run was the harness walking out of the channel, not a film.

## 2. A derivative outranks a better original — MEASURED, NOT FIXED

`archive_lib.pick_video` ranks by TIER first and size second, and every
`derivative` tier sits above the tier that holds originals. So Archive's
re-encode wins even when the uploader's own mp4 is substantially better.

Measured on 20 random professionally-presented items with a public mp4:

    items where a notably higher-resolution mp4 existed but was not chosen: 1/20
      fiddlesticks_1930   baked 618x480   available 928x720 (fiddlesticks_1930.mp4)

**Do not "fix" this by preferring originals.** The tier order exists for
reasons that still hold: derivatives are faststart, consistently encoded, and
far more likely to stream without the stalls Decisions 021/031/034 were spent
on, while an "original" can be any container an uploader had to hand. A change
here needs a measurement of streaming behaviour, not just of pixel count —
the resolution is only one of the things being traded.

## 3. Low-resolution is often the truth, not a bug

Three audited films played at 320x240, and in every case that was the best mp4
archive.org offers:

    gov.archives.arc.616322          512Kb MPEG4 320x240  |  Ogg 400x304
    homemovie_tarzan_and_rocky_gorge 512Kb MPEG4 320x240  |  Ogg 400x304
    Our_Day                          512Kb MPEG4 320x240  |  Ogg 400x304

Worth stating because it looks identical to a selection bug from the outside.
The honest presentation question — whether a viewer should be told a copy is
320x240 before pressing Play — belongs with the Roku "More" / copies surface.

## 4. A baked URL whose filename does not match the file

`silent-princess-nicotine-or-the-smoke-fairy` bakes

    .../Princess%20Nicotine%3A%20or%2C%20The%20Smoke%20Fairy.mp4     (%3A = ':')

while the item's file is

    Princess Nicotine; or, The Smoke Fairy.mp4                        (';')

archive.org's download handler tolerates it — it answers 200 with exactly the
right byte count, and the film plays — so this is latent rather than broken.
It means some baked URLs were built from a title rather than from the file's
own name, and a stricter handler would break them. `check_liveness --refresh`
repoints a URL whose filename is absent from the item, so a sweep already
carries the repair.
