"""Episode identity from archive.org file names and ID3 album tags.

Copied from tools/probe_otr_corpus.py (MEASURED 2026-10-17: 14 families parse
93.8% of 16,544 sampled episode files, 80% to a full broadcast date). Every
pattern's example is a real file name; see docs/research/radio/07.
"""
import re


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
    if not (1920 <= y <= 1999 and 1 <= m <= 12 and 1 <= d <= 31):
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
_D = r"(?P<yyyy>19[2-9]\d)|(?P<yy>[2-9][\dx]|xx)"
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
    # "Rex Stout's Nero Wolfe 04 82-02-06 The Cop Killer" (number BEFORE the date)
    #   [04-rex-stouts-nero-wolfe-04-82-02-06-the-cop-killer, after the leading track is stripped]
    ("F1g_num_then_date", re.compile(
        rf"^(?P<series>[A-Za-z].*?)[ _-]+(?P<num>\d{{1,4}})[ _-]+{_DATE_DASH}[ _-]+(?P<title>.+)$")),
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


LEAD_TRACK = re.compile(r"^\d{1,3}[ ._-]+(?=[A-Za-z])")


def parse(name):
    s = LEAD_TRACK.sub("", stem(name))
    for fam, rx in PATTERNS:
        m = rx.match(s)
        if not m:
            continue
        g = m.groupdict()
        date, swapped = _date(g, fam)
        if swapped is None and fam in ("F0_otrr_v2", "F0b_camel_yymmdd_num", "F2_yymmdd",
                                       "F2b_series_yymmdd_title", "F1d_camel_glued",
                                       "F7_date_first", "F1e_series_date_title", "F1g_num_then_date"):
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


