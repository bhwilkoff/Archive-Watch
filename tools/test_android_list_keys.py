#!/usr/bin/env python3
"""A Compose lazy list throws on a repeated key, and a user sees a crash with no
frame of ours in it (Play, versions 66-69). Lists fed by catalog data, where one id
can appear twice, must pass through uniqueBy. Run: python3 tools/test_android_list_keys.py"""
import re, sys
from pathlib import Path
root = Path(__file__).resolve().parent.parent / "android/app/src/main/java"
RISKY = [r"items\(season\?\.episodes\.orEmpty\(\), key", r"items\(scenes, key",
         r"items\(v\.size, key = \{ v\[it\]\.choiceKey", r"itemsIndexed\(rows, key = \{ _, it -> it\.archiveID \}\) \{ index, item ->\n\s+if \(onNearEnd",
         r"items\(episodeItems, span"]
bad = [f"{p.name}: {r}" for p in root.rglob("*.kt") for r in RISKY if re.search(r, p.read_text(encoding="utf-8"))]
print("\n".join("FAIL " + b for b in bad) or "PASS every catalog-fed lazy list is unique before it is keyed")
sys.exit(1 if bad else 0)
