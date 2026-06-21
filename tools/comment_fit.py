#!/usr/bin/env python3
"""
comment_fit.py — score an archive.org review/comment for fit as a GENUINE review of
the TITLE (the film), for display on the app's Detail page.

archive.org "reviews" are really a comment box, so they mix three things:
  1. genuine reviews of the film  ("Vincent Price gives a once-in-a-lifetime
     performance")                                                   -> KEEP
  2. talk about the FILE / upload / transfer ("what format is the audio?", "the
     m2ts file is flawed, request a re-rip", "I downloaded the DVD-5 version, the
     picture is cleaner than the other download")                    -> DROP
  3. inappropriate / spam (slurs, "click here", URLs)                -> DROP

We filter in the PIPELINE (one deterministic, reviewable scorer) and bake only the
fit reviews into the catalog, so every client just displays a clean set — no
per-platform filtering, no runtime LLM. The score is keyword/heuristic based:
film-content signals raise it, file/upload/quality signals lower it (the owner's
explicit rule: NOT about the quality of the video files), and inappropriate/spam
hard-reject.

score_review(review) -> (fit: float, verdict: str). keep_review(review) -> bool.
A review is KEPT when it has real film content and is not file-dominated, spam, or
inappropriate.
"""

from __future__ import annotations

import re

# --- hard rejects -----------------------------------------------------------
# Offensive: tight list of slurs / hate / harassment — NOT mild profanity (a
# genuine review may say "scary as hell" / "damn good"). Kept minimal + severe.
_INAPPROPRIATE = re.compile(
    r"\b(n[i1]gg|f[a4]gg|ret[a4]rd|k[i1]ke|sp[i1]c\b|ch[i1]nk|tr[a4]nny|"
    r"c[u\*]nt|raped?\b|molest|pedo|kill yourself|kys\b)", re.I)
# Spam: links + promo CTAs.
_SPAM = re.compile(
    r"(https?://|www\.|\.com\b|\.net\b|\.ru\b|click here|buy now|"
    r"subscribe|promo code|for more cool finds|check out my|visit my)", re.I)
# Mild self-promo (penalise, don't reject).
_SELF_PROMO = re.compile(r"(click on my name|see my other|my channel|my profile)", re.I)

# --- file / upload / transfer-quality signals (the "about the FILE" rule) ----
# Phrases are preferred over bare words so "quality of the ACTING" isn't punished
# while "video quality" is. (pattern, weight)
_FILE_SIGNALS = [
    (r"\bm2ts\b", 4), (r"\bre-?rip\b", 4), (r"\bre-?upload", 4), (r"\bre-?encode", 4),
    (r"\brip\b", 2), (r"\bripped\b", 2), (r"\bftp\b", 3), (r"\bcodec", 3),
    (r"\bbitrate", 3), (r"\bframe ?rate", 3), (r"aspect ratio", 3), (r"\bgb file", 3),
    (r"\bcorrupt", 3), (r"won'?t play", 3), (r"out of sync", 3), (r"\bin sync\b", 3),
    (r"no (sound|audio)\b", 3), (r"\bre-?master", 2), (r"\bencod(e|ing)", 2),
    (r"\bformat\b", 2), (r"\bmpe?g\b", 2), (r"\bh\.?264\b", 3), (r"\bx264\b", 3),
    (r"\b(xvid|divx)\b", 3), (r"\bresolution\b", 2), (r"\b(1080|720|480)p?\b", 2),
    (r"\bdvd-?5\b", 3), (r"\bblu-?ray\b", 2), (r"\bvhs\b", 2),
    (r"(video|picture|image|audio|sound|download|playback) quality", 3),
    (r"the (download|upload|file|print|transfer|rip|scan|copy|version|encode)", 3),
    (r"this (download|upload|file|print|transfer|rip|scan|copy|version|encode)", 3),
    (r"best (copy|version|print|transfer|quality) i", 3), (r"\bupload(ed|ing)?\b", 2),
    (r"\bdownload(ed|ing)?\b", 2), (r"\bbuffer", 3), (r"\bpixelat", 3),
    (r"\bglitch", 2), (r"\bartifact", 2), (r"\bsubtitle", 2), (r"\bcaption", 2),
    (r"\bstreaming?\b", 2), (r"\bplay(s|ed)? (fine|fine on|on my|back)", 3),
    (r"\b\d{1,2}:\d{2}\b", 2),                 # a timecode = a file-defect report
    (r"thanks for (the|posting|uploading|sharing)", 2), (r"please (re-?up|fix|repost)", 4),
    # containers / download-help / "how do I get this file" comments
    (r"\btorrent", 4), (r"\biso\b", 3), (r"\b(ogv|ogg|flv|mkv|m4v|wmv)\b", 3),
    (r"\.(mp4|avi|mkv|mov|iso|ogv|m4v|wmv)\b", 3), (r"\bavi\b", 2),
    (r"save (it|this|the (movie|film|video)) to", 4), (r"to my (computer|pc|phone|device)", 3),
    (r"how (do i|to|can i) (save|download|burn|play|watch|get|open)", 4),
    (r"can'?t (download|save|play|open|get)", 4), (r"burn (it|the|to|image)", 3),
    (r"\bdis[ck]\b", 2), (r"\bhow do i\b", 2), (r"to download", 2), (r"to watch this on", 3),
]

