#!/usr/bin/env python3
"""
verify_playback_strict.py — verify catalog playability against the STRICT consumer
(AVFoundation, the app's real engine) instead of the lenient 1 KB byte-probe.

Why: tools/check_liveness.py's `probe_playable()` reads the first KB of a video
and checks an HTTP status + container magic. ffprobe/curl/requests all auto-encode
URLs and never decode a frame, so a URL can pass that probe yet still fail in the
shipping app with "resource unavailable" — a truncated/corrupt stream that reaches
readyToPlay but can't decode, an unsupported codec inside a valid MP4 container, a
moov-at-EOF stall, or (historically) a raw-space/#-bearing URL. The only faithful
verifier is AVFoundation itself. This tool feeds each item's URL(s) to the compiled
Swift harness (tools/PlaybackVerifierCLI), which loads them exactly as DetailView
does — MP4 via AVURLAsset with the app's Catalog.playableURL encoding, and a
CAPTIONED item (subtitleHLS set) via AVPlayerItem on the RAW HLS master URL, the
strict path that actually ships — then waits for readyToPlay and decodes a real
frame at t~=0 and t~=duration/2.

The harness ALSO fails over across archive.org storage nodes exactly as the app does
(Decision 034): a -1008/5xx/reset on the origin node is retried against the item's
other storage nodes (from /metadata) before any verdict — so a rotating-node blip the
app would recover from is reported as a PASS (ok_failover), and a genuinely
all-nodes-down item is reported `unavailable_all_nodes`.

Conventions mirror check_liveness.py exactly (popularity-first `visibility()`
ordering, --limit / --reprobe-days / --max-minutes budgets, catalog_release.py
fetch/publish, HARD-vs-TRANSIENT discipline). It writes NEW additive flags and
never clobbers the lenient `playbackVerified`:
  * strictVerified   (bool)   — True on PASS, False on a HARD/persistent fail.
  * strictReason      (str)   — the harness reason code.
  * strictCheckedAt   (date)  — ISO date of the last strict check.
  * strictUnavailCount/First/LastAt — confirm-across-runs tracking for all-nodes
                                unavailability (cleared on any PASS/recovery).
On a HARD verdict (deterministic media problem: bad file) it ALSO sets excluded=True
+ strictFail=True + playbackReason so build_sqlite's existing `excluded` gate hides
the item everywhere — but ONLY on a hard verdict, NEVER on a transient one (bias
against false-excluding a playable film: a wrongly-hidden film is the costly error).
An `unavailable_all_nodes` verdict does NOT exclude on first sight: it increments a
per-item counter (at most once per calendar day) and excludes only when the item has
failed all-nodes on >= 3 distinct days spanning >= 2 days (strictReason
"persistently_unavailable"). Any subsequent PASS clears the counters and un-hides it.
On PASS it clears any prior strict exclusion IT set (never a rights/liveness exclusion
owned by another tool).

Run: python tools/verify_playback_strict.py [--limit N] [--reprobe-days 90]
        [--max-minutes M] [--concurrency 4] [--dry-run] [--shard-index i --shard-count n]
        [--publish]   (default: --no-publish; mutate local catalog.json only)
Catalog I/O via the local catalog.json (catalog_release.py fetch first in CI).
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from collections import Counter
from datetime import date
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
HARNESS_DIR = REPO / "tools" / "PlaybackVerifierCLI"
HARNESS_BIN = HARNESS_DIR / ".build" / "release" / "PlaybackVerifierCLI"

# Markers this tool OWNS (so a PASS only ever clears an exclusion WE set, never a
# rights-audit (Decision 027) or liveness (check_liveness.py) exclusion).
STRICT_FAIL_FLAG = "strictFail"

# Harness verdicts that are DETERMINISTIC media problems -> exclude immediately.
# Everything else the harness can emit never excludes on its own. Kept in lock-step
# with the Verdict enum in PlaybackVerifierCLI/main.swift.
HARD_VERDICTS = {
    "url_invalid", "not_playable", "no_video_track",
    "decode_failed", "unsupported_codec", "failed_permanent",
}
# PASS is either a first-node success or a recovery on an alternate storage node.
PASS_VERDICTS = {"ok", "ok_failover"}

# SOFT persistent-unavailability: the harness failed over across EVERY known storage
# node and none served the media (the app's own failover would also fail). This is
# NOT a hard exclude — a single all-nodes failure can be an archive.org-wide blip or
# an item mid-rotation. We only exclude once it recurs across separate runs spanning
# multiple days (confirm-across-runs), so a transient outage never hides a film.
UNAVAIL_VERDICT = "unavailable_all_nodes"
UNAVAIL_COUNT_THRESHOLD = 3     # all-nodes failures on >= this many distinct days
UNAVAIL_SPAN_DAYS = 2           # ... spanning >= this many calendar days
UNAVAIL_REASON = "persistently_unavailable"


def build_harness() -> None:
    """Build the Swift harness if the binary is missing. Local dev + CI both call
    this; `swift build` is a no-op when already up to date."""
    if HARNESS_BIN.exists():
        return
    print("[strict] building PlaybackVerifierCLI ...", flush=True)
    subprocess.run(["swift", "build", "-c", "release"], cwd=HARNESS_DIR, check=True)


def load_catalog():
    if not CATALOG.exists():
        print("[strict] no catalog.json (run catalog_release.py fetch first)")
        raise SystemExit(2)
    cat = json.load(open(CATALOG))
    items = cat["items"] if isinstance(cat, dict) else cat
    return cat, items


def visibility(it):
    """Order by what the USER can actually reach — same approximation
    check_liveness.py uses: designed artwork (the Home/browse gate) then
    popularity (how every shelf orders). Verify Home-facing titles first."""
    designed = bool(it.get("hasRealArtwork")
                    and (it.get("artworkSource") or "archive") != "archive")
    return (bool(it.get("shelves")), designed, it.get("popularityScore") or 0)


def strict_stale(it, reprobe_days):
    """A URL that decodes today can rot later (re-derived derivative, node change);
    re-verify past the TTL. 0 = never re-verify."""
    if reprobe_days <= 0:
        return False
    when = it.get("strictCheckedAt")
    if not when:
        return True
    try:
        return (date.today() - date.fromisoformat(str(when))).days >= reprobe_days
    except ValueError:
        return True


def candidate(it, args):
    if not it.get("downloadURL"):
        return False
    # An exclusion owned by ANOTHER tool (rights audit / liveness) is final — never
    # re-verify or resurrect it. Only skip items WE didn't exclude, or that WE did
    # (so a recovered item can clear its own strict exclusion).
    if it.get("excluded") and not it.get(STRICT_FAIL_FLAG):
        return False
    if not it.get("strictCheckedAt"):
        return True
    return strict_stale(it, args.reprobe_days)


def shard_ok(it, shard_index, shard_count):
    """Deterministic, stable assignment of an item to a shard by archiveID hash so
    a CI matrix splits the work with no overlap (mirrors the sharded-macOS pattern
    the subtitle/whisper pipelines use)."""
    if shard_count <= 1:
        return True
    h = 0
    for ch in (it.get("archiveID") or ""):
        h = (h * 131 + ord(ch)) & 0xFFFFFFFF
    return (h % shard_count) == shard_index


def run_harness(batch, concurrency, timeout):
    """Feed a batch of {id,url,hls} to the Swift harness; return {id: result}."""
    lines = "".join(json.dumps({"id": b["id"], "url": b["url"], "hls": b.get("hls")}) + "\n"
                     for b in batch)
    proc = subprocess.run(
        [str(HARNESS_BIN), "--concurrency", str(concurrency), "--timeout", str(timeout)],
        input=lines, capture_output=True, text=True,
    )
    out = {}
    for ln in proc.stdout.splitlines():
        ln = ln.strip()
        if not ln:
            continue
        try:
            r = json.loads(ln)
        except ValueError:
            continue
        out[r.get("id")] = r
    if proc.returncode != 0 and not out:
        sys.stderr.write(proc.stderr[-2000:])
    return out


def _span_days(a, b):
    """Calendar days between two ISO dates (0 if unparseable)."""
    try:
        return (date.fromisoformat(str(b)) - date.fromisoformat(str(a))).days
    except (ValueError, TypeError):
        return 0


def _clear_unavail(it):
    """Drop the persistent-unavailability tracking counters (on any PASS/recovery)."""
    for k in ("strictUnavailCount", "strictUnavailFirstAt", "strictUnavailLastAt"):
        it.pop(k, None)


def mark_unavailable(it, check_date, tally):
    """An all-nodes availability failure. Accumulate a per-item counter (at most one
    increment per calendar day, so a same-day re-run or CI retry never double-counts)
    and exclude ONLY once it has failed on >= UNAVAIL_COUNT_THRESHOLD distinct days
    spanning >= UNAVAIL_SPAN_DAYS. Never excludes on the first (or a single day's)
    occurrence — bias against hiding a film for a transient archive.org outage."""
    if it.get("strictUnavailLastAt") != check_date:
        it["strictUnavailCount"] = int(it.get("strictUnavailCount") or 0) + 1
    if not it.get("strictUnavailFirstAt"):
        it["strictUnavailFirstAt"] = check_date
    it["strictUnavailLastAt"] = check_date

    count = int(it.get("strictUnavailCount") or 0)
    span = _span_days(it.get("strictUnavailFirstAt"), it.get("strictUnavailLastAt"))
    if count >= UNAVAIL_COUNT_THRESHOLD and span >= UNAVAIL_SPAN_DAYS:
        it["strictVerified"] = False
        it[STRICT_FAIL_FLAG] = True
        it["excluded"] = True
        it["strictReason"] = UNAVAIL_REASON
        it["strictCheckedAt"] = check_date
        it["playbackReason"] = f"strict_{UNAVAIL_REASON}"
        tally[f"hard:{UNAVAIL_REASON}"] += 1
        tally["_hard"] += 1
    else:
        # Pending confirmation: NOT excluded, strictVerified left unset so candidate()
        # re-checks it next run to accumulate (or clear on recovery).
        tally[f"unavail:pending(d{count}/s{span})"] += 1
        tally["_unavail"] += 1


def apply_verdict(it, r, today, tally):
    """Write additive strict flags. HARD -> reversible exclude; UNAVAIL -> accumulate
    a confirm-across-runs counter (exclude only when persistently dead); PASS -> clear
    a strict exclusion WE set; TRANSIENT -> leave unverified (retry next run).
    `today` is the ISO date to stamp (the delta's own check date when re-applying a
    shard delta, so strictCheckedAt reflects when the check actually ran)."""
    verdict = r.get("verdict")
    reason = r.get("reason") or verdict
    check_date = r.get("date") or today

    if verdict == UNAVAIL_VERDICT:
        mark_unavailable(it, check_date, tally)
        return
    if verdict not in HARD_VERDICTS and verdict not in PASS_VERDICTS:
        # transient / timeout / internal: leave completely unmarked so the next
        # run retries it. NEVER exclude, NEVER stamp strictCheckedAt.
        tally[f"transient:{reason}"] += 1
        tally["_transient"] += 1
        return
    it["strictCheckedAt"] = check_date
    it["strictReason"] = reason
    if verdict in HARD_VERDICTS:
        it["strictVerified"] = False
        it[STRICT_FAIL_FLAG] = True
        it["excluded"] = True
        it["playbackReason"] = f"strict_{reason}"
        tally[f"hard:{verdict}"] += 1
        tally["_hard"] += 1
        return
    # PASS (ok or ok_failover) — clears any strict exclusion WE set + unavail counters.
    it["strictVerified"] = True
    _clear_unavail(it)
    if it.get(STRICT_FAIL_FLAG):
        # Item recovered (was a strict false-fail / re-derived / node came back) —
        # clear ONLY the exclusion WE set; never touch a rights/liveness exclusion.
        it.pop(STRICT_FAIL_FLAG, None)
        if it.get("excluded"):
            it["excluded"] = False
        it.pop("playbackReason", None)
    tally["_pass"] += 1


def apply_deltas_mode(args) -> int:
    """Merge every shard delta file onto the local catalog via the SAME
    apply_verdict logic (so the shared-flag discipline — only clear OUR own
    exclusion, never a rights/liveness one — holds at apply time even if another
    writer touched the item between the shard run and this merge)."""
    src = Path(args.apply_deltas)
    files = sorted(src.glob("**/*.json")) if src.is_dir() else [src]
    merged = {}
    for f in files:
        try:
            d = json.load(open(f))
        except (ValueError, OSError):
            print(f"[strict] skip unreadable delta {f}", flush=True)
            continue
        for k, r in d.items():
            # Latest check date wins if the same item appears in two shards.
            if k not in merged or (r.get("date") or "") >= (merged[k].get("date") or ""):
                merged[k] = r
    print(f"[strict] applying {len(merged)} deltas from {len(files)} file(s)", flush=True)

    cat, items = load_catalog()
    by_id = {it.get("archiveID"): it for it in items}
    tally = Counter()
    today = date.today().isoformat()
    for k, r in merged.items():
        it = by_id.get(k)
        if it is None:
            tally["_gone"] += 1              # item merged away/removed since the shard ran
            continue
        # An exclusion owned by ANOTHER tool (rights audit / liveness) is final —
        # never clear it on a PASS nor accumulate unavail against it. Only touch an
        # item that is unexcluded, or that WE excluded (strictFail set, so a recovery
        # can clear our own exclusion).
        if it.get("excluded") and not it.get(STRICT_FAIL_FLAG):
            continue
        apply_verdict(it, r, today, tally)

    tmp = CATALOG.with_suffix(".json.tmp")
    json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
    tmp.replace(CATALOG)
    print(f"[strict] apply done: {dict(tally)}", flush=True)

    if args.publish:
        subprocess.run([sys.executable, str(REPO / "tools" / "remediate_catalog.py")], check=False)
        subprocess.run([sys.executable, str(REPO / "tools" / "catalog_release.py"), "publish"],
                       check=True)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--concurrency", type=int, default=4,
                    help="parallel AVFoundation loads in the harness (keep LOW — "
                         "archive.org rate-limits an IP that storms its hosts)")
    ap.add_argument("--timeout", type=float, default=90,
                    help="hard per-item verification timeout (seconds) — covers the "
                         "origin load PLUS node failover within one item")
    ap.add_argument("--batch", type=int, default=40,
                    help="items per harness process (amortizes process startup)")
    ap.add_argument("--reprobe-days", type=int, default=90,
                    help="re-verify items last strict-checked longer ago than this "
                         "(0 = never re-verify)")
    ap.add_argument("--max-minutes", type=float, default=0,
                    help="stop starting new batches after this long and write what's "
                         "done (0 = no budget). Resumable: the next run continues.")
    ap.add_argument("--shard-index", type=int, default=0)
    ap.add_argument("--shard-count", type=int, default=1)
    ap.add_argument("--deltas-out", default="",
                    help="also write a compact per-item verdict delta JSON here "
                         "(for a sharded CI matrix: shards emit deltas, one publish "
                         "job merges + applies them). Ignored with --dry-run.")
    ap.add_argument("--apply-deltas", default="",
                    help="APPLY mode: merge shard delta files (a directory or a "
                         "single file) onto the local catalog, then flush (+ publish "
                         "if --publish). Skips verification entirely — the single "
                         "publish job of the CI matrix runs this.")
    ap.add_argument("--dry-run", action="store_true",
                    help="report the verdict distribution; write NOTHING")
    ap.add_argument("--publish", dest="publish", action="store_true",
                    help="catalog_release.py fetch first + publish after (CI)")
    ap.add_argument("--no-publish", dest="publish", action="store_false",
                    help="mutate local catalog.json only (default)")
    ap.set_defaults(publish=False)
    args = ap.parse_args()

    if args.publish and not args.dry_run:
        subprocess.run([sys.executable, str(REPO / "tools" / "catalog_release.py"), "fetch"],
                       check=True)

    # APPLY mode: no verification — just merge shard deltas onto the fetched
    # catalog. This is the single publish job of the CI matrix, run under the
    # catalog-writers concurrency group so it can't clobber a parallel writer.
    if args.apply_deltas:
        return apply_deltas_mode(args)

    build_harness()
    deadline = (time.monotonic() + args.max_minutes * 60) if args.max_minutes else None
    today = date.today().isoformat()

    cat, items = load_catalog()
    targets = [it for it in items
               if candidate(it, args) and shard_ok(it, args.shard_index, args.shard_count)]
    targets.sort(key=visibility, reverse=True)
    if args.limit:
        targets = targets[:args.limit]

    print(f"[strict] {len(targets)} items to verify "
          f"(shard {args.shard_index}/{args.shard_count}; concurrency {args.concurrency}; "
          f"batch {args.batch}{'; DRY-RUN' if args.dry_run else ''})", flush=True)

    tally = Counter()
    done = 0
    deltas = {}   # archiveID -> {verdict, reason, date} for HARD/PASS items only

    def flush():
        tmp = CATALOG.with_suffix(".json.tmp")
        json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
        tmp.replace(CATALOG)

    for start in range(0, len(targets), args.batch):
        if deadline and time.monotonic() > deadline:
            print("[strict] max-minutes budget reached; stopping (resumable).", flush=True)
            break
        chunk = targets[start:start + args.batch]
        batch = [{"id": it["archiveID"], "url": it.get("downloadURL"),
                  "hls": it.get("subtitleHLS")} for it in chunk]
        results = run_harness(batch, args.concurrency, args.timeout)
        for it in chunk:
            r = results.get(it["archiveID"])
            if r is None:
                tally["_no_result"] += 1          # harness produced nothing: retry next run
                continue
            if args.dry_run:
                v = r.get("verdict")
                if v in HARD_VERDICTS:
                    key, bucket = f"hard:{v}", "_hard"
                elif v in PASS_VERDICTS:
                    key, bucket = "pass", "_pass"
                elif v == UNAVAIL_VERDICT:
                    key, bucket = f"unavail:{r.get('reason') or v}", "_unavail"
                else:
                    key, bucket = f"transient:{r.get('reason') or v}", "_transient"
                tally[key] += 1
                tally[bucket] += 1
            else:
                apply_verdict(it, r, today, tally)
                v = r.get("verdict")
                # Carry HARD/PASS AND the SOFT unavail verdict in deltas so a sharded
                # CI run accumulates the confirm-across-runs counters across shards+days.
                if v in HARD_VERDICTS or v in PASS_VERDICTS or v == UNAVAIL_VERDICT:
                    deltas[it["archiveID"]] = {"verdict": v, "reason": r.get("reason"),
                                               "date": today}
            done += 1
        if not args.dry_run:
            flush()
        print(f"[{min(start + args.batch, len(targets))}/{len(targets)}] "
              f"pass={tally['_pass']} hard={tally['_hard']} unavail={tally['_unavail']} "
              f"transient={tally['_transient']} no_result={tally['_no_result']}", flush=True)

    print(f"[strict] done: {dict(tally)}", flush=True)

    if args.deltas_out and not args.dry_run:
        Path(args.deltas_out).parent.mkdir(parents=True, exist_ok=True)
        json.dump(deltas, open(args.deltas_out, "w"), separators=(",", ":"))
        print(f"[strict] wrote {len(deltas)} deltas -> {args.deltas_out}", flush=True)

    if args.publish and not args.dry_run:
        subprocess.run([sys.executable, str(REPO / "tools" / "remediate_catalog.py")], check=False)
        subprocess.run([sys.executable, str(REPO / "tools" / "catalog_release.py"), "publish"],
                       check=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
