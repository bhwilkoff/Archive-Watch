#!/usr/bin/env python3
"""Read the file a removal request names, and say whether the claim fits it
(docs/TAKEDOWNS.md, Decision 175).

Runs for ONE request at a time; it is never a catalog scan. Two things decide:

  * A modern layer. A public-domain film can reach us as a modern broadcast or
    a modern score, and archive.org's record does not say so: the Lubitsch
    "Madame Dubarry" of 2026-11-04 was an ARTE recording with its logo burned
    in. A logo is the one thing that stays still in the same place while every
    shot changes, so sampling frames across the film finds it.
  * Whether the claim is about this title. Notices are often matched on a title
    word: "UNIDENTIFIED" named a family's home movie because archive.org called
    it "Home Movie: 97390: Unidentified".

A complete notice removes the title unless the evidence contradicts the claim;
a contradiction goes to the owner. A file that could not be read is not evidence
of anything, so it can never hold a removal back (ENGINEERING-PROCESS §1).
"""
import datetime
import json
import re
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
import takedown_lib as T

FRAMES = 24
WIDTH = 320
SEEK_TIMEOUT = 60
UA = "ArchiveWatch-takedown-check"


# ── what a link points at ────────────────────────────────────────────────────

_LINK = re.compile(
    r"(?:archivewatch\.org/(?:#/)?(?P<kind>item|series)/|"
    r"archive\.org/(?:details|download)/)(?P<id>[^/?#\s\"'<>]+)", re.I)


def targets(links: str) -> list:
    """Every id a request names: `item/X`, `series/slug`, `archive.org/details/X`.
    A line that names nothing we can read comes back as {"unread": line}."""
    out, seen = [], set()
    for line in re.split(r"[\s,]+", links or ""):
        if not line:
            continue
        m = _LINK.search(urllib.parse.unquote(line))
        if not m:
            out.append({"unread": line[:200]})
            continue
        aid = m.group("id")
        if (m.group("kind") or "").lower() == "series" and not aid.startswith("series:"):
            aid = "series:" + aid
        if aid not in seen:
            seen.add(aid)
            out.append({"id": aid})
    return out


class Catalog:
    """What the site serves right now, read from the published files."""

    def __init__(self, repo=REPO):
        self.repo = repo
        idx = json.loads((repo / "catalog-index.json").read_text(encoding="utf-8"))
        f = {n: i for i, n in enumerate(idx["fields"])}
        self.items = {r[f["id"]]: {"title": r[f["title"]], "year": r[f["year"]],
                                   "contentType": r[f["contentType"]]}
                      for r in idx["items"]}
        al = repo / "aliases.json"
        self.aliases = json.loads(al.read_text(encoding="utf-8")) if al.exists() else {}
        self.episodes = {}
        self.spines = {}
        for p in (repo / "series").glob("*.json"):
            s = json.loads(p.read_text(encoding="utf-8"))
            slug = s.get("seriesID") or p.stem
            self.spines[slug] = s
            for season in s.get("seasons") or []:
                for e in season.get("episodes") or []:
                    if e.get("archiveID"):
                        self.episodes.setdefault(e["archiveID"], (s, e))

    def resolve(self, aid: str) -> str:
        """A merged-away id's page forwards to its survivor (Decision 085), so
        the survivor is what a link to it is showing."""
        return aid if aid in self.items else self.aliases.get(aid, aid)

    def find(self, aid: str):
        """{"title","year","contentType","url"} if we serve it, else None."""
        if aid.startswith("series:"):
            s = self.spines.get(aid.split(":", 1)[1])
            if not s:
                return None
            first = next((e for sn in s.get("seasons") or []
                          for e in sn.get("episodes") or [] if e.get("downloadURL")), {})
            return {"title": s.get("title"), "year": s.get("yearStart"),
                    "contentType": "tv-series", "url": first.get("downloadURL")}
        if aid in self.episodes:
            s, e = self.episodes[aid]
            return {"title": s.get("title"), "year": e.get("year"),
                    "contentType": "tv-episode", "url": e.get("downloadURL"),
                    "episode": e.get("title")}
        if aid in self.items:
            row = dict(self.items[aid])
            row["url"] = self._detail_url(aid)
            return row
        hits = [k for k in self.episodes if T.item_of(k) == aid]
        if hits:
            s, e = self.episodes[hits[0]]
            return {"title": s.get("title"), "year": e.get("year"),
                    "contentType": "tv-episode", "url": e.get("downloadURL")}
        return None

    def _detail_url(self, aid):
        p = self.repo / "details" / f"{_shard(aid)}.json"
        hit = json.loads(p.read_text(encoding="utf-8")).get(aid) if p.exists() else None
        return hit[0] if hit else None


