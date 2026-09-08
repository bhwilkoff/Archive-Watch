#!/usr/bin/env python3
"""
test_instagram_media.py — the Meta surfaces post the teaser when there is one
and the card when there is not, and never post nothing.

The owner asked for "both video (reels) and images". Posting twice a day would
break the one-post-a-day rule the programme is built on (SOCIAL-PROGRAM §4), so
the format follows the media: the teaser is already 1080x1920 and ~18s, which
IS a Reel, and days without one carry the portrait card.

The adapter is imported from the SHIPPED tool so the test cannot drift.
"""
import importlib.util, pathlib, sys

spec = importlib.util.spec_from_file_location(
    "sp", pathlib.Path(__file__).with_name("social_post.py"))
sp = importlib.util.module_from_spec(spec); spec.loader.exec_module(sp)

FILM = {"title": "The Gorilla", "id": "x", "date": "2026-09-08"}
CARD = "https://example.invalid/card.jpg"
VID  = "https://example.invalid/teaser.mp4"

def run(env, card, video):
    for k in ("IG_USER_ID", "IG_ACCESS_TOKEN"):
        sp.os.environ.pop(k, None)
    sp.os.environ.update(env)
    return sp.post_instagram(FILM, "caption", card, False, video)

cases = [
    ("no credentials -> not connected",
     {}, CARD, VID, (None, "not connected")),
    ("teaser present -> REEL",
     {"IG_USER_ID": "1", "IG_ACCESS_TOKEN": "t"}, CARD, VID, ("DRY-RUN (reel)", None)),
    ("no teaser -> image card",
     {"IG_USER_ID": "1", "IG_ACCESS_TOKEN": "t"}, CARD, None, ("DRY-RUN (image)", None)),
    ("teaser but no card -> still a REEL",
     {"IG_USER_ID": "1", "IG_ACCESS_TOKEN": "t"}, None, VID, ("DRY-RUN (reel)", None)),
    ("neither -> says why, does not crash",
     {"IG_USER_ID": "1", "IG_ACCESS_TOKEN": "t"}, None, None,
     (None, "no public media URL (set SOCIAL_MEDIA_BASE_URL)")),
]

# Threads follows the SAME rule, so the two Meta surfaces cannot diverge by
# accident — a difference between them would be a bug, not a feature.
def run_threads(env, card, video):
    for k in ("THREADS_USER_ID", "THREADS_ACCESS_TOKEN"):
        sp.os.environ.pop(k, None)
    sp.os.environ.update(env)
    return sp.post_threads(FILM, "caption", card, False, video)

TH = {"THREADS_USER_ID": "1", "THREADS_ACCESS_TOKEN": "t"}
thread_cases = [
    ("threads: no credentials -> not connected", {}, CARD, VID, (None, "not connected")),
    ("threads: teaser -> video", TH, CARD, VID, ("DRY-RUN (video)", None)),
    ("threads: no teaser -> image", TH, CARD, None, ("DRY-RUN (image)", None)),
    ("threads: neither -> says why", TH, None, None,
     (None, "no public media URL (set SOCIAL_MEDIA_BASE_URL)")),
]

fails = 0
for name, env, card, video, want in cases:
    got = run(env, card, video)
    ok = got == want
    if not ok: fails += 1
    print(f"  {'ok  ' if ok else 'FAIL'}  {name}  -> {got}")

for name, env, card, video, want in thread_cases:
    got = run_threads(env, card, video)
    ok = got == want
    if not ok: fails += 1
    print(f"  {'ok  ' if ok else 'FAIL'}  {name}  -> {got}")

# The REELS container must not carry alt_text (an image-only field Meta
# rejects) and must ask to appear in the profile grid.
src = pathlib.Path(__file__).with_name("social_post.py").read_text()
reel = src[src.index('"media_type": "REELS"'):src.index('else:', src.index('"media_type": "REELS"'))]
for label, cond in [("REEL container omits alt_text", "alt_text" not in reel),
                    ("REEL shares to the feed grid", 'share_to_feed' in reel)]:
    if not cond: fails += 1
    print(f"  {'ok  ' if cond else 'FAIL'}  {label}")

total = len(cases) + len(thread_cases) + 2
print(f"\n{total - fails}/{total} passed")
sys.exit(0 if fails == 0 else 1)
