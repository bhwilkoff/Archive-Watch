#!/usr/bin/env python3
"""
subtitle_asset.py — where an item's published WebVTT actually lives.

ONE resolver, because three copies of this guess produced two defects.

`build_subtitle_assets.py` names a published track after its LANGUAGE:
`<id>/en.vtt`, `<id>/zh.vtt`, `<id>/de.vtt`. Two auditors derived the path
instead by appending `/en.vtt` to the HLS master's directory, unconditionally:

  * `audit_dead_subtitles.py` asked for a file that was never written, got a
    definitive 404, and CONDEMNED the track — 35 healthy films lost
    `subtitleHLS` that way, keeping their captions on the web (which reads the
    caption's own vttURL) and losing them in every app. Measured 2026-09-11:
    all 35 answer 200 on both the VTT and the master today.
  * `audit_subtitle_rate.py` made the same guess. It never condemns on a fetch
    failure, so it did no damage — it simply counted every non-English track
    "unfetchable" and never checked one for timing drift.

The Swift twin (`Catalog.Item.publishedVTTURL`) had the right shape all
along: prefer the caption's OWN recorded URL, English first, and treat the
`en.vtt` sibling as a last resort. This mirrors it.
"""

from __future__ import annotations


def published_vtt_url(item) -> str | None:
    """The URL of the VTT this item actually publishes, or None.

    Order, matching Catalog.Item.publishedVTTURL on Apple:
      1. an English caption's recorded `vttURL`
      2. any caption's recorded `vttURL`
      3. the HLS master's sibling named for a caption's language
      4. `en.vtt` — only when the item records nothing at all
    """
    hls = item.get("subtitleHLS")
    if not hls:
        return None
    caps = item.get("captions") or []
    for c in caps:
        if c.get("vttURL") and (c.get("lang") or "").lower().startswith("en"):
            return c["vttURL"]
    for c in caps:
        if c.get("vttURL"):
            return c["vttURL"]
    base = hls.rsplit("/", 1)[0]
    for c in caps:
        if c.get("lang"):
            return f"{base}/{c['lang']}.vtt"
    return f"{base}/en.vtt"