def _shard(aid: str) -> str:
    """build_web_details' shard: FNV-1a 32-bit, low byte, hex."""
    h = 0x811C9DC5
    for b in aid.encode("utf-8"):
        h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
    return f"{h & 0xFF:02x}"


def archive_record(aid: str):
    """archive.org's own metadata, or None if it would not answer."""
    url = "https://archive.org/metadata/" + urllib.parse.quote(T.item_of(aid)) + "/metadata"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r).get("result")
    except Exception:
        return None


# ── what the file holds ──────────────────────────────────────────────────────

def probe(url: str):
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries",
             "format=duration:stream=codec_type,width,height", "-of", "json", url],
            capture_output=True, text=True, timeout=SEEK_TIMEOUT)
        d = json.loads(out.stdout)
        st = d.get("streams") or []
        v = next((s for s in st if s.get("codec_type") == "video"), None)
        if not v or not d.get("format", {}).get("duration"):
            return None
        return {"duration": float(d["format"]["duration"]),
                "width": v.get("width"), "height": v.get("height"),
                "hasAudio": any(s.get("codec_type") == "audio" for s in st)}
    except Exception:
        return None


def audio_level(url: str, duration: float):
    """Mean level in dB of 30 seconds from the middle, or None."""
    try:
        out = subprocess.run(
            ["ffmpeg", "-v", "info", "-ss", str(int(duration / 2)), "-t", "30", "-i", url,
             "-vn", "-af", "volumedetect", "-f", "null", "-"],
            capture_output=True, text=True, timeout=SEEK_TIMEOUT * 2)
        m = re.search(r"mean_volume:\s*(-?[\d.]+|-inf)", out.stderr)
        return float(m.group(1)) if m and m.group(1) != "-inf" else None
    except Exception:
        return None


def sample_frames(url: str, duration: float, height: int):
    import numpy as np
    frames = []
    for i in range(FRAMES):
        t = duration * (0.06 + 0.88 * i / (FRAMES - 1))
        try:
            r = subprocess.run(
                ["ffmpeg", "-v", "error", "-ss", f"{t:.1f}", "-i", url, "-frames:v", "1",
                 "-vf", f"scale={WIDTH}:{height}", "-pix_fmt", "gray", "-f", "rawvideo", "-"],
                capture_output=True, timeout=SEEK_TIMEOUT)
        except subprocess.TimeoutExpired:
            continue
        if len(r.stdout) == WIDTH * height:
            frames.append(np.frombuffer(r.stdout, np.uint8).reshape(height, WIDTH).astype("float32"))
    return frames


