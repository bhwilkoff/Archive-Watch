#!/usr/bin/env python3
"""Does this film actually make a sound?

WHY THIS EXISTS. The catalogue has `isSilentFilm`, and
`docs/TVOS-STUDIO-RUNBOOK.md` §3 already records that it is unreliable
("several 1928 entries flagged 0 are silent"). On 2026-09-20 the owner picked
a film from the home screen, heard nothing, and reasonably reported the audio
as broken — it was a silent film. The same day the hero was tightened to
buckets the rights audit can PROVE, which is overwhelmingly pre-1930: 3,392 of
3,612 hero-eligible items. So the marquee now routinely offers films with no
sound, and the app cannot truthfully say which.

TRACK PRESENCE IS NOT ENOUGH, and that is the whole reason this is a probe
rather than a query. Measured by hand the same day:

    TheWizardOfOz1925   AAC 44100 stereo, 3 kb/s   mean -91.0 dB  max -91.0 dB
    Cops1922            no audio track at all
    steamboat_bill      AAC 44100 stereo, 128 kb/s mean -20.2 dB  max  -6.4 dB

The first has a track and is silent. A `loadTracks(withMediaType: .audio)`
check — which `DetailView` already does for the Studio readout — calls it
sound. Only the LEVEL separates them.

TWO TRAPS, both already paid for elsewhere in this repo:

  · `ffmpeg -v error` HIDES volumedetect's output entirely, so a perfectly
    normal track reads as "zero samples decoded" (§9 records this costing two
    runs). `-v info` is required.
  · a mean at the 16-bit floor (about -91 dB) with the max EQUAL to it is
    digital silence; a quiet-but-real track has max well above mean. Judging
    on mean alone would call a quiet film silent.

OUTPUT is additive and merge-guarded (Decision 020): a JSON sidecar keyed by
archiveID, and a run that probes nothing changes nothing.

    python3 tools/audit_soundtrack.py --db /tmp/catalog.sqlite --limit 40
    python3 tools/audit_soundtrack.py --db /tmp/catalog.sqlite --self-test
"""
import argparse, json, os, sqlite3, subprocess, sys, re

SIDECAR = "shared/editorial/soundtrack.json"
FLOOR_DB = -80.0          # below this, with max ~= mean, is digital silence
SAMPLE_SECONDS = 45
SAMPLE_FROM = 120         # skip titles/leader, which are often silent anyway


def probe(url, seconds=SAMPLE_SECONDS, start=SAMPLE_FROM):
    """Returns (verdict, mean_db, max_db). Verdict is sound | silent | none | unreadable."""
    try:
        streams = subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "a",
             "-show_entries", "stream=codec_name", "-of", "csv=p=0", url],
            capture_output=True, text=True, timeout=90).stdout.strip()
    except Exception:
        return ("unreadable", None, None)
    if not streams:
        return ("none", None, None)

    try:
        # -v info, NOT -v error: volumedetect writes to the info channel and
        # `-v error` discards it, which reads as a track with no samples.
        out = subprocess.run(
            ["ffmpeg", "-v", "info", "-ss", str(start), "-t", str(seconds),
             "-i", url, "-vn", "-af", "volumedetect", "-f", "null", "-"],
            capture_output=True, text=True, timeout=180).stderr
    except Exception:
        return ("unreadable", None, None)

    m = re.search(r"mean_volume:\s*(-?[\d.]+) dB", out)
    x = re.search(r"max_volume:\s*(-?[\d.]+) dB", out)
    if not m or not x:
        return ("unreadable", None, None)
    mean, mx = float(m.group(1)), float(x.group(1))
    # Digital silence: at the floor AND with no peak above it. A quiet but real
    # track has a max well above its mean.
    if mean <= FLOOR_DB and (mx - mean) < 1.0:
        return ("silent", mean, mx)
    return ("sound", mean, mx)


def self_test():
    """The instrument, checked against three films whose answers are known.

    A probe that cannot tell these three apart cannot be trusted on 20,000.
    """
    cases = [
        ("https://archive.org/download/steamboat_bill_ipod/steamboat_bill.mp4", "sound"),
        ("https://archive.org/download/TheWizardOfOz1925/LarrySemonsWizardOfOzsilent1925.mp4", "silent"),
    ]
    ok = True
    for url, want in cases:
        got, mean, mx = probe(url, seconds=30)
        mark = "PASS" if got == want else "FAIL"
        if got != want:
            ok = False
        print(f"  {mark}  {want:9s} expected, {got:10s} measured "
              f"(mean {mean}, max {mx})  {url.rsplit('/',1)[-1]}")
    print("\nSELF-TEST " + ("PASS — the probe separates sound from silence"
                            if ok else "FAIL — do not trust a run from this"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", required=True)
    ap.add_argument("--limit", type=int, default=25)
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--apply", action="store_true",
                    help="write the sidecar; without it the run only reports")
    a = ap.parse_args()

    if a.self_test:
        return self_test()

    existing = {}
    if os.path.exists(SIDECAR):
        existing = json.load(open(SIDECAR))

    con = sqlite3.connect(a.db)
    # The hero's own pool first: that is where a silent film is most likely to
    # be mistaken for a broken one.
    rows = con.execute("""
        SELECT archiveID, title, year FROM items
        WHERE rightsBucket IN ('safe_pd_age','safe_gov','safe_cc')
          AND hasRealArtwork=1 AND playable=1
          AND contentType NOT IN ('tv-series','tv-episode','tv-special','commercial')
        ORDER BY popularityScore DESC""").fetchall()
    todo = [r for r in rows if r[0] not in existing][:a.limit]
    print(f"{len(rows)} hero-eligible items, {len(existing)} already probed, "
          f"probing {len(todo)}")

    counts = {}
    for aid, title, year in todo:
        meta = f"https://archive.org/metadata/{aid}"
        try:
            j = json.loads(subprocess.run(["curl", "-s", meta],
                                          capture_output=True, text=True, timeout=60).stdout)
            best = None
            for f in j.get("files", []):
                n = f.get("name", "")
                if n.endswith(".mp4"):
                    sz = int(f.get("size") or 0)
                    if best is None or sz > best[1]:
                        best = (n, sz)
            if not best:
                verdict, mean, mx = ("unreadable", None, None)
            else:
                verdict, mean, mx = probe(
                    f"https://archive.org/download/{aid}/{best[0]}")
        except Exception:
            verdict, mean, mx = ("unreadable", None, None)
        counts[verdict] = counts.get(verdict, 0) + 1
        print(f"  {verdict:10s} {str(year or '----'):4s} {title[:44]}")
        if verdict != "unreadable":
            existing[aid] = {"soundtrack": verdict, "meanDb": mean, "maxDb": mx}

    print("\n" + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    if a.apply and todo:
        os.makedirs(os.path.dirname(SIDECAR), exist_ok=True)
        json.dump(existing, open(SIDECAR, "w"), indent=1, sort_keys=True)
        print(f"wrote {SIDECAR} ({len(existing)} items)")
    elif todo:
        print("(report only — pass --apply to write the sidecar)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
