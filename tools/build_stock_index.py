#!/usr/bin/env python3
"""build_stock_index.py — the Stock-archive SHOT index (Creation Studio #6, Decision 042).

Detects REAL shot boundaries in clippable films via ffmpeg scene detection (`scdet`) and emits
`clips.sqlite` (a `shots` table) for the macOS Creation Studio stock-shot browser — replacing the
app's synthesized placeholder windows with actual cuts. Tags come from the catalog's
genres/subjects; Apple-Vision per-shot classification + MobileCLIP semantic embeddings are the
later refinement (the `shots` schema already matches `StockIndex.swift`, so the app needs no change
to consume the real index).

Runs on a Mac/CI with ffmpeg (the cover-pipeline dependency). Popularity-first, bounded per film
for speed (decode at a low fps, cap the processed seconds), resumable via the output DB.

  python3 tools/build_stock_index.py --limit 50 --max-seconds 300
"""
import argparse
import json
import re
import sqlite3
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

try:
    import resource           # POSIX only (Linux CI + macOS) — used to cap ffmpeg memory
except ImportError:           # pragma: no cover
    resource = None

sys.path.insert(0, str(Path(__file__).resolve().parent))
import attempt_ledger as L  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"

# Bump when the detector changes, so every recorded failure gets one fresh try
# (attempt_ledger: a fixed bug deserves a retry of what it broke).
#   2 — scdet threshold 10 -> 4 (2026-11-23).
STOCK_INDEX_VERSION = 2

# scdet's score is the frame difference as a percentage of full scale, and
# ffmpeg's suggested 8-14 assumes modern, full-contrast video. Archival film is
# dim and grey: measured 2026-11-23 at the 4 fps this decodes, every real cut in
# the first five minutes of Maniac (1934), House on Haunted Hill (1959), My Man
# Godfrey (1936) and JFK's Rice University speech scored between 4 and 9, so a
# threshold of 10 found NONE of them, and 2,340 of 2,362 films a run came back
# "read it but found no scene changes". At 4 those films yield 11-13 cuts each,
# checked against the frames either side; the odd false cut (a flag waving
# across the lens) only splits a shot in two, which costs nothing.
SCDET_THRESHOLD = 4

# Per-ffmpeg virtual-memory ceiling. A single poison film (a corrupt/oversized stream that
# makes the decoder attempt a huge allocation) used to OOM the whole runner — exit 143
# "runner received a shutdown signal" mid-item, the SAME shard every 6h, downscale
# notwithstanding (runs 28278175372 / 28284290545 / 28291365967). Capping ffmpeg's own
# address space means a runaway film kills ONLY its ffmpeg (scene_cuts returns []), never the
# runner. Generous (the runner has 16 GB; a 360p scdet pass uses well under 1 GB) so it never
# false-kills a normal film, only a pathological one.
FFMPEG_MEM_CAP = 6 * 1024 ** 3


def _cap_memory():
    """preexec hook: cap the child ffmpeg's address space so a runaway film can't OOM the runner."""
    if resource is not None:
        try:
            resource.setrlimit(resource.RLIMIT_AS, (FFMPEG_MEM_CAP, FFMPEG_MEM_CAP))
        except (ValueError, OSError):
            pass


