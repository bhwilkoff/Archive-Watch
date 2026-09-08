#!/usr/bin/env python3
"""
test_clip_line.py — the line-led teaser, asserted against the SHIPPED module.

Every case here is a shape the render depends on and that a screenshot could
not tell you about: whether the filtergraph's labels chain, whether the quote
layer disappears when there is no quote, whether a body that is not WebVTT is
refused. Checked to FAIL against the shot-only build.

Run: python3 tools/test_clip_line.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import social_clip as C

ok = fail = 0


def check(name, cond, detail=""):
    global ok, fail
    if cond:
        ok += 1
        print(f"  PASS  {name}")
    else:
        fail += 1
        print(f"  FAIL  {name}  {detail}")


print("wrap_quote")
w = C.wrap_quote("We've known Debbie, what, since the eighth grade?")
check("wraps a real line", w is not None and 1 <= len(w) <= 3, repr(w))
check("no line exceeds the column", w and max(len(x) for x in w) <= C.QUOTE_COLS, repr(w))
check("wrapping loses no words",
      w and " ".join(w).split() == "We've known Debbie, what, since the eighth grade?".split())
check("a paragraph is refused", C.wrap_quote(" ".join(["word"] * 40)) is None)
check("an empty line is refused", C.wrap_quote("   ") is None)
check("a single word never breaks mid-word",
      (C.wrap_quote("Antidisestablishmentarianism") or [""])[0]
      == "Antidisestablishmentarianism")

print("\nbuild_filter — the quote layer")
qf = "/tmp/q.txt"
f_q = C.build_filter("A Film", 1947, True, None, qf, 2.2)
f_n = C.build_filter("A Film", 1947, True, None, None, 0.0)
check("quote uses the italic face", "Fraunces-Text-Italic.ttf" in f_q)
check("quote is read from a file, never inlined", f"textfile='{qf}'" in f_q)
check("quote fades in on the spoken beat", "alpha='if(lt(t,1.90)" in f_q, f_q[-260:])
check("labels chain v -> lt -> out",
      f_q.count("[lt]") == 2 and f_q.count("[out]") == 1 and f_q.count("[v]") == 2)
check("without a quote there is no quote layer",
      "Fraunces-Text-Italic" not in f_n and "[lt]" not in f_n)
check("without a quote the graph still ends at [out]", f_n.rstrip().endswith("[out]"))
check("the lower third survives both ways",
      "Fraunces-Display-Black" in f_q and "Fraunces-Display-Black" in f_n)
# Reels/Shorts/TikTok draw the account name, caption and action rail across
# the BOTTOM of the video. The owner watched a Reel with the platform's own
# chrome printed straight through our title, so everything we burn must live
# in the upper band. These numbers are the whole fix; assert them.
import re
ys = [int(m) for m in re.findall(r"y=(\d+)", f_q)] + [C.QUOTE_Y + C.QUOTE_H]
check("nothing is burned into the platform's bottom chrome",
      ys and max(ys) <= C.H - C.BOTTOM_SAFE, str(sorted(ys)))
check("nothing is burned into the platform's top chrome",
      ys and min(ys) >= C.TOP_SAFE, str(sorted(ys)))
check("the quote is centred in its own band", f"y={C.QUOTE_Y}+({C.QUOTE_H}" in f_q)
check("the band leaves room to read three lines", C.QUOTE_H >= 3 * 68 + 44)

# The owner's rule: "we shouldn't overlay the captions text on the square
# video, but rather we should put it above or below to not block the content."
# So the three bands must not touch, and the film must be fitted INSIDE its
# box rather than to the frame width.
print("\nthe frame is banded, not layered")
check("title, film and quote are three disjoint bands",
      C.CARD_Y + C.CARD_H <= C.FILM_Y
      and C.FILM_Y + C.FILM_H <= C.QUOTE_Y
      and C.QUOTE_Y + C.QUOTE_H <= C.H - C.BOTTOM_SAFE)
check("the title band clears the platform header", C.CARD_Y >= C.TOP_SAFE)
check("the film is fitted inside a BOX, not to the frame width",
      f"scale={C.W}:{C.FILM_H}:force_original_aspect_ratio=decrease" in f_q)
check("the film is placed in its band, not centred in the frame",
      f"overlay=(W-w)/2:{C.FILM_Y}+" in f_q)
check("with no quote the picture takes the room back",
      f"scale={C.W}:{C.FILM_H_TALL}:force_original_aspect_ratio=decrease" in f_n
      and C.FILM_H_TALL > C.FILM_H)
check("even the tall picture stays inside the safe area",
      C.FILM_Y_TALL + C.FILM_H_TALL <= C.H - C.BOTTOM_SAFE)
check("nothing is ever cropped to fit a band",
      "force_original_aspect_ratio=decrease" in f_q and "crop=1080:1920" in f_q)
check("no drawtext escaping is attempted on the quote",
      "text='" not in f_q.split("[lt]")[-1])

print("\nfetch_vtt")
tmp = Path("/tmp/aw_test.vtt")
tmp.write_text("WEBVTT\n\n00:01.000 --> 00:03.000\nHello.\n", encoding="utf-8")
check("a local file is read verbatim",
      (C.fetch_vtt("x", str(tmp)) or "").startswith("WEBVTT"))
bad = Path("/tmp/aw_test_404.html")
bad.write_text("<!doctype html><title>404</title>", encoding="utf-8")
check("a local non-WebVTT file still reads (explicit override)",
      C.fetch_vtt("x", str(bad)) is not None)

print("\nline_segment padding")
seg = {"start": 100.0, "end": 103.0, "text": "Come."}
lead_start = max(0.0, seg["start"] - C.LEAD)
check("the cut starts a beat BEFORE the line", lead_start < seg["start"])
check("the cut runs past the line", (seg["end"] - lead_start) + C.TAIL > seg["end"] - lead_start)
check("a teaser stays inside the platform ceilings", C.LINE_MAX <= 60.0)

import inspect

print("\nthe line must be HEARD before it is burned")
check("the clip asks the audio, not just the subtitle file",
      "from social_hear import hear" in Path(C.__file__).read_text())
check("a line the film does not say is skipped",
      "the film does not say this here" in inspect.getsource(C.main))
check("a line that could NOT be checked is not burned either",
      "could not be checked against the" in inspect.getsource(C.main))
check("more than one candidate is tried", C.HEAR_TRIES >= 2)
check("the threshold sits in the measured gap (0.0 wrong vs 0.625+ right)",
      0.3 <= C.HEARD_MIN <= 0.6)

print("\naudio")
src = inspect.getsource(C.main)
check("every teaser keeps its sound, not only the line-led ones",
      '"-an"' not in src and '"-map", "0:a?"' in src)
check("the sound is normalised", "loudnorm=I=-16" in src)
check("and faded at both ends", "afade=t=in" in src and "afade=t=out" in src)

check("a render that lost the source's audio is refused, not published",
      'src_audio and not out_audio' in src and 'return 5' in src)
check("the sidecar reports what the render actually has, not what we hoped",
      '"audio": out_audio' in src)

print("\ncaption adopts the teaser's line")
import json
import social_post as P

vid = Path("/tmp/aw_clip_test.mp4"); vid.write_bytes(b"x")
side = vid.with_suffix(".json")


def spec_with(line_text):
    return {"fragments": [{"kind": "meta", "text": "1947", "source": "catalog"},
                          {"kind": "line", "text": line_text, "source": "subtitles"}]}


side.write_text(json.dumps({"quote": "Come with me."}), encoding="utf-8")
sp = spec_with('"Some other line."')
got = P.adopt_clip_quote(sp, vid)
check("the burned line replaces the caption's own", got == "Come with me.")
check("the caption now quotes it",
      [f for f in sp["fragments"] if f["kind"] == "line"][0]["text"] == '"Come with me."')
check("the other fragments survive", len(sp["fragments"]) == 2)
check("the source says where the line came from",
      "teaser" in [f for f in sp["fragments"] if f["kind"] == "line"][0]["source"])

sp2 = {"fragments": [{"kind": "meta", "text": "1947", "source": "catalog"}]}
P.adopt_clip_quote(sp2, vid)
check("a spec with no line fragment gains one", len(sp2["fragments"]) == 2)

side.write_text(json.dumps({"quote": None}), encoding="utf-8")
sp3 = spec_with('"Kept."')
check("a shot-led teaser leaves the caption alone",
      P.adopt_clip_quote(sp3, vid) is None
      and [f for f in sp3["fragments"] if f["kind"] == "line"][0]["text"] == '"Kept."')
side.unlink()
sp4 = spec_with('"Kept."')
check("no sidecar leaves the caption alone", P.adopt_clip_quote(sp4, vid) is None)
check("no video at all leaves the caption alone",
      P.adopt_clip_quote(spec_with('"Kept."'), None) is None)
vid.unlink()

print(f"\n{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