# --- film-content signals (about the movie itself) --------------------------
_FILM_SIGNALS = [
    "acting", "actor", "actress", "performance", "perform", "story", "storyline",
    "plot", "character", "directed", "director", "direction", "cinematograph",
    "script", "screenplay", "cast", "scene", "ending", "dialogue", "dialog",
    "masterpiece", "classic", "atmospher", "suspense", "scary", "creepy", "eerie",
    "funny", "hilarious", "boring", "entertaining", "compelling", "noir", "horror",
    "comedy", "drama", "thriller", "sci-fi", "b-movie", "cult", "plays ", "portray",
    "villain", "role", "soundtrack", "score ", "special effect", "effects", "twist",
    "remake", "the film", "this film", "the movie", "this movie", "the story",
    "watched", "enjoyed", "loved this", "love this", "recommend", "underrated",
    "overrated", "well made", "well-made", "well written", "well-written", "pace",
    "ahead of its time", "stars as", "great movie", "good movie", "bad movie",
    "best movie", "worst movie", "must see", "must-see", "must watch",
]


def _film_score(text: str) -> int:
    return sum(1 for kw in _FILM_SIGNALS if kw in text)


def _file_score(text: str) -> float:
    return sum(w for pat, w in _FILE_SIGNALS if re.search(pat, text))


def score_review(review: dict) -> tuple[float, str]:
    """(fit, verdict). Higher fit = more clearly a genuine review of the title."""
    title = (review.get("reviewtitle") or "")
    body = (review.get("reviewbody") or "")
    text = (title + " . " + body).lower()

    if _INAPPROPRIATE.search(text):
        return (-99.0, "inappropriate")
    if _SPAM.search(text):
        return (-99.0, "spam")

    words = re.findall(r"[a-z][a-z']+", text)
    if len(words) < 4:                            # "thanks", "ok", "5 stars" — no substance
        return (-5.0, "too_short")

    film = _film_score(text)
    file_ = _file_score(text)
    if _SELF_PROMO.search(text):
        file_ += 2

    # A genuine title review must have real film content AND not be dominated by
    # file/upload/quality talk. The 1.5x weight makes a file-leaning "mixed" review
    # (praises the transfer, mentions the plot in passing) fall below the bar.
    fit = film - 1.5 * file_
    if film == 0:
        return (fit, "file_only" if file_ > 0 else "no_substance")
    if fit <= 0:
        return (fit, "file_dominant")
    return (fit, "keep")


def keep_review(review: dict) -> bool:
    return score_review(review)[1] == "keep"


# ---------------------------------------------------------------------------
# Self-test against REAL archive.org reviews (fetched 2026-06-21). Run directly.
# ---------------------------------------------------------------------------
_SELFTEST = [
    # (expect_keep, reviewtitle, reviewbody)
    (False, "Audio format", "What format is the audio in the PS3 H.264 file?"),
    (False, "OK, I'll try again", "I'll upload the m2ts file again from a faster connection. IA might not let me get away with uploading a 16GB file"),
    (False, "Problem with m2ts file", "Thanks for the upload but there appears to be a problem with the m2ts file. Beginning at time 28:21 about 25 seconds repeats itself before continuing on."),
    (False, "m2ts file flawed", "The 16GB m2ts file is flawed in exactly the manner he mentioned. I'd like to request a re-rip and re-upload."),
    (False, "Beautiful picture!", "I downloaded the DVD-5 version (MPEG-2). It is absolutely beautiful! The download shows a very clear and cleaned up picture. MUCH better than the other download."),
    (False, "best version I've seen", "I have three other copies of this movie, and the quality of this download is by far the best. The video is also nice and clean."),
    (True, "Watch this!", "Excellent cinematography and beautiful sets make this rather tiresome zombie drama worth watching. Bela Lugosi plays a thoroughly evil zombie master in Haiti."),
    (True, "First Zombie", "This film was made in 1932 and it was the first time they used the word zombie for the undead. The story is atmospheric and the acting strong."),
    (True, "A True Classic!", "A must-have movie. Beautifully filmed, with excellent acting, atmospheric and compelling. Still holds up today."),
    (True, "The House on Haunted Hill", "Classic chilling horror from the master William Castle, Vincent Price gives a once in a lifetime performance in this wonderfully written and directed film."),
    (True, "SCOTCH AND", "Brilliant, what a masterpiece! Vincent Price in his most perfect role. I love this movie and its twist ending."),
    (True, "Who Likes Horror Movies", "I for one like horror movies and i have to say that this one was pretty good. How come Elisha Cook Jr. knew so much about the house? Vincent Price gives a great performance."),
]

if __name__ == "__main__":
    ok = 0
    for expect, t, b in _SELFTEST:
        fit, verdict = score_review({"reviewtitle": t, "reviewbody": b})
        got = verdict == "keep"
        flag = "OK " if got == expect else "XX "
        ok += got == expect
        print(f"  {flag} keep={got!s:5} fit={fit:6.1f} {verdict:13} {t[:34]!r}")
    print(f"\n{ok}/{len(_SELFTEST)} correct")
    raise SystemExit(0 if ok == len(_SELFTEST) else 1)
