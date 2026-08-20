#!/usr/bin/env python3
"""Refuse to publish a shared SQLite index that lost rows.

An index that several workflows append to is only as safe as its weakest
publish. On 2026-08-18 `subtitle-index.yml` uploaded the raw 1.17 GB
subtitle.sqlite alongside the .zz; `gh release upload --clobber` DELETES an
asset before replacing it, the raw upload 422'd, and both assets vanished. The
next run's restore said "no assets to download", its `|| echo "first run"`
translated that into a fresh start, and it rebuilt the index from zero and
republished — destroying 702,148 word timings and the whole `aligned` resume
history. `word-index.yml`, which has no such swallow, hit the identical
condition twice and failed safely both times.

Removing the swallow fixes that cause. This fixes every cause: snapshot the
row counts right after the restore, and refuse to upload if any table came out
smaller than it went in.

    python tools/sqlite_publish_guard.py snapshot subtitle.sqlite --out .baseline.json
    python tools/sqlite_publish_guard.py check    subtitle.sqlite --baseline .baseline.json

A missing baseline is a genuine first run and passes with a note; growth and
equality pass; any shrink is a hard failure naming the table and the numbers.
"""
from __future__ import annotations
import argparse, json, os, sqlite3, sys


def counts(path: str) -> dict[str, int]:
    if not os.path.exists(path):
        return {}
    con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        out = {}
        for (t,) in con.execute(
            "select name from sqlite_master where type='table' "
            "and name not like 'sqlite_%' order by name"
        ):
            try:
                out[t] = con.execute(f'select count(*) from "{t}"').fetchone()[0]
            except sqlite3.Error:
                pass          # an FTS shadow table we cannot count is not evidence
        return out
    finally:
        con.close()


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("snapshot"); s.add_argument("db"); s.add_argument("--out", required=True)
    c = sub.add_parser("check");    c.add_argument("db"); c.add_argument("--baseline", required=True)
    a = ap.parse_args()

    if a.cmd == "snapshot":
        rows = counts(a.db)
        with open(a.out, "w") as fh:
            json.dump(rows, fh)
        print(f"[guard] baseline: {rows or 'no index restored (first run)'}")
        return 0

    if not os.path.exists(a.baseline):
        print("[guard] no baseline recorded — treating as first run")
        return 0
    base = json.load(open(a.baseline))
    if not base:
        print("[guard] baseline is empty (genuine first run) — nothing to protect")
        return 0
    now = counts(a.db)
    if not now:
        print(f"[guard] REFUSING: {a.db} is missing or has no tables, "
              f"but the restored index had {base}", file=sys.stderr)
        return 1

    shrank = [(t, n, now.get(t, 0)) for t, n in base.items() if now.get(t, 0) < n]
    for t, before, after in shrank:
        print(f"[guard] REFUSING: table {t!r} shrank {before} -> {after}", file=sys.stderr)
    if shrank:
        print("[guard] the restored index is larger than what this run produced; "
              "publishing would destroy the difference. Not uploading.", file=sys.stderr)
        return 1

    grew = {t: (base.get(t, 0), n) for t, n in now.items() if n != base.get(t, 0)}
    print(f"[guard] OK — no table shrank. changed: {grew or 'none'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
