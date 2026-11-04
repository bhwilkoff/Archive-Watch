#!/usr/bin/env python3
"""The rule that reads a removal request (Decision 175), and the privacy of what
the public workflow writes. The two real notices of 2026-11-04 are cases here.
Run: python3 tools/test_takedown_check.py
"""
import datetime, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
import takedown_check as C
import takedown_cases as K

ok = True
def check(label, cond):
    global ok
    print(("PASS " if cond else "FAIL ") + label); ok &= bool(cond)

NOTICE = {"kind": "copyright", "complete": True}
DAY = datetime.date(2026, 11, 4)
def v(work, item, ev, **case):
    return C.verdict({**NOTICE, "work": work, **case}, item, ev, DAY)

arte = {"title": "Madame Dubarry", "year": 1924, "contentType": "silent-film"}
home = {"title": "Home Movie: 97390: Unidentified", "year": None, "contentType": "ephemeral"}
modern = {"title": "Some Film", "year": 2004, "contentType": "feature-film"}
clean = {"read": True, "logo": False, "hasAudio": False}

r = v("MADAME DU BARRY", arte, {"read": True, "logo": True, "hasAudio": True, "audioDb": -18.5})
check("the ARTE broadcast is removed", (r["action"], r["reason"]) == ("remove", "modern_layer"))
check("and both layers are named", r["layer"] == ["logo", "soundtrack"])
r = v("UNIDENTIFIED", home, clean)
check("the home movie is held for the owner", (r["action"], r["reason"]) == ("hold", "title_word_only"))
r = v("MADAME DU BARRY", arte, clean)
check("a clean copy of an old film is held", (r["action"], r["reason"]) == ("hold", "public_domain_by_age"))
r = v("Some Film (2004)", modern, clean)
check("a complete notice removes a modern title", r["action"] == "remove")
r = v("Some Film", modern, {"read": False})
check("an unread file never holds a removal back", r["action"] == "remove")
r = v("Madame du Barry", arte, {"read": False})
check("nor does age, when nothing was read", r["action"] == "remove")
r = v("Passion", arte, {"read": True, "logo": True, "hasAudio": False})
check("a translated title with a logo is removed", r["action"] == "remove")
check("a silent film with a mute track has no soundtrack",
      C.modern_layer(arte, {"hasAudio": True, "audioDb": -91}) == [])
check("sound on a sound film is not a modern layer",
      C.modern_layer(modern, {"hasAudio": True, "audioDb": -20}) == [])
check("what we do not serve closes", v("X", None, {})["action"] == "none")
check("a privacy request is the owner's", v("", modern, clean, kind="other")["reason"] == "not_copyright")
check("an incomplete notice is the owner's", v("X", modern, clean, complete=False)["reason"] == "incomplete_notice")
check("1930 is public domain in 2026", C.public_domain_by_age(1930, DAY))
check("1931 is not", not C.public_domain_by_age(1931, DAY))

check("names: spacing does not divide a title", C.name_fit("MADAME DU BARRY", "Madame Dubarry") == "same")
check("names: one word of a long title is partial", C.name_fit("UNIDENTIFIED", home["title"]) == "partial")
check("names: a year in the claim is no difference", C.name_fit("Some Film (2004)", "Some Film") == "same")
check("names: nothing in common proves nothing", C.name_fit("Passion", "Madame Dubarry") == "none")

t = C.targets("https://archivewatch.org/item/X1/\nhttps://archivewatch.org/#/series/a-show "
              "https://archive.org/details/Y2@e01 https://archive.org/download/Z3/f.mp4 "
              "https://archivewatch.org/item/X1/ nonsense")
check("every kind of link resolves", [x.get("id") for x in t][:4] == ["X1", "series:a-show", "Y2@e01", "Z3"])
check("a repeated link counts once, and a bad one is kept", len(t) == 5 and "unread" in t[4])

rng = np.random.default_rng(4)
def film(n=24, h=240, w=320):
    out = []
    for _ in range(n):
        f = np.kron(rng.uniform(40, 200, (h // 8, w // 8)), np.ones((8, 8)))
        out.append(f.astype("float32"))
    return out
def translucent(frames):
    for f in frames:
        f[20:36, 250:296] = f[20:36, 250:296] * .6 + 100
    return frames
def border(frames):
    for f in frames:
        f[:14, :] = 0; f[-14:, :] = 0; f[:, :20] = 0; f[:, -20:] = 0
    return frames
s = C.logo_score(translucent(film()))
check("a translucent logo over moving pictures is found", C.has_logo(s))
check("in its own corner", max(s, key=s.get) == "topRight")
check("CONTROL: moving pictures alone have none", not C.has_logo(C.logo_score(film())))
check("CONTROL: a border in every corner is not a logo", not C.has_logo(C.logo_score(border(film()))))
check("too few frames is not a clean file", C.logo_score(film(5)) is None)
check("black frames do not count as frames",
      C.logo_score([np.zeros((240, 320), "float32")] * 24) is None)

PLANT = "Jane Requester jane@example.com 555-0100 12 Private Lane"
result = [{"id": "X1", "action": "hold", "reason": "title_word_only",
           "work": PLANT, "name": PLANT, "email": PLANT, "links": PLANT, "note": PLANT,
           "evidence": {"read": True, "minutes": 9, "logo": False, "hasAudio": False}},
          {"id": None, "action": "hold", "reason": "unread_link"}]
body = K.issue_body({"ref": "TD-TEST0001", "verdict": result})
check("the issue asks for a decision", "Reply `remove` or `keep`" in body)
check("every reason has a sentence", set(K.REASONS) >= {"title_word_only", "public_domain_by_age",
      "not_copyright", "incomplete_notice", "unread_link", "run_limit"})
check("the planted requester does not reach the public issue", PLANT.split()[0] not in body)
sys.exit(0 if ok else 1)
