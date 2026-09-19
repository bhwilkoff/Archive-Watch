#!/usr/bin/env python3
"""
upload_covers.py — publish frame-extracted covers to an archive.org item (#86).

Uploads the JPEGs produced by batch_covers.py into a single archive.org item via
the IAS3 (S3-like) API, so each cover gets a stable public URL:
    https://archive.org/download/<item>/<slug>.jpg
The tvOS app fetches that as posterURL (URLSession — no CORS concern).

Credentials come from the environment ONLY (never committed):
    IAS3_ACCESS_KEY, IAS3_SECRET_KEY
In CI add them as GitHub Actions secrets of the same name.

Resumable: tracks uploaded slugs in <out>/uploaded.jsonl; re-running skips them.

Usage:
    export IAS3_ACCESS_KEY=...  IAS3_SECRET_KEY=...
    python tools/upload_covers.py --item archivewatch-covers
    python tools/upload_covers.py --item archivewatch-covers --limit 50   # smoke
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

DEFAULT_OUT = Path(__file__).resolve().parent / "covers_out"
S3 = "https://s3.us.archive.org"


def _auth() -> str:
    ak = os.environ.get("IAS3_ACCESS_KEY")
    sk = os.environ.get("IAS3_SECRET_KEY")
    if not ak or not sk:
        sys.exit("[upload] set IAS3_ACCESS_KEY and IAS3_SECRET_KEY in the environment")
    return f"LOW {ak}:{sk}"


def ensure_item(item: str, auth: str, retries: int = 4) -> None:
    """Create the bucket with item-level metadata (idempotent).

    THIS IS PREFLIGHT, AND PREFLIGHT MAY NOT END THE RUN. On 2026-09-19 a
    single read timeout here raised out of main() and exit(1) threw away 44
    covers that 45 minutes of macOS runner time had already produced — none
    of them uploaded, none wired, the runner disposed with the JPEGs on it.
    The item has existed since #86; this call is a formality, so a network
    failure to confirm it is not a reason to discard finished work. Only
    auth actually being rejected stops the run, because every subsequent
    PUT would fail the same way.

    Retries transient errors the way put_file does — same host, same fault.
    """
    for attempt in range(1, retries + 1):
        req = urllib.request.Request(f"{S3}/{item}", method="PUT", data=b"")
        req.add_header("authorization", auth)
        req.add_header("x-amz-auto-make-bucket", "1")
        req.add_header("x-archive-meta-mediatype", "image")
        req.add_header("x-archive-meta-collection", "opensource_media")
        req.add_header("x-archive-meta-title", "Archive Watch - generated cover art")
        req.add_header("x-archive-meta-creator", "Archive Watch")
        req.add_header("x-archive-meta-licenseurl", "https://creativecommons.org/publicdomain/zero/1.0/")
        req.add_header("x-archive-meta-description",
                       "Cover thumbnails extracted from public-domain / CC0 moving images "
                       "for the Archive Watch tvOS app. Each image is a single still from "
                       "the source film, selected by automated frame scoring.")
        req.add_header("x-archive-queue-derive", "0")
        try:
            urllib.request.urlopen(req, timeout=60)
            print(f"[upload] ensured item '{item}'")
            return
        except urllib.error.HTTPError as e:
            # 409 / already-exists-style responses are fine.
            if e.code in (409,):
                print(f"[upload] item '{item}' already exists")
                return
            body = e.read().decode("utf-8", "replace")[:300]
            print(f"[upload] ensure_item HTTP {e.code}: {body}", file=sys.stderr)
            if e.code in (401, 403):
                sys.exit("[upload] auth rejected — check IAS3 keys")
            return
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            if attempt < retries:
                time.sleep(min(2 ** attempt, 30))
                continue
            print(f"[upload] ensure_item could not reach {S3} ({e}) — "
                  f"uploading anyway; the item already exists", file=sys.stderr)


def put_file(item: str, local: Path, remote: str, auth: str, retries: int = 4) -> bool:
    data = local.read_bytes()
    for attempt in range(1, retries + 1):
        req = urllib.request.Request(f"{S3}/{item}/{remote}", method="PUT", data=data)
        req.add_header("authorization", auth)
        req.add_header("content-type", "image/jpeg")
        req.add_header("x-archive-queue-derive", "0")
        req.add_header("x-archive-keep-old-version", "0")
        try:
            urllib.request.urlopen(req, timeout=120)
            return True
        except urllib.error.HTTPError as e:
            if e.code == 503 and attempt < retries:  # slow down / reduce request rate
                time.sleep(min(2 ** attempt, 30))
                continue
            print(f"[upload] {remote} HTTP {e.code}: {e.read().decode('utf-8','replace')[:160]}",
                  file=sys.stderr)
            return False
        except (urllib.error.URLError, TimeoutError) as e:
            if attempt < retries:
                time.sleep(min(2 ** attempt, 30))
                continue
            print(f"[upload] {remote} error: {e}", file=sys.stderr)
            return False
    return False


def load_uploaded(path: Path) -> set[str]:
    done: set[str] = set()
    if path.exists():
        for line in open(path):
            line = line.strip()
            if line:
                try:
                    done.add(json.loads(line)["file"])
                except (json.JSONDecodeError, KeyError):
                    pass
    return done


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--item", default="archivewatch-covers")
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    auth = _auth()
    posters = args.out / "posters"
    manifest = args.out / "manifest.jsonl"
    uploaded_log = args.out / "uploaded.jsonl"
    if not manifest.exists():
        sys.exit(f"[upload] no manifest at {manifest} — run batch_covers.py first")

    # The set of covers worth uploading = manifest status ok with a real file.
    wanted = []
    seen = set()
    for line in open(manifest):
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)  # tolerate a partial last line during a live batch
        except json.JSONDecodeError:
            continue
        if rec.get("status") != "ok":
            continue
        f = rec["file"]
        if f in seen:
            continue
        seen.add(f)
        if (posters / f).exists():
            wanted.append(rec)

    already = load_uploaded(uploaded_log)
    todo = [r for r in wanted if r["file"] not in already]
    if args.limit:
        todo = todo[:args.limit]
    print(f"[upload] item={args.item} | covers={len(wanted)} | already uploaded={len(already)} "
          f"| this run={len(todo)}")
    if not todo:
        return 0

    ensure_item(args.item, auth)
    started = time.time()
    ok = 0
    with open(uploaded_log, "a") as ulog:
        for i, rec in enumerate(todo, 1):
            f = rec["file"]
            if put_file(args.item, posters / f, f, auth):
                ulog.write(json.dumps({"file": f, "archiveID": rec["archiveID"],
                                       "url": f"https://archive.org/download/{args.item}/{f}",
                                       "at": time.time()}) + "\n")
                ulog.flush()
                ok += 1
            rate = i / max(time.time() - started, 1e-6)
            if i % 25 == 0 or i == len(todo):
                print(f"[{i:>5}/{len(todo)}] uploaded {ok} | {rate*60:.0f}/min "
                      f"eta {(len(todo)-i)/max(rate,1e-6)/60:.0f}m")
    print(f"[upload] done: {ok}/{len(todo)} uploaded to item '{args.item}'")
    print(f"[upload] base URL: https://archive.org/download/{args.item}/<slug>.jpg")
    # A run with covers in hand that uploaded NONE has produced nothing, and
    # that goes red (Decision 093). Returning 0 here made a total archive.org
    # refusal look like a clean run: the wire step says "nothing to wire", the
    # delta is empty, and the whole workflow goes green having shipped nothing.
    if ok == 0:
        print(f"[upload] FAILED: {len(todo)} covers were ready and none uploaded",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
