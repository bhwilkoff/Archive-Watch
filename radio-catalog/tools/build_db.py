"""Build the radio catalog database from the harvested caches.

    python3 tools/build_db.py            -> out/radio-catalog.sqlite, out/build_report.json

Inputs (all under .cache/, written by the harvest_* and fetch_* tools):
  meta/<id>.json.gz          archive.org items, slimmed
  librivox.json.gz           LibriVox dramatic works
  radioechoes/series/*.json  the episode spine (owner: RadioEchoes as spine)
  p72_schedules.json.gz      the Copyright Office's pre-1972 schedules
plus editorial/*.json and Archive Watch's shared/editorial/cce_renewals.json.

Model (docs/research/RADIO-DRAMA.md §4): series -> episode (the broadcast,
keyed by series + air date) -> recording (a file in an archive.org item).
"""
import collections
import datetime
import glob
import gzip
import json
import os
import re
import sqlite3
import statistics
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
import ia_lib as ia
import otr_parse as P
import audit_audio_rights as A

AW_RENEWALS = os.path.join(os.path.dirname(ia.ROOT), "shared", "editorial", "cce_renewals.json")
PLAYABLE = {"VBR MP3": 0, "128Kbps MP3": 0, "320Kbps MP3": 0, "256Kbps MP3": 0, "192Kbps MP3": 0,
            "160Kbps MP3": 0, "96Kbps MP3": 0, "64Kbps MP3": 0, "48Kbps MP3": 0, "32Kbps MP3": 0,
            "24Kbps MP3": 0, "16Kbps MP3": 0, "MP3": 0, "Ogg Vorbis": 1, "MPEG-4 Audio": 2, "Opus": 2}
ITEM_NOISE = re.compile(
    r"\b(otrr|certified|maintained|non[- ]?maintained|curated|singles?|and doubles|set|sets|collection|"
    r"old[- ]time[- ]radio|otr|radio shows?|radio programs?|radio drama|episodes?|complete|"
    r"by year|vol(ume)?\.?\s*\d+|part\s*\d+|\d{4}(\s*-\s*\d{2,4})?|mp3s?|archive|library)\b", re.I)


def load(path, default):
    return ia.read_json(path) if os.path.exists(path) else default


def item_series(item):
    t = item.get("title") or item.get("identifier") or ""
    t = re.sub(r"[_]+", " ", t)
    t = ITEM_NOISE.sub(" ", t)
    t = re.sub(r"[\[\]()\-:,.#]+", " ", t)
    return re.sub(r"\s+", " ", t).strip() or None


def seconds(v):
    return P.seconds(v)


def bitrate_kbps(f):
    s, l = f.get("size"), seconds(f.get("length"))
    try:
        return round(int(s) * 8 / l / 1000) if s and l else None
    except (ValueError, ZeroDivisionError):
        return None


def stem_key(name):
    s = name.rsplit("/", 1)[-1]
    s = re.sub(r"\.[A-Za-z0-9]{2,4}$", "", s)
    return re.sub(r"_(64kb|128kb|vbr|sample)$", "", s, flags=re.I)


def pick_files(files):
    """One playable file per stem: the uploaded MP3 when there is one (92% are VBR MP3
    and archive.org derives only Ogg from them, MEASURED), else the best derivative."""
    by = collections.defaultdict(list)
    for f in files:
        if f.get("private") in ("true", True) or f.get("format") not in PLAYABLE:
            continue
        by[stem_key(f["name"])].append(f)
    out = []
    for st, fs in by.items():
        fs.sort(key=lambda f: (PLAYABLE[f["format"]], f.get("source") != "original", -(bitrate_kbps(f) or 0)))
        out.append(fs[0])
    return out


