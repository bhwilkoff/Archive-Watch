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
for name in ("NOT_A_REVIEW", "HAS_CONTACT", "SIGN_OFF"):
    m = re.search(rf"^{name} = re\.compile\(\s*(.*?)\)\s*$", src, re.S | re.M)
    if not m:
        print(f"FAIL: {name} not found in social_select.py"); sys.exit(1)
    exec(f"{name} = re.compile({m.group(1)})", ns)
NOT_A_REVIEW, HAS_CONTACT = ns["NOT_A_REVIEW"], ns["HAS_CONTACT"]
SIGN_OFF = ns["SIGN_OFF"]
reject = lambda b: bool(NOT_A_REVIEW.search(b) or HAS_CONTACT.search(b)
                        or SIGN_OFF.search(b))

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
    # "best" INSIDE a sentence is not a sign-off; only a trailing one is.
    "This is the best print of the film I have seen anywhere, and the score suits it.",
    "Thanks to the uploader I finally saw this — the chase in reel three is astonishing.",
]

# Found live once the composer started preferring short bodies: a request for
# a copy reads as a review to a length test, and a letter sign-off quotes as a
# dangling fragment.
REJECT += [
    "Hey, I am searching desperately for a copy of the film. Do you know where to find one? Best,",
    "Where can I find a better print of this? The one here is very soft.",
    "Does anyone know where a restored version might be hiding these days?",
    "I loved this film and would watch it again any day. Thanks,",
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
