#!/usr/bin/env python3
"""
tvdb_lib.py — minimal TheTVDB v4 client (login + search + extended).

TheTVDB has professional posters + overviews + cast for TV and movies, reaching
obscure public-domain titles TMDb/TVmaze miss. Key from env THETVDB_API_KEY or
Secrets.xcconfig (gitignored) — NEVER committed.
"""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://api4.thetvdb.com/v4"
UA = "ArchiveWatch-tvdb"


def load_key(secrets_path: Path | None = None) -> str | None:
    v = os.environ.get("THETVDB_API_KEY")
    if v:
        return v.strip()
    if secrets_path and secrets_path.exists():
        for line in secrets_path.read_text().splitlines():
            if line.strip().startswith("THETVDB_API_KEY"):
                return line.partition("=")[2].strip()
    return None


def _req(url: str, token: str | None = None, data: dict | None = None):
    headers = {"User-Agent": UA, "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, headers=headers,
                                 method="POST" if data is not None else "GET")
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 429:
                time.sleep(2 ** attempt + 1); continue
            if e.code in (404,):
                return None
            return None
        except (urllib.error.URLError, TimeoutError):
            time.sleep(2 ** attempt); continue
    return None


def login(key: str) -> str | None:
    res = _req(f"{API}/login", data={"apikey": key})
    return (res or {}).get("data", {}).get("token")


def search(token: str, query: str, kind: str, year: int | None = None) -> list:
    params = {"query": query, "type": kind}
    if year:
        params["year"] = str(year)
    res = _req(f"{API}/search?{urllib.parse.urlencode(params)}", token)
    return (res or {}).get("data") or []


def series_extended(token: str, tvdb_id) -> dict | None:
    res = _req(f"{API}/series/{tvdb_id}/extended", token)
    return (res or {}).get("data")


def movie_extended(token: str, tvdb_id) -> dict | None:
    res = _req(f"{API}/movies/{tvdb_id}/extended", token)
    return (res or {}).get("data")


def best_poster(extended: dict) -> str | None:
    """Highest-scored poster (artwork type 2), else the series `image`."""
    arts = [a for a in (extended.get("artworks") or []) if a.get("type") == 2 and a.get("image")]
    if arts:
        arts.sort(key=lambda a: a.get("score") or 0, reverse=True)
        return arts[0]["image"]
    return extended.get("image")


def cast_from(extended: dict, cap: int = 18) -> list:
    """TheTVDB characters -> [{name, character, order, profilePath}], deduped."""
    out, seen = [], set()
    chars = sorted((extended.get("characters") or []),
                   key=lambda c: c.get("sort") or 9999)
    for c in chars:
        name = (c.get("personName") or "").strip()
        if not name or name in seen:
            continue
        seen.add(name)
        out.append({"name": name,
                    "character": (c.get("name") or "").strip(),
                    "order": len(out),
                    "profilePath": c.get("personImgURL") or c.get("image")})
        if len(out) >= cap:
            break
    return out
