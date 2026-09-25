#!/usr/bin/env python3
"""Re-derive titles that sanitize_title reduced to a bare parenthetical.

Prelinger's amateur-film uploads name the film INSIDE square brackets and add
part markers after it: "[Amateur film: Medicus collection: New York World's
Fair, 1939-40] (Reel 2) (Part I)". The bracket-strip deleted the real title
and 42 visible cards were called "(Part I)", "(Part II)" (2026-09-25). The
cleaner is fixed; this puts the archive's title back through it for the items
already damaged. Idempotent: once repaired nothing matches, and the run is a
no-op. Reads/writes ./catalog.json (catalog_release.py fetch first).

    python3 tools/repair_bracket_titles.py [--dry-run]
"""
import json, re, sys, time, urllib.request
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R  # noqa: E402

CATALOG = Path(__file__).resolve().parent.parent / "catalog.json"
BARE = re.compile(r"^\s*\([^)]*\)\s*$")


def archive_title(aid):
    req = urllib.request.Request(f"https://archive.org/metadata/{aid}/metadata",
                                 headers={"User-Agent": "ArchiveWatch/1.0 (+https://archivewatch.org)"})
    t = json.load(urllib.request.urlopen(req, timeout=30)).get("result", {}).get("title")
    return t[0] if isinstance(t, list) else t


def main():
    dry = "--dry-run" in sys.argv
    cat = json.loads(CATALOG.read_text(encoding="utf-8"))
    hits = [it for it in cat["items"] if BARE.match(it.get("title") or "")]
    fixed = 0
    for it in hits:
        try:
            raw = archive_title(it["archiveID"])
        except Exception as e:  # noqa: BLE001 — a failed fetch leaves it for the next run
            print(f"  skip {it['archiveID']}: {e}")
            continue
        time.sleep(0.3)
        if not raw:
            continue
        probe = dict(it, title=raw)
        R.sanitize_title(probe)
        if probe["title"] and not BARE.match(probe["title"]):
            print(f"  {it['title']!r} -> {probe['title']!r}")
            it["title"] = probe["title"]
            fixed += 1
    if fixed and not dry:
        CATALOG.write_text(json.dumps(cat, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"[bracket-titles] {len(hits)} bare-parenthetical titles, {fixed} repaired"
          f"{' (dry run)' if dry else ''}")


if __name__ == "__main__":
    main()
