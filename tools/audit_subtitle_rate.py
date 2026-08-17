#!/usr/bin/env python3
"""Find subtitle files that are provably mistimed, using one airtight fact.

Owner report 2026-08-17: Earth vs. the Flying Saucers' subtitles are
"incredibly poor". Measured: the published file's last cue ENDS at 4994.8s on
a 4818.7s film — 176 seconds past the end of the movie. Ground truth (speech
transcribed locally at two points 50 minutes apart) put it +51s late at the
quarter mark and +184s late near the end. It does not have an offset; it
DRIFTS, because it was authored against a different frame rate than the copy
we stream. Decisions 062/064 search for one constant offset and are
structurally blind to this: no constant is right for a file that is 0s off at
the start and 200s off at the end.

THE TEST IS PHYSICS, NOT PATTERN MATCHING. A subtitle file cannot end after
its film ends. That single check needs no download, no audio and no speech
models, so it scans the whole published set in minutes and runs anywhere.

What this deliberately does NOT do: infer a fault from a file that ends
EARLY at a telecine-looking ratio. That was tried and measured — across 3,726
published files the distribution of (last cue end / runtime) is smooth and
rises monotonically toward 1.0, with NO spike at 23.976/25 = 0.9590. A film
with roughly 2:45 of end credits lands on that ratio by coincidence, so the
inference would have "repaired" 95 files with no evidence they were wrong.
reefer_madness1938 is exactly that case. Precision over recall (Decisions
035/064): leaving a bad file alone costs a viewer captions on one film;
rewriting a good one breaks a film that worked.

Verdicts (`subtitleRateAudit`, additive + resumable):
  overruns  — ends after the film. Definitively mistimed.
              `cause: PAL->NTSC` when the overrun ratio also matches a
              telecine constant, which means `fix_subtitle_rate.py` can
              repair it arithmetically. Otherwise it needs audio-based sync.
  far-past  — ends >10% past the end: a wrong file or a compilation's
              subtitles, not a timing fault. Never rescale these.
  ok        — no verdict available from data alone. NOT a clean bill of
              health: a uniformly-shifted file ends in the right place.
              Decision 062's on-device judge still owns that fault.

Usage:
  python tools/catalog_release.py fetch
  python tools/audit_subtitle_rate.py [--limit N] [--workers 8]
  python tools/catalog_release.py publish
"""
import argparse, json, re, urllib.request
from concurrent.futures import ThreadPoolExecutor

CATALOG = "catalog.json"
UA = {"User-Agent": "ArchiveWatch-pipeline (subtitle rate audit; ben@learningischange.com)"}

# The cue's END is what must land inside the film. Reading the START instead
# mis-flags a correctly-timed file whose final cue ends right at the runtime.
CUE = re.compile(r"-->\s*(\d+):(\d\d):(\d\d)[.,](\d\d\d)")

OVERRUN_TOL = 1.005     # >0.5% past the end is not rounding or a stray cue
FAR_PAST = 1.10         # beyond this it is a different work, not a rate error

# A file authored at 25fps and played at 23.976 runs long by exactly this.
# Used ONLY to explain an overrun we have already proven — never to detect one.
TELECINE = {"PAL->NTSC": 25 / 23.976}
TELECINE_TOL = 0.004


def last_cue_end(url):
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=25) as r:
            text = r.read().decode("utf-8", "replace")
    except Exception:
        return None                      # transient — never condemn on a fetch failure
    last = None
    for m in CUE.finditer(text):
        g = [int(x) for x in m.groups()]
        end = g[0] * 3600 + g[1] * 60 + g[2] + g[3] / 1000
        last = end if last is None else max(last, end)
    return last


def vtt_url(item):
    hls = item.get("subtitleHLS")
    return hls.rsplit("/", 1)[0] + "/en.vtt" if hls else None


def classify(last, runtime):
    ratio = last / runtime
    if ratio >= FAR_PAST:
        return "far-past", None
    if ratio > OVERRUN_TOL:
        for name, r in TELECINE.items():
            if abs(ratio - r) <= TELECINE_TOL:
                return "overruns", name
        return "overruns", None
    return "ok", None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--refresh", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with open(CATALOG) as f:
        catalog = json.load(f)

    targets = [
        i for i in catalog["items"]
        if i.get("subtitleHLS") and not i.get("excluded")
        and (i.get("runtimeSeconds") or 0) > 600
        and (args.refresh or not i.get("subtitleRateAudit"))
    ]
    targets.sort(key=lambda i: -(i.get("popularityScore") or 0))
    if args.limit:
        targets = targets[: args.limit]
    print(f"scanning {len(targets)} published subtitle files", flush=True)

    def work(item):
        return item, last_cue_end(vtt_url(item))

    counts, findings = {}, []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        for n, (item, last) in enumerate(pool.map(work, targets)):
            if last is None or last <= 0:
                counts["unfetchable"] = counts.get("unfetchable", 0) + 1
                continue
            runtime = item["runtimeSeconds"]
            verdict, cause = classify(last, runtime)
            counts[verdict] = counts.get(verdict, 0) + 1
            if not args.dry_run:
                item["subtitleRateAudit"] = {
                    "lastCue": round(last, 1), "runtime": runtime,
                    "ratio": round(last / runtime, 4), "verdict": verdict,
                    **({"cause": cause} if cause else {}),
                }
            if verdict != "ok":
                findings.append((item["archiveID"], verdict, cause or "",
                                 round(last), runtime, round(last / runtime, 3),
                                 item.get("popularityScore") or 0))
                print(f"  {verdict.upper():9} {item['archiveID'][:44]:44} "
                      f"ends={round(last):5}s runtime={runtime:5}s "
                      f"ratio={last/runtime:.3f} {cause or ''}", flush=True)
            if n % 250 == 249:
                print(f"  ... {n+1}/{len(targets)} — {counts}", flush=True)

    print(f"\nverdicts: {counts}")
    repairable = sum(1 for f in findings if f[1] == "overruns")
    print(f"provably mistimed: {repairable} "
          f"({sum(1 for f in findings if f[2])} of them arithmetically repairable)")
    if findings and not args.dry_run:
        with open("tools/subtitle_rate_findings.csv", "w") as f:
            f.write("archiveID,verdict,cause,lastCue,runtime,ratio,pop\n")
            for row in findings:
                f.write(",".join(str(x) for x in row) + "\n")
        print("wrote tools/subtitle_rate_findings.csv")
        with open(CATALOG, "w") as f:
            json.dump(catalog, f, separators=(",", ":"))
        print("catalog written")


if __name__ == "__main__":
    main()