def scene_cuts(url: str, max_seconds: int, fps: float) -> tuple[list[float], str]:
    """Scene-change timestamps (seconds) via ffmpeg `scdet`, bounded for speed AND memory.

    Returns (cuts, problem). `problem` is empty when ffmpeg succeeded; otherwise it
    carries the reason, because a film ffmpeg could not OPEN and a film with no
    cuts are the same empty list — and telling them apart is the whole difference
    between "drained" and "broken". This ran four times a day producing 0 shots
    while scanning real films, and the log could not say why: the exit code was
    discarded and stderr went to a temp file that was only scanned for matches.
    Word-index hid for months behind exactly this (a mislabelled error), so the
    rule is the same one: keep the reason.
    """
    # Downscale to <=360p BEFORE scene detection. Shot boundaries don't need full resolution,
    # and decoding HD/1080i frames at full res under --concurrency blew the CI runner's RAM (the
    # kernel OOM-killer SIGTERM'd whole shards right after HD items — run 28262168655). The comma
    # inside min() is single-quoted so the filtergraph parser doesn't read it as a filter break.
    # IDENTIFY OURSELVES, AND RECONNECT. Without a User-Agent this indexed
    # nothing at all: archive.org answers datacenter clients differently, and
    # ffmpeg's default identifies nobody, so a diagnostic run came back
    # 403 Forbidden / 401 Unauthorized / 5XX / timed out on nearly every film.
    # word-index sets exactly this UA and reports zero download failures — the
    # difference between the two tools was one flag. The reconnect options are
    # the ffmpeg-level echo of Decisions 021/031: archive.org drops idle
    # connections, and a drop mid-scan should resume rather than end the film.
    # These are HTTP-protocol options and ffmpeg rejects them outright for a
    # local path ("Option not found"), so they are applied only to a real URL.
    net = (["-user_agent", "ArchiveWatch/1.0 (+https://archivewatch.org)",
            "-reconnect", "1", "-reconnect_streamed", "1", "-reconnect_delay_max", "10"]
           if url.startswith("http") else [])
    cmd = ["ffmpeg", "-nostats", "-threads", "2", *net,
           "-t", str(max_seconds), "-i", url,
           # `metadata=print` IS LOAD-BEARING. scdet SETS frame metadata; it does not
           # print it. Recent ffmpeg happens to log some of it at info level, which is
           # why this detected cuts on a dev Mac (7.1.1) and NOTHING on the runner's
           # older build — 147 of 179 films came back "read it but found no scene
           # changes" while the same films yield cuts locally. With the filter the same
           # local film goes 7 -> 14 cuts, so it was under-detecting by half even where
           # it appeared to work.
           "-vf", f"fps={fps},scale=-2:'min(360,ih)',scdet=threshold={SCDET_THRESHOLD},metadata=print",
           "-f", "null", "-"]
    # stderr → a TEMP FILE, not capture_output (which holds ALL of ffmpeg's stderr in RAM — a
    # corrupt stream spamming per-frame decode errors could balloon it and OOM the runner). The
    # file is read back line-by-line so the parse stays bounded too. preexec caps ffmpeg's own
    # memory (see FFMPEG_MEM_CAP). Both guard the deterministic single-shard OOM the owner hit.
    cuts: list[float] = []
    problem = ""
    try:
        with tempfile.TemporaryFile(mode="w+", encoding="utf-8", errors="replace") as errf:
            rc = None
            try:
                rc = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=errf,
                                    timeout=max_seconds * 4 + 90,
                                    preexec_fn=(_cap_memory if sys.platform != "win32" else None)
                                    ).returncode
            except subprocess.TimeoutExpired:
                problem = "ffmpeg timed out"   # still parse the cuts found before it
            errf.seek(0)
            tail = ""
            for line in errf:             # bounded: one line at a time, never the whole buffer
                # BOTH SEPARATORS. ffmpeg's info log writes "lavfi.scd.time: 1.23";
                # the `metadata` filter writes "lavfi.scd.time=1.23". Matching only
                # the colon meant adding the filter that finally emits the values on
                # the runner would still have parsed none of them.
                m = re.search(r"lavfi\.scd\.time[:=]\s*([\d.]+)", line)
                if m:
                    cuts.append(float(m.group(1)))
                elif line.strip() and not line.startswith("frame="):
                    tail = line.strip()[:160]
            if rc not in (0, None) and not problem:
                problem = f"ffmpeg exit {rc}: {tail}" if tail else f"ffmpeg exit {rc}"
    except Exception as e:
        problem = f"{type(e).__name__}: {e}"[:160]
    return sorted(cuts), problem


def shots_from_cuts(cuts: list[float], total: float,
                    min_len: float = 1.2, max_len: float = 20.0) -> list[tuple[float, float]]:
    """Turn cut points into usable shot windows: keep [min_len, max_len], split longer takes."""
    bounds = sorted(set([0.0] + cuts + ([total] if total else [])))
    shots: list[tuple[float, float]] = []
    for a, b in zip(bounds, bounds[1:]):
        d = b - a
        if min_len <= d <= max_len:
            shots.append((a, b))
        elif d > max_len:                       # chop a long static take into chunks
            t = a
            while t + min_len < b:
                shots.append((t, min(t + max_len, b)))
                t += max_len
    return shots


