#!/usr/bin/env python3
"""Turn any catalog-mutating tool into a lock-free one, without changing it.

THE PROBLEM, measured. Twenty-seven workflows hold the single `catalog-writers`
lock for their ENTIRE run — fetch, compute for up to four hours, publish — and
their average demand adds up to **24.2 hours per cycle** against a lock that has
24 hours a day to give. It is oversubscribed, which is why runs are destroyed in
the queue routinely rather than occasionally (Decision 057), why budgets have to
be measured in hours, and why a kill discards a whole run's work.

The compute needs no lock. Only the mutation does, and the mutation takes about
two minutes.

Converting each tool to emit deltas by hand is ~27 bespoke changes. This does it
generically instead, by observing what a tool DID rather than asking it to
report:

    snapshot   before the tool runs      — record every item's field values
    extract    after the tool runs       — diff, emit only what changed
    apply      in a short, locked job    — merge onto a FRESHLY fetched catalog

The merge is what makes it safe. Republishing a whole catalog read hours earlier
silently reverts anything another writer published meanwhile — which the lock
was compensating for. A field-level merge does not: two workflows touching
different fields of the same item both survive.

Usage in a workflow:

    # compute job — NO catalog-writers lock
    python tools/catalog_release.py fetch
    python tools/catalog_delta.py snapshot --out /tmp/before.json
    python tools/<any existing tool>.py ...        # unchanged
    python tools/catalog_delta.py extract --snapshot /tmp/before.json --out deltas.json
    # upload deltas.json as an artifact

    # apply job — holds catalog-writers, runs in ~2 minutes
    python tools/catalog_release.py fetch
    python tools/catalog_delta.py apply --deltas deltas.json
    python tools/catalog_release.py publish
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"

# Fields that are pure bookkeeping: a tool rewriting them is not a change worth
# carrying, and shipping them would make every delta enormous.
IGNORED = {"_fileRuntime"}


def load(path: Path):
    data = json.loads(path.read_text(encoding="utf-8"))
    items = data["items"] if isinstance(data, dict) else data
    return data, items


def key(item: dict) -> str | None:
    return item.get("archiveID")


def cmd_snapshot(args) -> int:
    _, items = load(CATALOG)
    # Only the values, keyed by id. This is what the diff compares against, and
    # it is far smaller than a second copy of the catalog.
    snap = {}
    for it in items:
        k = key(it)
        if k:
            snap[k] = {f: v for f, v in it.items() if f not in IGNORED}
    Path(args.out).write_text(json.dumps(snap, separators=(",", ":")))
    print(f"[delta] snapshot of {len(snap)} items -> {args.out}")
    return 0


def cmd_extract(args) -> int:
    before = json.loads(Path(args.snapshot).read_text(encoding="utf-8"))
    _, items = load(CATALOG)

    changes: dict[str, dict] = {}
    removals: dict[str, list[str]] = {}
    added = 0
    for it in items:
        k = key(it)
        if not k:
            continue
        old = before.get(k)
        if old is None:
            # A tool that INGESTS new items is not a field-level change; carry
            # the whole item.
            changes[k] = {f: v for f, v in it.items() if f not in IGNORED}
            added += 1
            continue
        diff = {f: v for f, v in it.items()
                if f not in IGNORED and old.get(f) != v}
        gone = [f for f in old if f not in it and f not in IGNORED]
        if diff:
            changes[k] = diff
        if gone:
            removals[k] = gone

    payload = {"changes": changes, "removals": removals}
    Path(args.out).write_text(json.dumps(payload, separators=(",", ":")))
    fields = sum(len(v) for v in changes.values())
    print(f"[delta] {len(changes)} items changed ({fields} fields, {added} new), "
          f"{len(removals)} with removed fields -> {args.out} "
          f"({Path(args.out).stat().st_size/1e6:.1f} MB)")
    return 0


def cmd_apply(args) -> int:
    path = Path(args.deltas)
    if not path.exists() or path.stat().st_size == 0:
        print("[delta] no deltas to apply")
        return 0
    payload = json.loads(path.read_text(encoding="utf-8"))
    changes = payload.get("changes", {})
    removals = payload.get("removals", {})
    if not changes and not removals:
        print("[delta] deltas file is empty; nothing to apply")
        return 0

    data, items = load(CATALOG)
    by_id = {key(it): it for it in items if key(it)}

    applied = new_items = missing = removed = 0
    for k, fields in changes.items():
        it = by_id.get(k)
        if it is None:
            # The tool ingested this item; add it whole.
            if fields.get("archiveID"):
                items.append(dict(fields))
                new_items += 1
            else:
                missing += 1
            continue
        it.update(fields)
        applied += 1
    for k, fields in removals.items():
        it = by_id.get(k)
        if it is None:
            continue
        for f in fields:
            it.pop(f, None)
            removed += 1

    tmp = CATALOG.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")),
                   encoding="utf-8")
    tmp.replace(CATALOG)
    print(f"[delta] applied {applied} items, added {new_items}, removed {removed} fields"
          + (f", {missing} ids no longer in the catalog" if missing else ""))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("snapshot"); s.add_argument("--out", required=True)
    s.set_defaults(func=cmd_snapshot)
    e = sub.add_parser("extract")
    e.add_argument("--snapshot", required=True); e.add_argument("--out", required=True)
    e.set_defaults(func=cmd_extract)
    a = sub.add_parser("apply"); a.add_argument("--deltas", required=True)
    a.set_defaults(func=cmd_apply)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
