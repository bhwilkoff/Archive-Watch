#!/usr/bin/env python3
"""
probe_otr_corpus.py — measure the archive.org old-time-radio corpus for the
radio sister app (docs/research/radio/07-archive-org-ingest.md).

Read-only. Stdlib only. Polite: one request at a time, a pause between
requests, backoff on 429/5xx, resumable cache of metadata responses.

Outputs (in --out, default ./otr_probe):
  items.jsonl     one line per enumerated item (search fields + seed)
  meta/<id>.json  cached /metadata responses (sampled items)
  files.jsonl     one line per audio file with its parse
  report.json     the numbers
  report.txt      the same, readable

Usage:
  python3 tools/probe_otr_corpus.py                    # enumerate all, sample 400 items' metadata
  python3 tools/probe_otr_corpus.py --sample 0         # enumerate + count only
  python3 tools/probe_otr_corpus.py --sample all       # every item's metadata (slow: hours)
  python3 tools/probe_otr_corpus.py --pause 1.5 --out /tmp/otr
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import random
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

UA = "ArchiveWatch-OTRProbe/1.0 (https://archivewatch.org; research, read-only)"
SCRAPE = "https://archive.org/services/search/v1/scrape"
META = "https://archive.org/metadata/"

SEEDS = {
    "oldtimeradio": "collection:oldtimeradio",
    "otrr_ids": "identifier:OTRR_*",
    "subject_otr": 'subject:"old time radio"',
    "subject_otrr": 'subject:"otrr"',
    "lumedwards": "collection:lumedwards",
}
# Counted only (advancedsearch numFound), never enumerated: radioprograms is
# archive.org's umbrella "Radio Show and Programs Archive" (millions of items,
# mostly modern community audio), librivoxaudio is audiobooks.
COUNT_ONLY = [
    "collection:oldtimeradio", "collection:oldtimeradio AND mediatype:audio",
    "collection:radioprograms", "collection:librivoxaudio", "mediatype:radio",
    "identifier:OTRR_*", 'subject:"otrr"', 'subject:"old time radio"',
    'subject:"old time radio" AND NOT collection:oldtimeradio',
    "collection:lumedwards", "uploader:OTRRArchive*",
]
ADV = "https://archive.org/advancedsearch.php"
FIELDS = ("identifier,title,mediatype,collection,downloads,item_size,"
          "files_count,subject,licenseurl,publicdate,uploader")

AUDIO_EXT = (".mp3", ".ogg", ".flac", ".wav", ".m4a", ".opus", ".aiff", ".wma")

def get_json(url, params=None, *, pause, tries=6):
    if params:
        url = url + "?" + urllib.parse.urlencode(params)
    delay = max(pause, 1.0)
    for attempt in range(tries):
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                data = json.load(r)
            time.sleep(pause)
            return data
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504):
                time.sleep(delay); delay *= 2; continue
            print(f"HTTP {e.code} {url}", file=sys.stderr)
            return None
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            print(f"retry {attempt}: {e} {url}", file=sys.stderr)
            time.sleep(delay); delay *= 2
    return None


def scrape(q, *, pause, count=5000):
    # Seen 2026-10-17: some scrape calls answered a bogus single record
    # ("theses-and-dissertations", total 1) and total_only=true returned the
    # same total for every query; so totals are cross-checked against
    # advancedsearch numFound in the report, never trusted alone.
    total = None
    cursor = None
    while True:
        p = {"q": q, "fields": FIELDS, "count": count}
        if cursor:
            p["cursor"] = cursor
        d = get_json(SCRAPE, p, pause=pause)
        if d is None:
            return total
        if total is None:
            total = d.get("total")
        for it in d.get("items", []):
            yield it
        cursor = d.get("cursor")
        if not cursor:
            return total


def seconds(length):
    if length in (None, ""):
        return None
    parts = str(length).split(":")
    try:
        if len(parts) == 3:
            return int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])
        if len(parts) == 2:
            return int(parts[0]) * 60 + float(parts[1])
        return float(parts[0])
    except ValueError:
        return None


def stem(name):
    base = name.rsplit("/", 1)[-1]
    return re.sub(r"\.[A-Za-z0-9]{2,4}$", "", base)


def valid_date(y, m, d):
    try:
        y, m, d = int(y), int(m), int(d)
    except (TypeError, ValueError):
        return False
    if not (1920 <= y <= 1979 and 1 <= m <= 12 and 1 <= d <= 31):
        return False
    import datetime
    try:
        datetime.date(y, m, d)
        return True
    except ValueError:
        return False


# Filename families, in the order they are tried. Every example is a real
# file name measured 2026-10-17 (item id in brackets).
# yy may be "4x" (decade known, year not) or "xx"; month/day may be "xx".
_D = r"(?P<yyyy>19[2-7]\d)|(?P<yy>[2-7][\dx]|xx)"
_DATE_DASH = rf"(?:{_D})[-.](?P<mm>\d{{1,2}}|xx)[-.](?P<dd>\d{{1,2}}|xx)"
_NUM = r"(?P<num>\d{1,4}[A-Za-z]?|x{1,4})"
PATTERNS = [
    # "Suspense 420617 001 The Burning Court (128-44) 28455 30m00s"  [OTRR_Suspense_Singles_By_Year_1942]
    #  OTRR v2: series YYMMDD epNNN title (kbps-kHz) KiB MMmSSs
    ("F0_otrr_v2", re.compile(
        r"^(?P<series>.+?)[ _](?P<yy>\d{2}|xx)(?P<mm>\d{2}|xx)(?P<dd>\d{2}|xx)[ _]"
        r"(?P<num>\d{1,4}|x{1,4})[ _](?P<title>.+?)"
        r"(?:[ _]\((?P<kbps>\d{2,3})-(?P<khz>\d{2})\))?(?:[ _](?P<kib>\d{3,7}))?"
        r"(?:[ _](?P<mins>\d{1,3})m(?P<secs>\d{2})s)?$", re.I)),
    # "Whistler_42-05-16_ep001_Retribution", "Whistler_xx-xx-xx_epxxx_Kaleidoscope_epAFRTS",
    # "CP_42-03-01_ep001-Eddie_Cantor", "Dragnet_49-06-10_ep002_Homicide"   [OTRR_Whistler_Singles, CommandPerformance, Dragnet_OTR]
    ("F1_otrr_ep", re.compile(
        rf"^(?P<series>.+?)[ _-]+{_DATE_DASH}[ _-]+(?:ep)?{_NUM}[ _-]+(?P<title>.+?)"
        r"(?:_aka_(?P<aka>.+?))?(?:[ _-]ep(?P<variant>AFRTS|AFRS|Rehearsal|Audition))?$", re.I)),
    # "Space_Patrol_53-02-14_020_The_Mysterious_Meteor", "YTJD 1957-09-29 554 The Doubtful Dairy Matter [AFRTS]",
    # "MBF_5x.xx.xx_ep49_First_Song", "Lux_Radio_Theatre_45-11-05_500R_Destry_Rides_Again" are F1 too.
    # "Gunsmoke 52-04-26 (001) Billy the Kid", "The Shadow 1937-09-26 (87) The Death House Rescue",
    # "FMM 1931-06-01 (xx) Smackout"   [OTRR_Gunsmoke_Singles, the-shadow-..., fibber-mc-gee-and-molly]
    ("F1c_paren_num", re.compile(
        rf"^(?P<series>.+?)[ _-]+{_DATE_DASH}[ _-]*\({_NUM}\)[ _-]*(?P<title>.+)$", re.I)),
    # "Father Knows Best (055) 1950-11-02 Too Many Problems"   [OTRR_Father_Knows_Best_Singles]
    ("F1f_paren_num_first", re.compile(
        rf"^(?P<series>.+?)[ _-]*\({_NUM}\)[ _-]*{_DATE_DASH}[ _-]+(?P<title>.+)$", re.I)),
    # "XMinusOne55-04-24001NoContact", "LuxRadioTheatre46-09-02535OurVinesHaveTenderGrapes",
    # "LightsOut-1936-06-17CatWife"   [OTRR_X_Minus_One_Singles, OTRR_Lux_Radio_Theater_Singles, LightsOutoldTimeRadio]
    ("F1d_camel_glued", re.compile(
        rf"^(?P<series>[A-Za-z][A-Za-z'&]+?)[-_ ]?{_DATE_DASH}(?P<num>\d{{3,4}})?[-_ ]?(?P<title>[A-Za-z].*)$")),
    # "Pwh541114319AGuyNamedScottc" (YYMMDD + NNN glued, CamelCase)   [OTRR_Proudly_We_Hail_Singles]
    ("F0b_camel_yymmdd_num", re.compile(
        r"^(?P<series>[A-Za-z]+?)(?P<yy>[2-7]\d)(?P<mm>\d{2})(?P<dd>\d{2})(?P<num>\d{3,4})(?P<title>[A-Z].*)$")),
    # "Inner_Sanctum_-_450109_Desert_Death"   [Inner_Sanctum_otr]
    ("F2b_series_yymmdd_title", re.compile(
        r"^(?P<series>.+?)[ _-]+(?P<yy>[2-7]\d)(?P<mm>\d{2})(?P<dd>\d{2})[ _-]+(?P<title>[A-Za-z].*)$")),
    # "X Minus One 1955 04 24 No Contact ( 001)"   [xminusone19550424nocontact001 title]
    ("F3_spaced_date", re.compile(
        r"^(?P<series>.+?)[ _-]+(?P<yyyy>19[2-7]\d)[ _](?P<mm>\d{2})[ _](?P<dd>\d{2})"
        r"[ _-]*(?P<title>.*?)(?:\(\s*(?P<num>\d{1,4})\s*\))?$")),
    # "Series 42-06-17 Title" / "Series_1942-06-17_Title" (no episode number)
    ("F1e_series_date_title", re.compile(
        rf"^(?P<series>[A-Za-z].*?)[ _-]+{_DATE_DASH}[ _-]+(?P<title>[A-Za-z].*)$")),
    # "42-06-17_Burning_Court", "1932-05-02 - 001) First Show", "01 38-07-11 Dracula"
    #  no series in the name: the ITEM supplies it   [SUSPENSE, TheJackBennyProgram, OrsonWelles_MercuryTheatre]
    ("F7_date_first", re.compile(
        rf"^(?:\d{{1,3}}[ _.-]+)?{_DATE_DASH}[ _-]*(?:-[ _]*)?(?:\(?(?P<num>\d{{1,4}})\)[ _-]*)?(?P<title>.*)$")),
    # "SuspenseTheHitchHiker09021942"   [SuspenseTheHitchHiker09021942]
    ("F4_us_mmddyyyy", re.compile(
        r"^(?P<head>.+?)[ _-]*(?P<mm>0[1-9]|1[0-2])[-_ ]?(?P<dd>[0-3]\d)[-_ ]?(?P<yyyy>19[2-7]\d)$")),
    # "xminusone_550424_NoContact", "X_Minus_One_560515_Hallucination_Orbit", "TSP420617",
    # "JackBennyProgram481017SorryWrongNumber"
    ("F2_yymmdd", re.compile(
        r"^(?P<series>[A-Za-z][A-Za-z_ ]*?)[_ -]?(?P<yy>[1-7]\d)(?P<mm>0[1-9]|1[0-2])"
        r"(?P<dd>0[1-9]|[12]\d|3[01])(?:[_ -]?(?P<title>[A-Za-z].*))?$")),
    # "Dimension X 011 Zero Hour" (number, no date)
    ("F5_number", re.compile(
        r"^(?P<series>.+?)[ _-]+(?:#|ep\.?|no\.?\s*)?(?P<num>\d{1,4})[ _-]+(?P<title>[A-Za-z].+)$", re.I)),
    # "X_Minus_One-A_Gun_for_Dinosaur" (series + title, nothing else)   [xminusoneotr]
    ("F8_series_dash_title", re.compile(r"^(?P<series>[A-Za-z][A-Za-z_ ]+?)-(?P<title>[A-Za-z].+)$")),
]
# The OTRR sets also write identity into the ID3 album tag:
# album "04/26/52, episode 1"   [OTRR_Gunsmoke_Singles, OTRR_X_Minus_One_Singles, OTRR_Lux_Radio_Theater_Singles]
ALBUM_TAG = re.compile(r"^(?P<mm>\d{1,2}|xx)/(?P<dd>\d{1,2}|xx)/(?P<yy>\d{2}|xx),\s*episode\s*(?P<num>\d{1,4}|x+)", re.I)
AFRS = re.compile(r"(?:^|[ _(\[{\-]|(?<=[a-z]))(afrs|afrts)(?:$|[ _)\]}\-])", re.I)


def _date(g, fam):
    yyyy = g.get("yyyy")
    yy = g.get("yy")
    if not yyyy and yy and yy.lower() != "xx":
        yyyy = "19" + yy
    mm, dd = g.get("mm") or "", g.get("dd") or ""
    if not yyyy or not mm or not dd or "x" in (mm + dd).lower():
        return None, False
    if valid_date(yyyy, mm, dd):
        return f"{yyyy}-{int(mm):02d}-{int(dd):02d}", False
    if yy and valid_date("19" + dd, yy, mm):          # MM-DD-YY written in a YY-MM-DD slot
        return f"19{dd}-{int(yy):02d}-{int(mm):02d}", True
    return None, None                                  # digits that are not a date


def parse(name):
    s = stem(name)
    for fam, rx in PATTERNS:
        m = rx.match(s)
        if not m:
            continue
        g = m.groupdict()
        date, swapped = _date(g, fam)
        if swapped is None and fam in ("F0_otrr_v2", "F0b_camel_yymmdd_num", "F2_yymmdd",
                                       "F2b_series_yymmdd_title", "F1d_camel_glued",
                                       "F7_date_first", "F1e_series_date_title"):
            continue
        if swapped:
            fam += "_mdy"
        if g.get("head") is not None:
            head = re.sub(r"[_]+", " ", g["head"]).strip(" -")
            ser, _, ttl = head.partition(":") if ":" in head else ("", "", head)
            g = dict(g, series=ser.strip(), title=ttl.strip())
        series = re.sub(r"[_]+", " ", g.get("series") or "").strip(" -") or None
        num = g.get("num")
        variant = g.get("variant") or (AFRS.search(s).group(1).upper() if AFRS.search(s) else None)
        yy = g.get("yy") or ""
        decade = (g.get("yyyy") or "")[:3] + "0s" if g.get("yyyy") else \
            ("19" + yy[0] + "0s" if yy[:1].isdigit() else None)
        return {"family": fam, "series": series, "date": date, "decade": decade,
                "num": None if not num or "x" in num.lower() else int(re.sub(r"\D", "", num)),
                "title": re.sub(r"[_]+", " ", g.get("title") or "").strip(" -") or None,
                "aka": re.sub(r"[_]+", " ", g.get("aka") or "").strip() or None,
                "variant": variant}
    return {"family": "F6_none", "series": None, "date": None, "decade": None, "num": None,
            "title": None, "aka": None, "variant": None}


def parse_album_tag(album):
    m = ALBUM_TAG.match((album or "").strip())
    if not m:
        return None
    g = m.groupdict()
    date, _ = _date(g, "tag")
    num = g.get("num")
    return {"date": date, "num": None if "x" in num.lower() else int(num)}


def norm_series(s):
    s = (s or "").lower()
    s = re.sub(r"^(otrr|the)\s+", "", s)
    s = re.sub(r"theatre", "theater", s)
    return re.sub(r"[^a-z0-9]", "", s)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="otr_probe")
    ap.add_argument("--sample", default="400", help="items whose metadata to fetch: N, 0 or all")
    ap.add_argument("--pause", type=float, default=1.0, help="seconds between requests")
    ap.add_argument("--seed", type=int, default=17)
    a = ap.parse_args()
    os.makedirs(os.path.join(a.out, "meta"), exist_ok=True)

    report = {"seeds": {}, "date": time.strftime("%Y-%m-%d"), "numFound": {}}
    for q in COUNT_ONLY:
        d = get_json(ADV, {"q": q, "rows": 0, "output": "json"}, pause=a.pause)
        report["numFound"][q] = (d or {}).get("response", {}).get("numFound")
    items = {}
    for key, q in SEEDS.items():
        n = 0
        gen = scrape(q, pause=a.pause)
        try:
            while True:
                it = next(gen)
                n += 1
                rec = items.setdefault(it["identifier"], dict(it, seeds=[]))
                rec["seeds"].append(key)
        except StopIteration as stop:
            total = stop.value
        report["seeds"][key] = {"query": q, "reported_total": total, "read": n}
        print(f"{key:16} total={total} read={n}", file=sys.stderr)

    with open(os.path.join(a.out, "items.jsonl"), "w") as fh:
        for it in items.values():
            fh.write(json.dumps(it) + "\n")

    combo = collections.Counter("+".join(sorted(it["seeds"])) for it in items.values())
    report["seed_overlap"] = combo.most_common(20)
    coll = collections.Counter()
    for it in items.values():
        c = it.get("collection") or []
        for x in (c if isinstance(c, list) else [c]):
            coll[x] += 1
    report["collections_of_items_top"] = coll.most_common(40)
    mt = collections.Counter(str(it.get("mediatype")) for it in items.values())
    report["unique_items"] = len(items)
    report["mediatype"] = dict(mt.most_common())
    report["otrr_items"] = sum(1 for i in items if i.startswith("OTRR_"))
    lic = collections.Counter(str(it.get("licenseurl") or "none") for it in items.values())
    report["licenseurl_top"] = lic.most_common(15)
    fc = [int(it.get("files_count") or 0) for it in items.values() if it.get("files_count")]
    if fc:
        fc.sort()
        report["files_count_per_item"] = {"median": fc[len(fc) // 2], "p90": fc[int(len(fc) * .9)],
                                          "max": fc[-1], "sum": sum(fc)}
    report["item_bytes_sum"] = sum(int(it.get("item_size") or 0) for it in items.values())

    ids = sorted(items)
    if a.sample == "all":
        pick = ids
    else:
        k = int(a.sample)
        random.Random(a.seed).shuffle(ids)
        otrr = [i for i in ids if i.startswith("OTRR_")]
        pick = (otrr[: k // 2] + [i for i in ids if not i.startswith("OTRR_")])[:k] if k else []

    fam = collections.Counter(); fam_otrr = collections.Counter()
    fmt = collections.Counter(); src = collections.Counter()
    tags = collections.Counter(); series_files = collections.Counter()
    file_keys = collections.Counter(); series_files_otrr = collections.Counter()
    orig_fmt = collections.Counter(); deriv_fmt = collections.Counter()
    item_hours = []
    dated = 0; tag_dated = 0; tag_only = 0; tag_agree = 0; tag_disagree = 0
    variants = collections.Counter(); no_series_in_name = 0
    per_item_audio = []
    md5s = collections.Counter(); bcast = collections.defaultdict(set)
    secs_total = 0.0; secs_known = 0; audio_files = 0
    with open(os.path.join(a.out, "files.jsonl"), "w") as fh:
        for n, iaid in enumerate(pick, 1):
            path = os.path.join(a.out, "meta", iaid.replace("/", "_") + ".json")
            if os.path.exists(path):
                with open(path) as f:
                    meta = json.load(f)
            else:
                meta = get_json(META + urllib.parse.quote(iaid), pause=a.pause)
                if not meta:
                    continue
                with open(path, "w") as f:
                    json.dump(meta, f)
            if n % 25 == 0:
                print(f"meta {n}/{len(pick)}", file=sys.stderr)
            files = meta.get("files") or []
            for f in files:
                fmt[str(f.get("format"))] += 1
                if (f.get("name") or "").lower().endswith(AUDIO_EXT):
                    for k in f:
                        file_keys[k] += 1
                    (orig_fmt if f.get("source") == "original" else deriv_fmt)[str(f.get("format"))] += 1
            ih = 0.0
            audio = [f for f in files if (f.get("name") or "").lower().endswith(AUDIO_EXT)
                     and str(f.get("private", "")).lower() != "true"
                     and not re.search(r"(^|/)history/|\.~\d+~$", f.get("name") or "")]
            # one row per WORK: an original plus its derivatives count once
            works = {}
            for f in audio:
                works.setdefault(stem(f.get("original") or f["name"]), []).append(f)
            per_item_audio.append(len(works))
            for wk, group in works.items():
                audio_files += 1
                orig = next((g for g in group if g.get("source") == "original"), group[0])
                src[str(orig.get("source"))] += 1
                p = parse(orig["name"])
                tp = parse_album_tag(orig.get("album"))
                if p["date"]:
                    dated += 1
                if tp and tp["date"]:
                    tag_dated += 1
                    if not p["date"]:
                        tag_only += 1
                    elif tp["date"] == p["date"]:
                        tag_agree += 1
                    else:
                        tag_disagree += 1
                if p.get("decade") and not p["date"]:
                    variants["decade_only_date"] += 1
                if p["variant"]:
                    variants[p["variant"]] += 1
                if p["family"] != "F6_none" and not p["series"]:
                    no_series_in_name += 1
                fam[p["family"]] += 1
                if iaid.startswith("OTRR_"):
                    fam_otrr[p["family"]] += 1
                for t in ("title", "track", "album", "creator", "artist", "genre"):
                    if orig.get(t):
                        tags[t] += 1
                s = seconds(orig.get("length"))
                if s:
                    secs_total += s; secs_known += 1; ih += s
                if orig.get("md5"):
                    md5s[orig["md5"]] += 1
                ser = norm_series(p["series"] or (meta.get("metadata") or {}).get("title"))
                series_files[ser] += 1
                if iaid.startswith("OTRR_"):
                    series_files_otrr[ser] += 1
                if p["date"]:
                    bcast[(ser, p["date"])].add(iaid)
                fh.write(json.dumps({"id": iaid, "name": orig["name"], "format": orig.get("format"),
                                     "source": orig.get("source"), "length": orig.get("length"),
                                     "size": orig.get("size"), "md5": orig.get("md5"),
                                     "tag_title": orig.get("title"), "tag_track": orig.get("track"),
                                     **p}) + "\n")
            item_hours.append((iaid, round(ih / 3600, 1), len(works)))

    if pick:
        per_item_audio.sort()
        report["sampled_items"] = len(per_item_audio)
        report["audio_works_in_sample"] = audio_files
        report["audio_works_per_item"] = {
            "median": per_item_audio[len(per_item_audio) // 2] if per_item_audio else 0,
            "single_episode_items": sum(1 for x in per_item_audio if x == 1),
            "multi_episode_items": sum(1 for x in per_item_audio if x > 1),
            "max": per_item_audio[-1] if per_item_audio else 0}
        report["filename_family"] = {k: [v, round(v / max(audio_files, 1), 3)] for k, v in fam.most_common()}
        report["filename_family_otrr"] = dict(fam_otrr.most_common())
        report["format_all_files"] = fmt.most_common(30)
        report["audio_source"] = dict(src)
        report["tag_hit_rate"] = {k: round(v / max(audio_files, 1), 3) for k, v in tags.items()}
        report["hours_in_sample"] = round(secs_total / 3600, 1)
        report["length_known_rate"] = round(secs_known / max(audio_files, 1), 3)
        report["date_coverage"] = {
            "filename_date": round(dated / max(audio_files, 1), 3),
            "album_tag_date": round(tag_dated / max(audio_files, 1), 3),
            "date_from_tag_only": tag_only, "tag_agrees_with_name": tag_agree,
            "tag_disagrees_with_name": tag_disagree,
            "any_date": round((dated + tag_only) / max(audio_files, 1), 3)}
        report["variants"] = dict(variants)
        report["parsed_but_series_from_item"] = no_series_in_name
        report["md5_duplicates"] = sum(v - 1 for v in md5s.values() if v > 1)
        report["broadcasts_in_several_items"] = sum(1 for v in bcast.values() if len(v) > 1)
        report["distinct_dated_broadcasts"] = len(bcast)
        report["top_series_by_files"] = series_files.most_common(40)
        report["top_series_by_files_otrr"] = series_files_otrr.most_common(40)
        report["audio_file_keys"] = file_keys.most_common()
        report["audio_format_original"] = orig_fmt.most_common(20)
        report["audio_format_derivative"] = deriv_fmt.most_common(20)
        report["biggest_items_by_hours"] = sorted(item_hours, key=lambda x: -x[1])[:25]
        if a.sample != "all" and report.get("files_count_per_item"):
            report["note"] = ("sample-based numbers; scale by unique_items/sampled_items "
                              "only as a rough estimate")

    with open(os.path.join(a.out, "report.json"), "w") as fh:
        json.dump(report, fh, indent=2)
    with open(os.path.join(a.out, "report.txt"), "w") as fh:
        for k, v in report.items():
            fh.write(f"{k}: {json.dumps(v)}\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()