#!/usr/bin/env python3
"""
faststart_remux.py — FIX the moov-at-EOF films that AVFoundation-over-HTTP rejects
(-11829, the owner's "resource unavailable on Apple" + start-stutter class) by
generating a lossless faststart remux and HOSTING it on archive.org.

Background: tools/verify_playback_strict.py flags valid H.264 films whose `moov`
atom sits at EOF as needsFaststart=True. AVFoundation-over-HTTP returns
AVErrorFailedToParse (-11829) on them and they stutter on start; ffmpeg/Android/web
read them fine. Archive.org has NO `.ia.mp4` derivative for these (it skips
deriving a second MP4 when the upload is already H.264), so repair_derivatives.py
has nothing to swap to — the ONLY fix is to relocate the moov to the front and host
the result. This tool does exactly that:

  download current downloadURL  ->  ffmpeg -c copy -movflags +faststart  ->
  ffprobe-validate (moov-before-mdat + streams identical + duration matches)  ->
  upload to archive.org item `archivewatch-faststart` via IAS3  ->
  re-point downloadURL + set faststartRemuxed=true + clear needsFaststart/applePlayable.

The remux is LOSSLESS (`-c copy` copies the video+audio streams byte-for-byte and
only moves the moov box) — bitrate/quality are identical to the original, honoring
the no-bitrate-ceiling goal (Decision 021). It NEVER touches a needsReSource
(truncated) item — those are incomplete and a remux cannot fix them.

Hosting mirrors Decision 023 / upload_covers.py: one archive.org item holds every
remux, each at a stable public URL
    https://archive.org/download/archivewatch-faststart/<name>.mp4
fetched by every client via URLSession/<video> (no CORS concern). Credentials come
from the environment ONLY (never committed):
    IAS3_ACCESS_KEY, IAS3_SECRET_KEY
In CI add them as GitHub Actions secrets of the same name. LOCAL runs without creds
can still download + remux + validate (use --dry-run, or they'll stop before upload).

Resumable: a manifest (tools/faststart_out/manifest.jsonl) + an upload log
(uploaded.jsonl) let re-runs skip items already remuxed+uploaded. Additive +
reversible: the original archive.org item is untouched; clearing faststartRemuxed +
restoring the old downloadURL fully reverts.

Usage:
    export IAS3_ACCESS_KEY=...  IAS3_SECRET_KEY=...
    python tools/faststart_remux.py                     # all needsFaststart items
    python tools/faststart_remux.py --ids A,B --limit 2
    python tools/faststart_remux.py --dry-run           # download+remux+validate, no upload
    python tools/faststart_remux.py --keep-local        # keep the remuxed mp4 on disk
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
OUT_DIR = REPO / "tools" / "faststart_out"
S3 = "https://s3.us.archive.org"
DEFAULT_ITEM = "archivewatch-faststart"
BASE_URL = "https://archive.org/download"

# Duration is allowed to differ by at most this (a container remux can nudge the
# reported duration by a frame or two; a real mismatch means we grabbed the wrong
# bytes / a truncated download).
DURATION_TOL_S = 1.5
DURATION_TOL_FRAC = 0.01


# ---------------------------------------------------------------------------
# IAS3 upload (mirrors upload_covers.py)
# ---------------------------------------------------------------------------

def _auth() -> str | None:
    ak = os.environ.get("IAS3_ACCESS_KEY")
    sk = os.environ.get("IAS3_SECRET_KEY")
    if not ak or not sk:
        return None
    return f"LOW {ak}:{sk}"


def ensure_item(item: str, auth: str) -> None:
    """Create the bucket with item-level metadata (idempotent)."""
    req = urllib.request.Request(f"{S3}/{item}", method="PUT", data=b"")
    req.add_header("authorization", auth)
    req.add_header("x-amz-auto-make-bucket", "1")
    req.add_header("x-archive-meta-mediatype", "movies")
    req.add_header("x-archive-meta-collection", "opensource_movies")
    req.add_header("x-archive-meta-title", "Archive Watch - faststart-remuxed films")
    req.add_header("x-archive-meta-creator", "Archive Watch")
    req.add_header("x-archive-meta-licenseurl", "https://creativecommons.org/publicdomain/mark/1.0/")
    req.add_header("x-archive-meta-description",
                   "Lossless faststart remuxes (moov atom relocated to the front, "
                   "streams copied byte-for-byte) of public-domain / CC0 films whose "
                   "original archive.org upload has its moov atom at EOF, which "
                   "AVFoundation-over-HTTP cannot start. Video/audio quality is "
                   "identical to the source item; only the MP4 box order changed.")
    req.add_header("x-archive-queue-derive", "0")
    try:
        urllib.request.urlopen(req, timeout=60)
        print(f"[faststart] ensured item '{item}'")
    except urllib.error.HTTPError as e:
        if e.code in (409,):
            print(f"[faststart] item '{item}' already exists")
        else:
            body = e.read().decode("utf-8", "replace")[:300]
            print(f"[faststart] ensure_item HTTP {e.code}: {body}", file=sys.stderr)
            if e.code in (401, 403):
                sys.exit("[faststart] auth rejected — check IAS3 keys")


def put_file(item: str, local: Path, remote: str, auth: str, retries: int = 4) -> bool:
    data = local.read_bytes()
    for attempt in range(1, retries + 1):
        req = urllib.request.Request(f"{S3}/{item}/{remote}", method="PUT", data=data)
        req.add_header("authorization", auth)
        req.add_header("content-type", "video/mp4")
        req.add_header("x-archive-queue-derive", "0")
        req.add_header("x-archive-keep-old-version", "0")
        try:
            urllib.request.urlopen(req, timeout=600)
            return True
        except urllib.error.HTTPError as e:
            if e.code == 503 and attempt < retries:   # slow down / reduce request rate
                time.sleep(min(2 ** attempt, 30))
                continue
            print(f"[faststart] upload {remote} HTTP {e.code}: "
                  f"{e.read().decode('utf-8','replace')[:200]}", file=sys.stderr)
            return False
        except (urllib.error.URLError, TimeoutError) as e:
            if attempt < retries:
                time.sleep(min(2 ** attempt, 30))
                continue
            print(f"[faststart] upload {remote} error: {e}", file=sys.stderr)
            return False
    return False


# ---------------------------------------------------------------------------
# Remux + validation
# ---------------------------------------------------------------------------

def remote_name(archive_id: str) -> str:
    """Deterministic, URL/S3-safe object name for an item's remux. Same id -> same
    name every run, so a re-run overwrites in place and the re-pointed URL is stable."""
    slug = re.sub(r"[^A-Za-z0-9._-]", "_", archive_id).strip("._-") or "item"
    return f"{slug}.mp4"


def download_original(url: str, dest: Path, timeout: int = 120, retries: int = 3) -> bool:
    """Stream the current downloadURL to dest. archive.org 302-redirects to a storage
    node; requests follows it. Retries a transient network failure."""
    try:
        import requests
    except ImportError:
        sys.exit("[faststart] pip install requests")
    for attempt in range(1, retries + 1):
        try:
            with requests.get(url, stream=True, allow_redirects=True, timeout=timeout,
                              headers={"User-Agent": "ArchiveWatch-Faststart/1.0"}) as r:
                if r.status_code != 200:
                    print(f"[faststart] download HTTP {r.status_code} (attempt {attempt})",
                          file=sys.stderr)
                    if attempt < retries:
                        time.sleep(3 * attempt)
                        continue
                    return False
                with open(dest, "wb") as f:
                    for chunk in r.iter_content(chunk_size=1 << 20):
                        if chunk:
                            f.write(chunk)
            return dest.exists() and dest.stat().st_size > 0
        except Exception as e:  # noqa: BLE001 — network is broad; retry then give up
            print(f"[faststart] download error (attempt {attempt}): {e}", file=sys.stderr)
            if attempt < retries:
                time.sleep(3 * attempt)
                continue
            return False
    return False


def ffmpeg_faststart(src: Path, dst: Path) -> bool:
    """Lossless remux: copy every stream, relocate the moov to the front. NO
    re-encode -> identical bitrate/quality (Decision 021)."""
    exe = shutil.which("ffmpeg")
    if not exe:
        sys.exit("[faststart] ffmpeg not found on PATH")
    p = subprocess.run(
        [exe, "-y", "-v", "error", "-i", str(src),
         "-map", "0", "-c", "copy", "-movflags", "+faststart", str(dst)],
        capture_output=True, text=True)
    if p.returncode != 0:
        print(f"[faststart] ffmpeg failed: {(p.stderr or '')[:400]}", file=sys.stderr)
        return False
    return dst.exists() and dst.stat().st_size > 0


def first_box_after_ftyp(path: Path) -> str | None:
    """Return the type of the first top-level box AFTER `ftyp` (walking only the tiny
    box headers, never reading the huge mdat). 'moov' here == faststart."""
    try:
        with open(path, "rb") as f:
            head = f.read(1 << 16)   # 64 KB is plenty to pass ftyp (ftyp is tiny)
    except OSError:
        return None
    off = 0
    seen_ftyp = False
    while off + 8 <= len(head):
        size = int.from_bytes(head[off:off + 4], "big")
        typ = head[off + 4:off + 8].decode("latin-1", "replace")
        if size == 1:   # 64-bit largesize
            if off + 16 > len(head):
                break
            size = int.from_bytes(head[off + 8:off + 16], "big")
        if typ == "ftyp":
            seen_ftyp = True
            if size <= 0:
                break
            off += size
            # The very next box header:
            if off + 8 <= len(head):
                return head[off + 4:off + 8].decode("latin-1", "replace")
            return None
        # No ftyp (rare) — the first box itself is the answer.
        if not seen_ftyp:
            return typ
        if size <= 0:
            break
        off += size
    return None


def ffprobe_summary(url_or_path: str, timeout: int = 120):
    """(video_codec, sorted audio_codecs, duration_seconds) or None on probe failure."""
    exe = shutil.which("ffprobe")
    if not exe:
        sys.exit("[faststart] ffprobe not found on PATH")
    try:
        p = subprocess.run(
            [exe, "-v", "error",
             "-show_entries", "stream=codec_type,codec_name",
             "-show_entries", "format=duration",
             "-of", "json", url_or_path],
            capture_output=True, text=True, timeout=timeout)
    except (subprocess.TimeoutExpired, OSError) as e:
        print(f"[faststart] ffprobe error: {e}", file=sys.stderr)
        return None
    if p.returncode != 0:
        print(f"[faststart] ffprobe rc={p.returncode}: {(p.stderr or '')[:200]}", file=sys.stderr)
        return None
    try:
        j = json.loads(p.stdout or "{}")
    except ValueError:
        return None
    vcodec = None
    acodecs = []
    for s in j.get("streams", []):
        t = s.get("codec_type")
        name = (s.get("codec_name") or "").lower()
        if t == "video" and not vcodec:
            vcodec = name
        elif t == "audio":
            acodecs.append(name)
    dur = None
    try:
        dur = float((j.get("format") or {}).get("duration"))
    except (TypeError, ValueError):
        dur = None
    return (vcodec, sorted(acodecs), dur)


def validate_remux(original_url: str, out_path: Path):
    """Confirm the remux is a faithful faststart copy. Returns (ok, reason, detail)."""
    # 1) moov must now precede mdat.
    box = first_box_after_ftyp(out_path)
    if box != "moov":
        return (False, "moov_not_first", f"first box after ftyp = {box!r} (expected moov)")

    out = ffprobe_summary(str(out_path))
    if out is None:
        return (False, "output_unprobable", "ffprobe could not read the remuxed file")
    orig = ffprobe_summary(original_url)
    if orig is None:
        # Can't compare streams (origin unreachable now) — the output is still a
        # valid, faststart, probable MP4. Accept but flag that streams weren't diffed.
        return (True, "ok_no_origin_compare",
                f"out video={out[0]} audio={out[1]} dur={out[2]}; origin unprobable")

    ov, oa, od = orig
    nv, na, nd = out
    if nv != ov:
        return (False, "video_codec_changed", f"origin={ov} out={nv}")
    if na != oa:
        return (False, "audio_codec_changed", f"origin={oa} out={na}")
    if od and nd:
        tol = max(DURATION_TOL_S, od * DURATION_TOL_FRAC)
        if abs(od - nd) > tol:
            return (False, "duration_mismatch", f"origin={od:.2f}s out={nd:.2f}s tol={tol:.2f}s")
    return (True, "ok", f"video={nv} audio={na} dur={nd}")


# ---------------------------------------------------------------------------
# Manifest / catalog
# ---------------------------------------------------------------------------

def load_done(uploaded_log: Path) -> set[str]:
    done: set[str] = set()
    if uploaded_log.exists():
        for line in open(uploaded_log):
            line = line.strip()
            if line:
                try:
                    done.add(json.loads(line)["archiveID"])
                except (json.JSONDecodeError, KeyError):
                    pass
    return done


def load_catalog():
    if not CATALOG.exists():
        sys.exit("[faststart] no catalog.json (run catalog_release.py fetch first)")
    cat = json.load(open(CATALOG))
    items = cat["items"] if isinstance(cat, dict) else cat
    return cat, items


def flush_catalog(cat):
    tmp = CATALOG.with_suffix(".json.tmp")
    json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
    tmp.replace(CATALOG)


def repoint(it, item: str, name: str):
    """Re-point the catalog item at the hosted faststart remux and clear the flags —
    it now starts instantly everywhere. Additive + reversible."""
    it["downloadURL"] = f"{BASE_URL}/{item}/{name}"
    it["videoFile"] = {
        "name": name,
        "format": "h.264",
        "sizeBytes": it.get("videoFile", {}).get("sizeBytes") if isinstance(it.get("videoFile"), dict) else None,
        "tier": 1,
    }
    it["faststartRemuxed"] = True
    it.pop("needsFaststart", None)
    it.pop("applePlayable", None)
    # A prior strict pass may have advisory-flagged it; let the next strict run
    # re-confirm readyToPlay on the new URL rather than carrying a stale reason.
    if it.get("strictReason") == "apple_faststart_quirk":
        it.pop("strictReason", None)
        it.pop("strictCheckedAt", None)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--item", default=DEFAULT_ITEM, help="archive.org item to host remuxes on")
    ap.add_argument("--ids", default="", help="comma-separated archiveIDs (default: all needsFaststart)")
    ap.add_argument("--limit", type=int, default=0, help="cap items processed this run")
    ap.add_argument("--out", type=Path, default=OUT_DIR)
    ap.add_argument("--dry-run", action="store_true",
                    help="download + remux + validate only; NO upload, NO catalog write")
    ap.add_argument("--keep-local", action="store_true",
                    help="keep the remuxed .mp4 on disk (implied by --dry-run)")
    ap.add_argument("--publish", action="store_true",
                    help="catalog_release.py fetch before + remediate/publish after (CI)")
    args = ap.parse_args()

    if args.publish and not args.dry_run:
        subprocess.run([sys.executable, str(REPO / "tools" / "catalog_release.py"), "fetch"],
                       check=True)

    args.out.mkdir(parents=True, exist_ok=True)
    manifest = args.out / "manifest.jsonl"
    uploaded_log = args.out / "uploaded.jsonl"
    remux_dir = args.out / "remuxes"
    remux_dir.mkdir(exist_ok=True)

    cat, items = load_catalog()
    by_id = {it.get("archiveID"): it for it in items}

    if args.ids:
        want = [i.strip() for i in args.ids.split(",") if i.strip()]
        targets = [by_id[i] for i in want if i in by_id]
        missing = [i for i in want if i not in by_id]
        for m in missing:
            print(f"[faststart] --ids: {m} not in catalog", file=sys.stderr)
    else:
        targets = [it for it in items if it.get("needsFaststart")]

    # HARD GUARDS: never remux a truncated (needsReSource) item, and skip anything
    # already remuxed. Both are safety invariants, not just optimizations.
    kept = []
    for it in targets:
        if it.get("needsReSource"):
            print(f"[faststart] SKIP {it.get('archiveID')} — needsReSource (truncated, "
                  f"remux cannot fix)")
            continue
        if it.get("faststartRemuxed") and not args.ids:
            continue
        if not it.get("downloadURL"):
            continue
        kept.append(it)
    targets = kept

    already = load_done(uploaded_log)
    if not args.ids:
        targets = [it for it in targets if it.get("archiveID") not in already]
    if args.limit:
        targets = targets[:args.limit]

    auth = _auth()
    print(f"[faststart] item={args.item} | to process={len(targets)} | already uploaded={len(already)}"
          f"{' | DRY-RUN' if args.dry_run else ''}"
          f"{'' if (auth or args.dry_run) else ' | NO IAS3 CREDS (will stop before upload)'}")
    if not targets:
        return 0

    if not args.dry_run:
        if not auth:
            print("[faststart] IAS3_ACCESS_KEY / IAS3_SECRET_KEY not set — cannot upload. "
                  "Use --dry-run to build+validate locally, or set the keys.", file=sys.stderr)
            return 2
        ensure_item(args.item, auth)

    stats = {"ok": 0, "validated": 0, "download_fail": 0, "remux_fail": 0,
             "validate_fail": 0, "upload_fail": 0}
    with open(manifest, "a") as mlog:
        for i, it in enumerate(targets, 1):
            aid = it["archiveID"]
            url = it["downloadURL"]
            name = remote_name(aid)
            orig_path = remux_dir / f"{name}.orig"
            out_path = remux_dir / name
            print(f"[{i}/{len(targets)}] {aid}  <-  {url}", flush=True)

            def record(status, reason="", detail=""):
                mlog.write(json.dumps({"archiveID": aid, "status": status, "reason": reason,
                                       "detail": detail, "name": name, "at": time.time()}) + "\n")
                mlog.flush()

            if not download_original(url, orig_path):
                stats["download_fail"] += 1
                record("download_fail")
                continue
            osz = orig_path.stat().st_size
            if not ffmpeg_faststart(orig_path, out_path):
                stats["remux_fail"] += 1
                record("remux_fail")
                orig_path.unlink(missing_ok=True)
                continue
            ok, reason, detail = validate_remux(url, out_path)
            print(f"       validate: {'OK' if ok else 'FAIL'} [{reason}] {detail}")
            if not ok:
                stats["validate_fail"] += 1
                record("validate_fail", reason, detail)
                out_path.unlink(missing_ok=True)
                orig_path.unlink(missing_ok=True)
                continue
            stats["validated"] += 1
            print(f"       remux {osz/1e6:.1f}MB -> {out_path.stat().st_size/1e6:.1f}MB "
                  f"(lossless -c copy)")

            # Original no longer needed once the remux validated.
            orig_path.unlink(missing_ok=True)

            if args.dry_run:
                record("validated_dryrun", reason, detail)
                # keep out_path (dry-run implies --keep-local) for local proving.
                continue

            if not put_file(args.item, out_path, name, auth):
                stats["upload_fail"] += 1
                record("upload_fail")
                continue
            hosted = f"{BASE_URL}/{args.item}/{name}"
            repoint(it, args.item, name)
            flush_catalog(cat)
            with open(uploaded_log, "a") as ulog:
                ulog.write(json.dumps({"archiveID": aid, "url": hosted, "at": time.time()}) + "\n")
            record("uploaded", reason, hosted)
            stats["ok"] += 1
            print(f"       hosted + re-pointed -> {hosted}")
            if not args.keep_local:
                out_path.unlink(missing_ok=True)

    print(f"[faststart] done: {stats}")

    if args.publish and not args.dry_run and stats["ok"]:
        subprocess.run([sys.executable, str(REPO / "tools" / "remediate_catalog.py")], check=False)
        subprocess.run([sys.executable, str(REPO / "tools" / "catalog_release.py"), "publish"],
                       check=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