def _densest(hit, wh=16, ww=32) -> int:
    """The most hits in any wh x ww window: a logo is compact, and scattered
    noise is not. numpy alone, so the runner installs nothing else for it."""
    import numpy as np
    if hit.shape[0] < wh or hit.shape[1] < ww:
        return int(hit.sum())
    c = np.pad(hit.astype("int32").cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    return int((c[wh:, ww:] - c[:-wh, ww:] - c[wh:, :-ww] + c[:-wh, :-ww]).max())


def logo_score(frames):
    """{corner: score}, or None if too few frames were readable. A logo's edges
    point the same way in every frame while the picture behind it changes, so
    a pixel counts when its gradient is steady across the film. Asking instead
    for pixels that barely change misses a translucent logo entirely (ARTE's
    scored 0 that way). Near-black frames say nothing and are dropped first."""
    import numpy as np
    lit = [f for f in frames if f.mean() > 12]
    if len(lit) < 8:
        return None
    a = np.stack(lit)
    gy, gx = np.gradient(a, axis=(1, 2))
    root = np.sqrt(len(lit))
    steady = np.maximum(np.abs(gy.mean(0)) / (gy.std(0) / root + .05),
                        np.abs(gx.mean(0)) / (gx.std(0) / root + .05))
    strength = np.maximum(np.abs(gy.mean(0)), np.abs(gx.mean(0)))
    hit = (steady > 7) & (strength > 2)
    h, w = hit.shape
    bh, bw, my, mx = h // 4, w // 4, int(h * .05), int(w * .05)
    box = {"topLeft": (my, bh, mx, bw), "topRight": (my, bh, w - bw, w - mx),
           "bottomLeft": (h - bh, h - my, mx, bw),
           "bottomRight": (h - bh, h - my, w - bw, w - mx)}
    return {k: _densest(hit[y0:y1, x0:x1]) for k, (y0, y1, x0, x1) in box.items()}


# Measured 2026-11-04 over 14 films at these settings: an ARTE logo 111, a TV
# rip 185; ten clean films 0; a film frame's rounded border 31-48 in all four
# corners, which is why one corner must also stand out from the rest.
LOGO_MIN = 64


def has_logo(scores) -> bool:
    if not scores:
        return False
    top, second = sorted(scores.values(), reverse=True)[:2]
    return top >= LOGO_MIN and top >= 2 * second


def read_file(url: str) -> dict:
    """Everything the file itself says. `read` False means nothing was learned."""
    p = probe(url) if url else None
    if not p:
        return {"read": False}
    h = int(round(WIDTH * (p["height"] or 240) / (p["width"] or 320) / 2) * 2)
    frames = sample_frames(url, p["duration"], h)
    scores = logo_score(frames)
    level = audio_level(url, p["duration"]) if p["hasAudio"] else None
    return {"read": scores is not None, "minutes": round(p["duration"] / 60),
            "framesRead": len(frames), "logoScores": scores,
            "logo": has_logo(scores),
            "hasAudio": p["hasAudio"], "audioDb": level}


# ── does the claim fit ───────────────────────────────────────────────────────

def _words(s):
    return re.findall(r"[a-z0-9]+", (s or "").lower())


def name_fit(claimed: str, title: str) -> str:
    """same: the two name one work. partial: the claim is only some of the words
    of a longer title, a notice matched on a word. none: no words in common,
    which can be a translated title and proves nothing. unknown: no claim named."""
    c, t = _words(claimed), _words(title)
    if not c or not t:
        return "unknown"
    if "".join(c) == "".join(t) or set(t) <= set(c):
        return "same"
    return "partial" if set(c) & set(t) else "none"


def public_domain_by_age(year, today=None) -> bool:
    """Decision 137: published 95 full years ago, by the calendar."""
    today = today or datetime.date.today()
    return isinstance(year, int) and 1880 < year <= today.year - 96


def modern_layer(item: dict, ev: dict) -> list:
    out = []
    if ev.get("logo"):
        out.append("logo")
    silent = item.get("contentType") == "silent-film"
    if silent and ev.get("hasAudio") and (ev.get("audioDb") or -91) > -60:
        out.append("soundtrack")
    return out


def verdict(case: dict, item, ev: dict, today=None) -> dict:
    """{"action": remove|hold|none, "reason": ...}. Pure: the whole rule is here.
    `case` is {kind, complete, work}; `item` what we serve, or None."""
    if item is None:
        return {"action": "none", "reason": "not_served"}
    if case.get("kind") != "copyright":
        return {"action": "hold", "reason": "not_copyright"}
    if not case.get("complete"):
        return {"action": "hold", "reason": "incomplete_notice"}
    layer = modern_layer(item, ev)
    if layer:
        return {"action": "remove", "reason": "modern_layer", "layer": layer}
    fit = name_fit(case.get("work"), item.get("title"))
    if fit == "partial":
        return {"action": "hold", "reason": "title_word_only", "fit": fit}
    if ev.get("read") and public_domain_by_age(item.get("year"), today):
        return {"action": "hold", "reason": "public_domain_by_age", "fit": fit}
    return {"action": "remove", "reason": "complete_notice", "fit": fit}


if __name__ == "__main__":
    # A look at one id, for a person: takedown_check.py <id> [claimed work]
    cat = Catalog()
    aid = sys.argv[1]
    item = cat.find(aid)
    ev = read_file((item or {}).get("url")) if item else {"read": False}
    case = {"kind": "copyright", "complete": True, "work": " ".join(sys.argv[2:])}
    print(json.dumps({"item": item, "evidence": ev, "verdict": verdict(case, item, ev)}, indent=1))
