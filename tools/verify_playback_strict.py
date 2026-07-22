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
On a HARD verdict (GENUINELY-universal media problem: nil URL, no tracks, or a
`truncated` no-moov / mdat>file) it ALSO sets excluded=True + strictFail=True +
playbackReason so build_sqlite's existing `excluded` gate hides the item everywhere
— but ONLY on a hard verdict, NEVER on a transient one (bias against false-excluding
a playable film: a wrongly-hidden film is the costly error).

APPLE-SPECIFIC failures are NOT blind-excluded (the 2026-07 -11829 false-exclude
fix): the harness's container/parse "media damaged" (apple_container_error) and
decode/codec verdicts are ffprobe-disambiguated here (disambiguate_apple) into
  * faststart-quirk  -> needsFaststart=True, NOT excluded (valid H.264 moov-at-EOF
                        that AVFoundation-over-HTTP rejects but ffmpeg/Android/web
                        read fine; feeds a later faststart-remux pass);
  * truncated        -> excluded + needsReSource=True (no moov / mdat>file: broken
                        everywhere, genuinely unplayable);
  * exotic_codec     -> applePlayable=False advisory, NOT global-excluded (legacy
                        codec Apple won't play but ExoPlayer/browsers will).
`--reverify-strictfail` force-re-verifies the current strictFail set (ignoring the
TTL + excluded gate) to correct prior false-excludes after a mapping change.
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
import shutil
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

# GENUINELY-UNIVERSAL media problems -> exclude on every platform immediately.
# These mean the file has NO playable video ANYWHERE (nil URL, no tracks) or is
# truncated (no moov / mdat > file). `truncated` is produced by the ffprobe
# disambiguation below, not emitted by the harness. Kept in lock-step with
# PlaybackVerifierCLI/main.swift + disambiguate_apple().
HARD_VERDICTS = {
    "url_invalid", "not_playable", "no_video_track", "truncated",
}
# PASS is either a first-node success or a recovery on an alternate storage node.
PASS_VERDICTS = {"ok", "ok_failover"}

# AVFoundation-SPECIFIC playback failures. These are NOT proof the file is broken
# everywhere: -11829/-11828/-11833 (apple_container_error) are container/parse
# "damaged" errors that a valid H.264 film with a non-faststart moov-at-EOF layout
# returns over HTTP yet plays fine on Android/web and after a local faststart remux.
# On ANY of these we run ffprobe (disambiguate_apple) to decide faststart-quirk
# (keep) vs truncated (exclude) vs exotic-codec (Apple-advisory, keep) — NEVER a
# blind global exclude. decode_failed/unsupported_codec/failed_permanent are folded
# in for the same reason (Apple couldn't play it -> verify with ffprobe, don't hide).
APPLE_DISAMBIG_VERDICTS = {
    "apple_container_error", "decode_failed", "unsupported_codec", "failed_permanent",
}

# ffprobe video-codec classification. A UNIVERSAL codec that ffprobe can read means
# the file is fine everywhere and Apple's rejection is the moov/faststart quirk. An
# EXOTIC/legacy codec is one Apple won't play but ExoPlayer/browsers usually will.
UNIVERSAL_VIDEO = {"h264", "hevc", "h265", "mpeg1video", "mpeg2video", "vp8", "vp9", "av1"}
EXOTIC_VIDEO = {"mpeg4", "msmpeg4v1", "msmpeg4v2", "msmpeg4v3", "wmv1", "wmv2", "wmv3",
                "rv10", "rv20", "rv30", "rv40", "vp6", "vp6f", "vp6a", "flv1", "theora"}

# The ONLY ffprobe stderr signature we trust as a structural truncation signal is a
# missing moov atom — and only when it PERSISTS across retries (see below). Broader
# markers like "Invalid data found" are deliberately NOT trusted: under archive.org
# load, a 5XX HTML error body fed to ffprobe surfaces as "Invalid data found",
# which would false-exclude a perfectly playable film. The authoritative truncation
# signal is the structural mdat>file check (_mdat_exceeds_file).
_NO_MOOV_MARKER = "moov atom not found"


def _ffprobe_streams(url, timeout=90):
    """Run ffprobe on the URL. Returns None if ffprobe is unavailable (caller then
    biases to NOT excluding), else (ok, video_codec, format_name, err) where
    ok=False means ffprobe could not read/demux the file (moov not found, etc.)."""
    exe = shutil.which("ffprobe")
    if not exe:
        return None
    try:
        p = subprocess.run(
            [exe, "-v", "error",
             "-show_entries", "stream=codec_type,codec_name",
             "-show_entries", "format=format_name",
             "-of", "json", url],
            capture_output=True, text=True, timeout=timeout)
    except (subprocess.TimeoutExpired, OSError) as e:
        return (False, None, None, f"ffprobe_error:{e}")
    if p.returncode != 0:
        return (False, None, None, (p.stderr or "").strip()[-200:])
    try:
        j = json.loads(p.stdout or "{}")
    except ValueError:
        return (False, None, None, "ffprobe_bad_json")
    vcodec = None
    for s in j.get("streams", []):
        if s.get("codec_type") == "video" and not vcodec:
            vcodec = (s.get("codec_name") or "").lower()
    fmt = (j.get("format", {}) or {}).get("format_name")
    return (True, vcodec, fmt, "")


def _mdat_exceeds_file(url, timeout=45):
    """True iff the top-level `mdat` box declares more bytes than the file actually
    has — a truncated non-faststart MP4 (e.g. The General Line: mdat=413.6 MB, file
    179.8 MB, no moov). Best-effort: any uncertainty -> False (ffprobe demux is the
    primary truncation signal; this is a belt-and-suspenders secondary)."""
    try:
        import requests
    except ImportError:
        return False
    try:
        total = 0
        h = requests.head(url, allow_redirects=True, timeout=timeout)
        total = int(h.headers.get("Content-Length") or 0)
        if total <= 0:
            g = requests.get(url, stream=True, allow_redirects=True, timeout=timeout,
                             headers={"Range": "bytes=0-0"})
            cr = g.headers.get("Content-Range", "")
            g.close()
            if "/" in cr:
                total = int(cr.rsplit("/", 1)[-1])
        if total <= 0:
            return False
        g = requests.get(url, stream=True, allow_redirects=True, timeout=timeout,
                         headers={"Range": "bytes=0-262143"})
        head = g.content
        g.close()
        off = 0
        while off + 8 <= len(head):
            size = int.from_bytes(head[off:off + 4], "big")
            typ = head[off + 4:off + 8]
            if size == 1:  # 64-bit largesize
                if off + 16 > len(head):
                    break
                size = int.from_bytes(head[off + 8:off + 16], "big")
            if typ == b"mdat":
                return size > 1 and size > total
            if size <= 0:
                break
            off += size
        return False
    except Exception:
        return False


def disambiguate_apple(url):
    """Classify an AVFoundation-specific playback failure via ffprobe. Returns
    (kind, detail) where kind is one of:
      * 'faststart'    — universal codec, ffprobe reads it (or ffprobe/ambiguous):
                          DON'T exclude; the file is fine, Apple just needs a
                          faststart remux (moov-at-EOF quirk). Plays on Android/web.
      * 'truncated'    — ffprobe cannot demux it OR mdat > file: genuinely broken
                          everywhere -> exclude, re-source needed.
      * 'exotic_codec' — legacy codec Apple won't play but ExoPlayer/browsers will:
                          Apple-advisory (applePlayable=false), DON'T global-exclude.
    A fourth kind, 'retry', means ffprobe failed with a TRANSIENT (network/5XX)
    error — no verdict, re-check next run. Biases to 'faststart'/'retry'
    (non-excluding) whenever ffprobe is unavailable/ambiguous."""
    if not url:
        return ("faststart", "no_url")
    # 1) Structural truncation — authoritative, immune to transient 5XX HTML bodies.
    if _mdat_exceeds_file(url):
        return ("truncated", "mdat_exceeds_file")

    # 2) ffprobe, with retries. "moov atom not found" is the only trusted truncation
    #    marker, and only when it PERSISTS (a 5XX under load never yields it twice).
    probe = None
    no_moov_hits = 0
    for attempt in range(4):
        probe = _ffprobe_streams(url)
        if probe is None:
            return ("faststart", "ffprobe_unavailable")  # never blind-exclude
        ok, vcodec, fmt, err = probe
        if ok:
            break
        if _NO_MOOV_MARKER in (err or "").lower():
            no_moov_hits += 1
        # Transient (Server returned 5XX / timeout / connection) — back off + retry.
        if attempt < 3:
            time.sleep(2 + attempt * 4)

    ok, vcodec, fmt, err = probe
    if not ok:
        # A PERSISTENT no-moov failure (>= 2 attempts) is a genuinely truncated /
        # moov-less file -> truncated. Any other exhausted failure is transient
        # (network/5XX) -> retry next run. NEVER exclude on a network blip.
        if no_moov_hits >= 2:
            return ("truncated", f"no_moov_persistent:{(err or '')[:120]}")
        return ("retry", f"ffprobe_transient:{(err or '')[:140]}")
    if vcodec in EXOTIC_VIDEO:
        return ("exotic_codec", f"codec={vcodec}")
    if vcodec in UNIVERSAL_VIDEO:
        return ("faststart", f"codec={vcodec};fmt={fmt}")
    # ffprobe read the container but the codec is unknown/absent -> ambiguous.
    # Bias to NOT excluding (a maybe-playable film must never be hidden).
    return ("faststart", f"codec={vcodec or '?'};fmt={fmt}")

# SOFT persistent-unavailability: the harness failed over across EVERY known storage
# node and none served the media (the app's own failover would also fail). This is
# NOT a hard exclude — a single all-nodes failure can be an archive.org-wide blip or
# an item mid-rotation. We only exclude once it recurs across separate runs spanning
# multiple days (confirm-across-runs), so a transient outage never hides a film.
UNAVAIL_VERDICT = "unavailable_all_nodes"
UNAVAIL_COUNT_THRESHOLD = 3     # all-nodes failures on >= this many distinct days
UNAVAIL_SPAN_DAYS = 2           # ... spanning >= this many calendar days
UNAVAIL_REASON = "persistently_unavailable"

# Run-level INFRA circuit breaker. A single item that fails all its storage nodes
# is a per-item signal (mark_unavailable accumulates it across days). But if a
# LARGE FRACTION of a whole run verdicts `unavailable_all_nodes`, that is not N
# independent dead films — it is archive.org rate-limiting our runner's IP (or an
# archive.org-wide blip), and every unavail verdict that run is untrustworthy. On
# a healthy run the all-nodes-unavail rate is ~3% (measured: 170/6000 on a real
# run). When it exceeds this fraction we treat the run as infra-affected and do NOT
# touch the per-item unavail counters/timestamps/exclusions for ANY unavail item
# that run (they stay exactly as they were, to be re-checked next run). HARD media
# verdicts (bad codec / no video track) still apply — a bad file isn't infra.
UNAVAIL_CIRCUIT_BREAKER_FRAC = 0.15


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


def _breaker(n_unavail, n_hard, n_pass):
    """Run-level infra guard. Returns (fraction, tripped) where the fraction is
    unavail over all DECIDED verdicts (hard+pass+unavail) and tripped is True when
    it exceeds UNAVAIL_CIRCUIT_BREAKER_FRAC. Transient/no-result verdicts are not
    'decided' and never counted (they carry no unavail signal)."""
    decided = n_unavail + n_hard + n_pass
    frac = (n_unavail / decided) if decided else 0.0
    return frac, frac > UNAVAIL_CIRCUIT_BREAKER_FRAC


def _log_breaker(frac):
    print(f"[strict] CIRCUIT BREAKER: unavail {frac:.0%} > "
          f"{UNAVAIL_CIRCUIT_BREAKER_FRAC:.0%} — treating as infra, no unavail "
          f"counters/exclusions this run", flush=True)


def apply_apple_disambig(it, check_date, tally):
    """An AVFoundation-specific failure -> ffprobe-disambiguate, then:
      * truncated    -> reversible global exclude (needsReSource), stays hidden.
      * faststart    -> NOT excluded (needsFaststart flag feeds a later remux pass);
                        clears any strict exclusion WE set.
      * exotic_codec -> NOT global-excluded (applePlayable=false advisory); clears
                        any strict exclusion WE set — still visible on Android/web.
    Never a blind exclude — this is the whole point of the false-exclude fix."""
    kind, detail = disambiguate_apple(it.get("downloadURL"))

    if kind == "retry":
        # Transient ffprobe failure — no verdict. Leave the item EXACTLY as-is
        # (no strictCheckedAt stamp) so candidate() re-checks it next run. A
        # strictFail item stays excluded until a clean probe; never hidden anew,
        # never wrongly un-hidden.
        tally["transient:apple_ffprobe_retry"] += 1
        tally["_transient"] += 1
        return

    it["strictCheckedAt"] = check_date

    if kind == "truncated":
        it["strictVerified"] = False
        it[STRICT_FAIL_FLAG] = True
        it["excluded"] = True
        it["strictReason"] = "truncated_no_moov"
        it["needsReSource"] = True
        it["playbackReason"] = "strict_truncated_no_moov"
        it.pop("needsFaststart", None)
        it.pop("applePlayable", None)
        tally["hard:truncated"] += 1
        tally["_hard"] += 1
        return

    # From here the item is NOT excluded. Set the advisory flag and clear any
    # strict exclusion / unavail counters WE previously set (never another tool's).
    if kind == "exotic_codec":
        it["strictReason"] = "apple_unsupported_codec"
        it["applePlayable"] = False        # Apple-only advisory; visible on Android/web
        it.pop("needsFaststart", None)
        tally["advisory:apple_unsupported_codec"] += 1
    else:  # faststart
        it["strictReason"] = "apple_faststart_quirk"
        it["needsFaststart"] = True        # feeds a later faststart-remux pass
        it.pop("applePlayable", None)
        tally["advisory:apple_faststart_quirk"] += 1

    it["strictVerified"] = True
    it.pop("needsReSource", None)
    _clear_unavail(it)
    if it.get(STRICT_FAIL_FLAG):
        # Recovered from a prior (false) strict exclusion — clear ONLY the exclusion
        # WE set; never touch a rights/liveness exclusion owned by another tool.
        it.pop(STRICT_FAIL_FLAG, None)
        if it.get("excluded"):
            it["excluded"] = False
        it.pop("playbackReason", None)
    tally["_pass"] += 1


def apply_verdict(it, r, today, tally, unavail_infra=False):
    """Write additive strict flags. HARD -> reversible exclude; UNAVAIL -> accumulate
    a confirm-across-runs counter (exclude only when persistently dead); PASS -> clear
    a strict exclusion WE set; TRANSIENT -> leave unverified (retry next run).
    `today` is the ISO date to stamp (the delta's own check date when re-applying a
    shard delta, so strictCheckedAt reflects when the check actually ran).
    `unavail_infra` (the run-level circuit breaker tripped) makes an UNAVAIL verdict
    a no-op — the item is left EXACTLY as it was (no counter, no timestamp, no
    exclusion), because the whole run's unavailability is IP-throttle noise, not a
    real per-item signal. HARD/PASS still apply (a bad codec isn't an infra problem)."""
    verdict = r.get("verdict")
    reason = r.get("reason") or verdict
    check_date = r.get("date") or today

    if verdict == UNAVAIL_VERDICT:
        if unavail_infra:
            tally["infra_unavail"] += 1          # breaker tripped: leave item as-is
            return
        mark_unavailable(it, check_date, tally)
        return
    if verdict in APPLE_DISAMBIG_VERDICTS:
        # AVFoundation-specific failure — ffprobe decides keep vs exclude. NEVER a
        # blind global exclude (the -11829 "media damaged" false-exclude fix).
        apply_apple_disambig(it, check_date, tally)
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

    # Run-level infra circuit breaker: the whole-run unavail fraction is known here
    # (this job sees the MERGED delta set from every shard), so this is where the
    # breaker belongs for the sharded CI matrix.
    n_unavail = sum(1 for r in merged.values() if r.get("verdict") == UNAVAIL_VERDICT)
    n_hard = sum(1 for r in merged.values() if r.get("verdict") in HARD_VERDICTS)
    n_pass = sum(1 for r in merged.values() if r.get("verdict") in PASS_VERDICTS)
    frac, breaker = _breaker(n_unavail, n_hard, n_pass)
    if breaker:
        _log_breaker(frac)
    else:
        print(f"[strict] unavail {frac:.0%} of {n_unavail + n_hard + n_pass} decided "
              f"(<= {UNAVAIL_CIRCUIT_BREAKER_FRAC:.0%}) — applying normally", flush=True)

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
        apply_verdict(it, r, today, tally, unavail_infra=breaker)

    if args.dry_run:
        # --apply-deltas --dry-run: report the breaker decision + verdict tally,
        # write NOTHING (the in-memory mutations above are discarded).
        print(f"[strict] apply DRY-RUN (no write): {dict(tally)}", flush=True)
        return 0

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
    ap.add_argument("--reverify-strictfail", action="store_true",
                    help="Force re-verify EVERY item this tool previously "
                         "strict-EXCLUDED (strictFail=True), ignoring the reprobe "
                         "TTL and the excluded gate. Corrects false-excludes after a "
                         "verdict-mapping change (e.g. the -11829 container-error "
                         "fix): the harness re-runs and the ffprobe disambiguation "
                         "un-hides faststart-quirk films + re-labels the truncated ones.")
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
    if args.reverify_strictfail:
        # Force-reverify the CURRENT strict-excluded set — ignore the TTL + excluded
        # gate (these are exactly the items candidate() would skip because they were
        # just checked). This catches ALL strictFail items (the named 6 plus any
        # extras a cancelled OLD-code run may have hidden).
        targets = [it for it in items
                   if it.get(STRICT_FAIL_FLAG) and it.get("downloadURL")
                   and shard_ok(it, args.shard_index, args.shard_count)]
    else:
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
    deltas = {}   # archiveID -> {verdict, reason, date} for HARD/PASS/UNAVAIL items
    # UNAVAIL decisions are DEFERRED until the whole run is done: the run-level
    # circuit breaker (unavail fraction over all decided verdicts) can only be judged
    # once, and a same-run breaker must apply to every unavail item that run. HARD/PASS
    # are applied streaming (they never depend on the run fraction).
    unavail_pending = []   # (item, check_date)

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
            v = r.get("verdict")
            if args.dry_run:
                if v in HARD_VERDICTS:
                    key, bucket = f"hard:{v}", "_hard"
                elif v in PASS_VERDICTS:
                    key, bucket = "pass", "_pass"
                elif v in APPLE_DISAMBIG_VERDICTS:
                    # Report the ffprobe outcome so a dry-run shows keep-vs-exclude.
                    kind, _ = disambiguate_apple(it.get("downloadURL"))
                    key = f"apple:{v}->{kind}"
                    bucket = "_hard" if kind == "truncated" else "_apple"
                elif v == UNAVAIL_VERDICT:
                    key, bucket = f"unavail:{r.get('reason') or v}", "_unavail"
                else:
                    key, bucket = f"transient:{r.get('reason') or v}", "_transient"
                tally[key] += 1
                tally[bucket] += 1
            else:
                if v == UNAVAIL_VERDICT:
                    unavail_pending.append((it, r.get("date") or today))
                else:
                    apply_verdict(it, r, today, tally)
                # Carry HARD/PASS, the APPLE-disambig verdicts, AND the SOFT unavail
                # verdict in deltas so a sharded CI run re-disambiguates + accumulates
                # the confirm-across-runs counters across shards+days at apply time.
                if (v in HARD_VERDICTS or v in PASS_VERDICTS or v == UNAVAIL_VERDICT
                        or v in APPLE_DISAMBIG_VERDICTS):
                    deltas[it["archiveID"]] = {"verdict": v, "reason": r.get("reason"),
                                               "date": today}
            done += 1
        if not args.dry_run:
            flush()
        print(f"[{min(start + args.batch, len(targets))}/{len(targets)}] "
              f"pass={tally['_pass']} hard={tally['_hard']} "
              f"unavail={len(unavail_pending) if not args.dry_run else tally['_unavail']} "
              f"transient={tally['_transient']} no_result={tally['_no_result']}", flush=True)

    # Resolve the deferred UNAVAIL items with the run-level circuit breaker now that
    # the whole run's fraction is known (a non-sharded direct run applies here; a
    # sharded CI run re-decides the merged fraction in apply_deltas_mode).
    if args.dry_run:
        frac, tripped = _breaker(tally["_unavail"], tally["_hard"], tally["_pass"])
        if tripped:
            _log_breaker(frac)
        else:
            print(f"[strict] unavail {frac:.0%} of decided (<= "
                  f"{UNAVAIL_CIRCUIT_BREAKER_FRAC:.0%}) — would apply normally", flush=True)
    elif unavail_pending:
        frac, tripped = _breaker(len(unavail_pending), tally["_hard"], tally["_pass"])
        if tripped:
            _log_breaker(frac)
            tally["infra_unavail"] += len(unavail_pending)   # leave every item as-is
        else:
            for it, cd in unavail_pending:
                mark_unavailable(it, cd, tally)
        flush()

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