class SeriesResolver:
    def __init__(self, aliases, known):
        self.aliases = {k: v for k, v in aliases.items() if not k.startswith("_")}
        self.known = known  # norm -> display name

    def key(self, raw):
        n = P.norm_series(raw)
        if n in self.aliases:
            return P.norm_series(self.aliases[n]), self.aliases[n]
        return n, raw

    def resolve(self, file_series, item_series_name):
        cands = []
        for raw, origin in ((file_series, "file"), (item_series_name, "item")):
            if raw:
                k, disp = self.key(raw)
                if k:
                    cands.append((k, disp, origin))
        for k, disp, origin in cands:
            if k in self.known:
                return k, self.known[k], origin + ":known"
        for k, disp, origin in cands:
            if origin == "file" and len(k) >= 5:
                return k, disp, "file"
        if cands:
            k, disp, origin = cands[-1]
            return k, disp, origin
        return None, None, "none"


def build_schedule_index(rows):
    by_title = collections.defaultdict(list)
    by_artist = collections.defaultdict(list)
    for r in rows:
        nt = A.norm_title(r.get("title"))
        if len(nt) >= 10:
            by_title[nt].append(r)
        for a in (r.get("artist") or "", r.get("album") or ""):
            na = P.norm_series(a)
            if len(na) >= 6:
                by_artist[na].append(r)
    return by_title, by_artist


def make_schedule_matcher(by_title, by_artist):
    def tokens(s):
        return {w for w in re.findall(r"[a-z]{4,}", (s or "").lower())}

    def match(ep):
        hits = []
        for r in by_artist.get(ep["series_key"], [])[:5]:
            hits.append({"source": "pre-1972 schedule (series named as artist/album)", "title": r.get("title"),
                         "artist": r.get("artist"), "rights_owner": r.get("rights_owner"),
                         "indexed": r.get("index_date")})
        nt = A.norm_title(ep.get("title"))
        if nt and len(nt) >= 10:
            st = tokens(ep.get("series_name")) | set().union(*[tokens(x.get("creator")) for x in ep["recordings"]])
            for r in by_title.get(nt, []):
                if st & tokens(r.get("artist")):
                    hits.append({"source": "pre-1972 schedule (episode title + artist)", "title": r.get("title"),
                                 "artist": r.get("artist"), "rights_owner": r.get("rights_owner"),
                                 "indexed": r.get("index_date")})
        return hits
    return match