UNREADABLE = re.compile(r"\b(40[0-9]|5\d\d)\b|Error opening input|Invalid data|"
                        r"Connection|resolve|Forbidden|Not Found|Unauthorized", re.I)


def outcome_for(cuts: list[float], shots: list, problem: str) -> tuple[str, str]:
    """Name what one scan produced, so the ledger can tell a result from a breakage."""
    if shots:
        return "indexed", f"{len(shots)} shots"
    if not cuts and problem:
        return ("unreadable" if UNREADABLE.search(problem) else "error"), problem
    if cuts:
        return "no_shots", f"{len(cuts)} cuts but no usable shot window"
    return "no_shots", problem or f"no scene changes above scdet threshold {SCDET_THRESHOLD}"


ATTEMPTS_DDL = """CREATE TABLE IF NOT EXISTS attempts(
    archiveID TEXT PRIMARY KEY, outcome TEXT, reason TEXT,
    attempts INTEGER, at TEXT, v INTEGER)"""


def load_attempts(path: str) -> dict:
    """archiveID -> ledger record, from an index's `attempts` table (absent = none)."""
    if not path or not Path(path).exists():
        return {}
    con = sqlite3.connect(path)
    try:
        return {r[0]: {"outcome": r[1], "reason": r[2], "attempts": r[3], "at": r[4], "v": r[5]}
                for r in con.execute("SELECT archiveID, outcome, reason, attempts, at, v FROM attempts")}
    except sqlite3.OperationalError:
        return {}
    finally:
        con.close()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=50, help="films to add this run")
    ap.add_argument("--max-seconds", type=int, default=300, help="process up to N seconds per film")
    ap.add_argument("--fps", type=float, default=4.0, help="decode fps for scene detection (lower = faster)")
    ap.add_argument("--concurrency", type=int, default=1,
                    help="films to scan in PARALLEL (ffmpeg is network-bound, so the runner's CPU "
                         "idles on one film at a time). Total concurrent archive.org streams = "
                         "shards * concurrency — keep modest so the load-balancer doesn't 503.")
    ap.add_argument("--out", default=str(REPO / "clips.sqlite"))
    # Sharding (#7): run N runners in parallel, each over a disjoint popularity-interleaved
    # slice (stride), skipping films already in the merged index from --seen-from.
    ap.add_argument("--shard-index", type=int, default=0)
    ap.add_argument("--shard-count", type=int, default=1)
    ap.add_argument("--seen-from", default="", help="existing index to skip already-done films")
    args = ap.parse_args()

    cat = json.loads(CATALOG.read_text())
    items = [it for it in cat["items"]
             if it.get("downloadURL") and not it.get("excluded")
             and it.get("contentType") not in ("tv-series",)
             and (it.get("rightsStatus") or "public_domain") in ("public_domain", "cc", "creative_commons", "")]
    items.sort(key=lambda it: it.get("popularityScore") or it.get("downloads") or 0, reverse=True)
    if args.shard_count > 1:
        items = items[args.shard_index::args.shard_count]   # disjoint stride slice

    db = sqlite3.connect(args.out)
    db.execute("""CREATE TABLE IF NOT EXISTS shots(
        id TEXT PRIMARY KEY, archiveID TEXT, sourceURL TEXT,
        startSeconds REAL, endSeconds REAL, tags TEXT, title TEXT)""")
    # EVERY attempt is recorded here and published with the index, so the next
    # run knows what failed, why, how often, and when (attempt_ledger).
    db.execute(ATTEMPTS_DDL)
    seen = {r[0] for r in db.execute("SELECT DISTINCT archiveID FROM shots")}
    ledger = load_attempts(args.seen_from)
    ledger.update(load_attempts(args.out))
    if args.seen_from and Path(args.seen_from).exists():
        sdb = sqlite3.connect(args.seen_from)
        try:
            seen |= {r[0] for r in sdb.execute("SELECT DISTINCT archiveID FROM shots")}
        except sqlite3.OperationalError:
            pass
        sdb.close()

    def scan(it):
        """Detect a film's shots (the network-bound work; runs on a worker thread). Returns
        (it, shots) or None — NO SQLite here (writes stay single-threaded in the main loop)."""
        # Log BEFORE the scan so a runner that's OOM-killed mid-film still names the culprit in
        # its log (a successful scan logs again, with the shot count, in the main loop below).
        print(f"[stock] scanning {it['archiveID']} (rt={it.get('runtimeSeconds')})", flush=True)
        cuts, problem = scene_cuts(it["downloadURL"], args.max_seconds, args.fps)
        shots = []
        if cuts:
            rt = it.get("runtimeSeconds") or 0
            total = min(rt, args.max_seconds) if rt else args.max_seconds
            shots = shots_from_cuts(cuts, total)
        outcome, reason = outcome_for(cuts, shots, problem)
        if not shots:
            # SAY WHY. "no cuts" from a film that played and "no cuts" from a
            # film ffmpeg never opened look identical, and only one is a result.
            print(f"[stock] {it['archiveID']}: {outcome} — {reason}", flush=True)
        return it, shots, outcome, reason

    def write(it, shots):
        aid, url = it["archiveID"], it["downloadURL"]
        # Discrete, clean, pipe-joined tags (drop sentence-long / punctuation-y subjects) so the
        # app shows readable chips and search works — NOT one hyphen-mangled token.
        tags = "|".join(
            t.strip().lower() for t in ((it.get("genres") or []) + (it.get("subjects") or [])[:2])
            if t and len(t.strip()) <= 22 and ":" not in t and ";" not in t)[:200]
        for i, (s, e) in enumerate(shots):
            db.execute("INSERT OR REPLACE INTO shots VALUES(?,?,?,?,?,?,?)",
                       (f"{aid}#{i}", aid, url, s, e, tags, it.get("title", "")))
        db.commit()

    pending = [it for it in items if it["archiveID"] not in seen]
    now = L.now_utc()
    eligible, backoff, capped = L.partition(
        ((it, ledger.get(it["archiveID"])) for it in pending), now, STOCK_INDEX_VERSION)
    candidates = eligible
    print(L.summary("stock", len(eligible), len(backoff), [it["archiveID"] for it in capped],
                    done_already=len(items) - len(pending)), flush=True)
    outcomes: dict[str, int] = {}

    def remember(it, outcome, reason):
        aid = it["archiveID"]
        rec = L.record(ledger.get(aid), outcome, reason, now, STOCK_INDEX_VERSION)
        ledger[aid] = rec
        db.execute("INSERT OR REPLACE INTO attempts VALUES(?,?,?,?,?,?)",
                   (aid, rec["outcome"], rec["reason"], rec["attempts"], rec["at"], rec["v"]))
        db.commit()
        outcomes[outcome] = outcomes.get(outcome, 0) + 1

    done = 0
    workers = max(1, args.concurrency)
    with ThreadPoolExecutor(max_workers=workers) as ex:
        inflight, idx = set(), 0
        while idx < len(candidates) and len(inflight) < workers:    # prime the pool
            inflight.add(ex.submit(scan, candidates[idx])); idx += 1
        while inflight and done < args.limit:
            fut = next(as_completed(inflight))
            inflight.discard(fut)
            it, shots, outcome, reason = fut.result()
            if shots:
                write(it, shots)
                done += 1
                print(f"[stock] {it['archiveID']}: {len(shots)} shots ({done}/{args.limit})", flush=True)
            remember(it, outcome, reason)
            if idx < len(candidates) and done < args.limit:         # keep the pool full
                inflight.add(ex.submit(scan, candidates[idx])); idx += 1
        # Stop scanning the in-flight remainder once the quota is met (don't waste decode time).
        ex.shutdown(wait=False, cancel_futures=True)

    n = db.execute("SELECT count(*) FROM shots").fetchone()[0]
    print(f"[stock] +{done} films this run; {n} shots total in {args.out}")
    print("[stock] outcomes: " + (", ".join(f"{k} {v}" for k, v in sorted(outcomes.items())) or "none"),
          flush=True)
    if done == 0 and candidates:
        print(f"[stock] WARNING: scanned films and indexed NONE. If every line above "
              f"names an ffmpeg error, this is a fetch problem, not an empty backlog.",
              flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
