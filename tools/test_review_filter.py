#!/usr/bin/env python3
"""
test_review_filter.py — a quoted "review" must be about the FILM.

archive.org's review box is free text, so it also collects requests to the
uploader, rights enquiries and complaints about YouTube. A live dry run of the
social programme selected this as our pull-quote for The Barber of Seville:

    "Hi I would like to add these videos on my youtube channel. I am asking
     your permission on this. Thank you so much!"  — Marcos Castro776

and it would have been posted under the film as if it were praise.

The patterns are read out of the SHIPPED social_select.py so the test cannot
drift from what runs.
"""
import pathlib, re, sys

src = pathlib.Path(__file__).with_name("social_select.py").read_text()
ns: dict = {"re": re}
for name in ("NOT_A_REVIEW", "HAS_CONTACT"):
    m = re.search(rf"^{name} = re\.compile\(\s*(.*?)\)\s*$", src, re.S | re.M)
    if not m:
        print(f"FAIL: {name} not found in social_select.py"); sys.exit(1)
    exec(f"{name} = re.compile({m.group(1)})", ns)
NOT_A_REVIEW, HAS_CONTACT = ns["NOT_A_REVIEW"], ns["HAS_CONTACT"]
reject = lambda b: bool(NOT_A_REVIEW.search(b) or HAS_CONTACT.search(b))

# Verbatim from the live catalog — the ones that must be refused.
REJECT = [
    "Hi I would like to add these videos on my youtube channel. I am asking your permission on this.",
    "Abdul, could you post the movie Pepe (1960) for me? It's one of my grandmother's favorite movies",
    "I would like a license to use the first part of this movie on my youtube channel. please email to the",
    "I love this cartoon I can dawnlod my YouTube channel please help me",
    "wunhunglo and history teacher could you contact me ar10@xs4all.nl",
    "Hello! I'm currently working on an art film and would be interested in licensing footage from this",
    "Hi there, I'm wondering who I would need permission from to use small selection from this film",
    "Reach me at 555-867-5309 if you want the reel",          # phone, same privacy rule
]
# Real reviews — including argumentative and question-bearing ones, which an
# over-broad rule would eat.
KEEP = [
    "A tight little thriller that earns its ending. Karloff is doing more with his eyes than the script gives him.",
    "How can you consider it a comedy? I'd rather watch this than most of what passes for one now.",
    "Great. How would you classify this movie? Pacifist propaganda? Either way the photography is superb.",
    "This is all you want from a fantasy movie - the story comes from one of the greatest Russian writers.",
    "Como is very underrated and I have to say I didnt realize how good he was until I watched this.",
    "The print is rough in the second reel but the performances carry it. Worth ninety minutes of anyone's evening.",
]

fails = 0
for b in REJECT:
    ok = reject(b)
    if not ok: fails += 1
    print(f"  {'ok  ' if ok else 'FAIL'}  refuse: {b[:66]}")
for b in KEEP:
    ok = not reject(b)
    if not ok: fails += 1
    print(f"  {'ok  ' if ok else 'FAIL'}  keep  : {b[:66]}")
total = len(REJECT) + len(KEEP)
print(f"\n{total - fails}/{total} passed")
sys.exit(0 if fails == 0 else 1)