def main():
    t0 = time.time()
    os.makedirs(ia.OUT, exist_ok=True)
    ed = lambda n: load(os.path.join(ia.EDITORIAL, n), {})
    aliases = ed("series_aliases.json")
    claims = {k: v for k, v in ed("audio_claims.json").items() if not k.startswith("_")}
    gov = {k: v for k, v in ed("gov_series.json").items() if not k.startswith("_")}
    takedowns = list((ed("takedowns.json").get("requests") or {}).values())
    lic_ev = ed("licence_evidence.json").get("evidence") or {}
    pub_rec = ed("published_records.json").get("records") or {}

    # The spine: RadioEchoes series names are the canonical display names.
    re_series = []
    for f in sorted(glob.glob(os.path.join(ia.CACHE, "radioechoes", "series", "*.json"))):
        re_series.append(ia.read_json(f))
    known = {}
    re_by_key = {}
    for s in re_series:
        k = P.norm_series(s["series"])
        if k:
            known.setdefault(k, s["series"])
            re_by_key.setdefault(k, []).append(s)
    for d in (gov, claims):
        for k, v in d.items():
            known.setdefault(k, v["series"])
    for v in aliases.values() if isinstance(aliases, dict) else []:
        if isinstance(v, str):
            known.setdefault(P.norm_series(v), v)
    resolver = SeriesResolver(aliases, known)

    items = {}
    episodes = {}
    stats = collections.Counter()
    meta_files = sorted(glob.glob(os.path.join(ia.CACHE, "meta", "*.json.gz")))
    for mf in meta_files:
        d = ia.read_json(mf)
        it = d["item"]
        for k in ("title", "creator", "publisher", "contributor", "licenseurl", "uploader", "publicdate"):
            if isinstance(it.get(k), list):
                it[k] = "; ".join(str(x) for x in it[k])
        ident = it.get("identifier") or os.path.basename(mf)[:-8]
        colls = it.get("collection") or []
        colls = [colls] if isinstance(colls, str) else colls
        text = " ".join(str(it.get(k) or "") for k in ("title", "description", "subject", "creator", "publisher",
                                                     "contributor", "source", "notes"))
        isr = item_series(it)
        items[ident] = {"id": ident, "title": it.get("title"), "collections": colls,
                        "licenseurl": it.get("licenseurl"), "uploader": it.get("uploader"),
                        "publicdate": it.get("publicdate"), "is_dark": d.get("is_dark"),
                        "reviews": d["reviews"]["count"], "avg_stars": d["reviews"]["avg_stars"],
                        "transcripts": len(d.get("transcripts") or []), "item_series": isr}
        tstems = {stem_key(t).replace("_asr", "") for t in d.get("transcripts") or []}
        chosen = pick_files(d["files"])
        n_audio = len(chosen)
        for f in chosen:
            stats["files"] += 1
            p = P.parse(f["name"])
            if not p["date"]:
                # Fallbacks, in order: the ID3 title tag, then for a single-episode
                # item its own title and identifier.
                alts = [f.get("title") if isinstance(f.get("title"), str) else None] + ([it.get("title"), ident] if n_audio <= 2 else [])
                for alt in alts:
                    q = P.parse(alt or "") if alt else None
                    if q and q["date"]:
                        p = dict(q, series=q["series"] or p["series"], title=q["title"] or p["title"],
                                 family=q["family"] + "+alt")
                        break
            stats["family:" + p["family"]] += 1
            tag = P.parse_album_tag(f.get("album"))
            date = p["date"] or (tag or {}).get("date")
            date_source = "filename" if p["date"] else ("album_tag" if tag and tag.get("date") else None)
            if p["date"] and tag and tag.get("date") and tag["date"] != p["date"]:
                stats["date_tag_disagrees"] += 1
            key, sname, how = resolver.resolve(p["series"], isr)
            stats["series:" + how] += 1
            title = p["title"] or (f.get("title") if not P.parse(f.get("title") or "")["date"] else None)
            num = p["num"] if p["num"] is not None else (tag or {}).get("num")
            if not key:
                ek = f"x:{ident}/{f['name']}"
            elif date:
                ek = f"{key}|{date}"
            elif num is not None:
                ek = f"{key}|n{num}"
            elif title:
                ek = f"{key}|t{A.norm_title(title)}"
            else:
                ek = f"x:{ident}/{f['name']}"
            ep = episodes.setdefault(ek, {"id": ek, "series_key": key, "series_name": sname, "date": date,
                                          "date_source": date_source, "num": num, "title": title,
                                          "aka": p["aka"], "decade": p["decade"], "recordings": []})
            if not ep["title"] and title:
                ep["title"] = title
            ep["recordings"].append({
                "archive_id": ident, "file": f["name"], "format": f.get("format"), "source": f.get("source"),
                "size": int(f["size"]) if str(f.get("size", "")).isdigit() else None,
                "length_s": seconds(f.get("length")), "kbps": bitrate_kbps(f), "md5": f.get("md5"),
                "variant": p["variant"], "collections": colls, "is_dark": d.get("is_dark"),
                "creator": f.get("creator") or f.get("artist") or it.get("creator"),
                "item_text": text + " " + " ".join(str(f.get(k) or "") for k in ("album", "genre", "artist")),
                "producer_text": " ".join(str(it.get(k) or "") for k in ("creator", "publisher", "contributor")),
                "otrr": ident.upper().startswith("OTRR_") or "lumedwards" in colls,
                "transcript": stem_key(f["name"]) in tstems,
                "url": f"https://archive.org/download/{ident}/{f['name']}"})

    # LibriVox: each project is a "play" series; its sections are its parts.
    lv = load(os.path.join(ia.CACHE, "librivox.json.gz"), [])
    for b in lv:
        key = "librivox" + str(b["id"])
        name = b.get("title")
        known[key] = name
        for sec in sorted(b.get("sections") or [], key=lambda s: int(s.get("section_number") or 0)):
            ek = f"{key}|s{sec.get('section_number')}"
            episodes[ek] = {"id": ek, "series_key": key, "series_name": name, "date": None, "date_source": None,
                            "num": int(sec.get("section_number") or 0), "title": sec.get("title"), "aka": None,
                            "decade": None, "librivox": True,
                            "recordings": [{"archive_id": (b.get("url_iarchive") or "").rstrip("/").rsplit("/", 1)[-1],
                                            "file": sec.get("file_name") or "", "format": "64Kbps MP3",
                                            "source": "librivox", "size": None,
                                            "length_s": seconds(sec.get("playtime")), "kbps": 64, "md5": None,
                                            "variant": None, "collections": ["librivoxaudio"], "is_dark": False,
                                            "creator": ", ".join(r.get("display_name") or "" for r in sec.get("readers") or []),
                                            "item_text": "", "producer_text": "", "otrr": False, "transcript": False,
                                            "url": sec.get("listen_url")}]}
            stats["librivox_sections"] += 1

    # Series-level evidence.
    by_series = collections.defaultdict(list)
    for ep in episodes.values():
        if ep["series_key"]:
            by_series[ep["series_key"]].append(ep)
    series_foreign, series_post = {}, {}
    for k, eps in by_series.items():
        recs = [r for e in eps for r in e["recordings"]]
        hits = [A.FOREIGN.search(r["item_text"]) for r in recs]
        n = sum(1 for h in hits if h)
        if recs and n >= 2 and n / len(recs) >= 0.5:
            series_foreign[k] = {"source": "item metadata names a non-US broadcaster",
                                 "term": collections.Counter(h.group(0) for h in hits if h).most_common(1)[0][0],
                                 "share": round(n / len(recs), 2)}
        dated = [e["date"] for e in eps if e["date"]]
        if dated and min(dated) >= "1972-02-15":
            series_post[k] = {"source": "every dated episode is after 1972-02-15", "earliest": min(dated)}

    film_ren = collections.defaultdict(list)
    for r in load(AW_RENEWALS, []):
        film_ren[A.norm_title(r["t"])].append(r)
    sched = load(os.path.join(ia.CACHE, "p72_schedules.json.gz"), {"rows": []})
    if not sched["rows"]:
        print("WARNING: no pre-1972 schedules cached; rec_schedule_claim cannot fire", file=sys.stderr)
    bt, ba = build_schedule_index(sched["rows"])
    ctx = {"takedowns": takedowns, "schedule_match": make_schedule_matcher(bt, ba), "claims": claims,
           "series_post_1972": series_post, "series_foreign": series_foreign, "gov_series": gov,
           "licence_evidence": lic_ev, "published_records": pub_rec, "film_renewals": film_ren,
           "today": datetime.date.today()}

    # The spine: attach RadioEchoes genre and episode facts; unmatched RE episodes are wants.
    wants = []
    for k, ss in re_by_key.items():
        for s in ss:
            for e in s.get("episodes") or []:
                dt = (e.get("date") or "").replace(".", "-")
                if not re.fullmatch(r"19\d\d-\d\d-\d\d", dt):
                    continue
                ep = episodes.get(f"{k}|{dt}")
                if ep:
                    ep.setdefault("spine", {"re_title": e["title"], "re_length": e.get("length"), "re_file": e["file"]})
                    stats["spine_matched"] += 1
                else:
                    wants.append((k, dt, e["title"], e.get("length")))

    db_path = os.path.join(ia.OUT, "radio-catalog.sqlite")
    tmp = db_path + ".tmp"
    if os.path.exists(tmp):
        os.remove(tmp)
    db = sqlite3.connect(tmp)
    db.executescript(open(os.path.join(os.path.dirname(__file__), "schema.sql")).read())
    state_count = collections.Counter()
    bucket_count = collections.Counter()
    for ep in episodes.values():
        recs = ep["recordings"]
        med = statistics.median([r["length_s"] for r in recs if r["length_s"]] or [0]) or None
        for r in recs:
            r["partial"] = bool(med and r["length_s"] and r["length_s"] < 0.6 * med)
        recs.sort(key=lambda r: (r["partial"], bool(r["variant"]), not r["otrr"], -(r["kbps"] or 0)))
        j = A.judge(ep, ctx)
        state_count[j["state"]] += 1
        bucket_count[j["rec_bucket"]] += 1
        bucket_count[j["work_bucket"]] += 1
        db.execute("INSERT INTO episodes VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (
            ep["id"], ep["series_key"], ep["date"], ep["date_source"], ep["num"], ep["title"], ep["aka"],
            ep["decade"], len(recs), med, any(r["transcript"] for r in recs),
            json.dumps(ep.get("spine")) if ep.get("spine") else None,
            j["state"], j["rec_bucket"], j["work_bucket"], json.dumps(j["evidence"], ensure_ascii=False)))
        for i, r in enumerate(recs):
            db.execute("INSERT INTO recordings VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (
                ep["id"], i, r["archive_id"], r["file"], r["url"], r["format"], r["source"], r["size"],
                r["length_s"], r["kbps"], r["md5"], r["variant"], r["partial"], r["transcript"]))
    for k, eps in by_series.items():
        ss = re_by_key.get(k) or []
        dates = sorted(e["date"] for e in eps if e["date"])
        db.execute("INSERT INTO series VALUES (?,?,?,?,?,?,?,?,?,?)", (
            k, known.get(k) or eps[0]["series_name"], ss[0]["genre"] if ss else None,
            dates[0] if dates else None, dates[-1] if dates else None, len(eps),
            k.startswith("librivox"), json.dumps(series_foreign.get(k)) if k in series_foreign else None,
            json.dumps(claims.get(k) or gov.get(k)) if (k in claims or k in gov) else None, bool(ss)))
    for it in items.values():
        db.execute("INSERT INTO items VALUES (?,?,?,?,?,?,?,?,?,?)", (
            it["id"], it["title"], json.dumps(it["collections"]), it["licenseurl"], it["uploader"],
            it["publicdate"], bool(it["is_dark"]), it["reviews"], it["avg_stars"], it["transcripts"]))
    db.executemany("INSERT INTO wants VALUES (?,?,?,?)", wants)
    db.execute("INSERT INTO meta VALUES (?,?)", ("built", datetime.datetime.now(datetime.timezone.utc).isoformat()))
    db.execute("INSERT INTO meta VALUES (?,?)", ("pd_published_year", str(A.pd_published_year())))
    db.commit()
    db.execute("VACUUM")
    db.close()
    os.replace(tmp, db_path)

    report = {"items": len(items), "episodes": len(episodes), "series": len(by_series),
              "states": dict(state_count), "buckets": dict(bucket_count), "wants": len(wants),
              "spine_series": len(re_series), "schedules_rows": len(sched["rows"]),
              "librivox_projects": len(lv), "stats": dict(stats), "seconds": round(time.time() - t0)}
    ia.write_json(os.path.join(ia.OUT, "build_report.json"), report)
    print(json.dumps({k: report[k] for k in ("items", "episodes", "series", "states", "wants")}, indent=1))
    # A build that judged nothing is a failed build (ENGINEERING-PROCESS §2).
    if not episodes:
        sys.exit(1)


if __name__ == "__main__":
    main()
