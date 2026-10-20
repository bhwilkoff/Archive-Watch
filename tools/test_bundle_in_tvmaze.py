#!/usr/bin/env python3
"""A whole series filed in one item and matched onto a TVmaze show becomes that
show's episodes, one per file (Decision 167).

Cases: FireballXL5.complete's numbering is production order, so a file is
placed by its TITLE ("08. Space Immigrants" is TVmaze's 1x03); a file with no
title is placed by its number and the season its item names; a second upload of
the same show adds nothing; a colorized upload never takes an episode from a
black-and-white one (Decision 158); an earlier expansion is replaced, not
doubled. Controls: an item that is one episode still maps by its SxE; a promo
shorter than four minutes is not an episode; a file that is a fragment of its
episode does not take it.
"""
import sys
from pathlib import Path
R = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(R / "tools"))
import build_bundle_series as B
import build_canonical_tv as T

MB = 200_000_000
ok = True


def check(name, cond):
    global ok
    ok &= bool(cond)
    print(f"  {'ok  ' if cond else 'FAIL'} {name}")


def entry(names, length="1500.5"):
    files = []
    for n in names:
        orig = n.rsplit(".", 1)[0] + ".avi"
        files.append({"name": orig, "format": "Cinepack", "source": "original", "size": MB})
        files.append({"name": n, "format": "h.264", "source": "derivative", "original": orig,
                      "size": MB, "length": length})
    return {"verdict": "bundle", "files": files}


canon = [{"season": 1, "number": n, "title": t, "overview": None, "stillURL": None,
          "airDate": "1962-10-28", "runtimeSeconds": 1500}
         for n, t in enumerate(["Planet 46", "The Doomed Planet", "Space Immigrants", "Plant Man from Space",
                                "Hypnotic Sphere"], 1)]

fxl5 = entry([f"Fireball XL5 - {n:02d}. {t}.mp4" for n, t in
              [(1, "Planet 46"), (2, "Hypnotic Sphere"), (5, "The Doomed Planet"),
               (6, "Plant Man From Space"), (8, "Space Immigrants")]])
B_CACHE = {"FireballXL5.complete": fxl5,
           "fxl5-colourized": entry([f"Fireball XL5 EP{n:02d}-{t} in Colour.mp4" for n, t in
                                     [(1, "Planet 46"), (3, "Planet of Plutonia"), (7, "Sun Temple")]]),
           "Room-222-Season-2": entry([f"Room 222 - {n:02d}.mp4" for n in range(1, 6)]),
           "show_promos": entry([f"Promo {n:02d} - {t}.mp4" for n, t in
                                 [(1, "Planet 46"), (2, "The Doomed Planet"), (3, "Space Immigrants")]],
                                length="31.0")}
T._BUNDLE_CACHE = B_CACHE

rows = B.tv_episodes("FireballXL5.complete", fxl5)
check("each file is an episode with its item's id and the item as source",
      len(rows) == 5 and rows[0]["archiveID"] == "FireballXL5.complete@e01"
      and all(r["sourceID"] == "FireballXL5.complete" for r in rows)
      and rows[0]["downloadURL"].endswith("/FireballXL5.complete/Fireball%20XL5%20-%2001.%20Planet%2046.mp4"))

whole = {"archiveID": "FireballXL5.complete", "title": "Fireball XL5.", "downloadURL": "x", "videoFile": {}}
single = {"archiveID": "FireballXL51x01", "title": "Fireball XL5 S01E01 Planet 46", "downloadURL": "y",
          "videoFile": {"name": "Fireball XL5 Ep-01 Planet 46.mp4"}}
eps, n = T.expand_bundles([single, whole])
check("the whole-series item is replaced by its files", n == 1 and len(eps) == 6
      and not any(e["archiveID"] == "FireballXL5.complete" for e in eps))
again, _ = T.expand_bundles(eps)
check("a second run replaces the earlier expansion instead of doubling it",
      sorted(e["archiveID"] for e in again) == sorted(e["archiveID"] for e in eps))

mapped, extras = T.map_items_to_canonical(eps, canon)
by = {k: it["archiveID"] for k, (c, it) in mapped.items()}
check("placed by title, not by the uploader's production number",
      by.get((1, 3)) == "FireballXL5.complete@e08" and by.get((1, 2)) == "FireballXL5.complete@e05"
      and by.get((1, 5)) == "FireballXL5.complete@e02")
check("control: an item that is one episode keeps its slot", by.get((1, 1)) == "FireballXL51x01")
check("a file whose episode another copy already plays adds nothing",
      "FireballXL5.complete@e01" not in [e["archiveID"] for e in extras] and len(extras) == 0)

col = T.expand_bundles([{"archiveID": "fxl5-colourized"}, whole])[0]
m2, x2 = T.map_items_to_canonical(col, canon)
by2 = {k: it["archiveID"] for k, (c, it) in m2.items()}
check("a colorized upload never takes an episode from the black-and-white one",
      by2.get((1, 1)) == "FireballXL5.complete@e01")
check("a colorized episode no other upload has is still offered",
      any(e["archiveID"] == "fxl5-colourized@e03" for e in x2)
      or any(it["archiveID"] == "fxl5-colourized@e03" for _, it in m2.values()))

r222 = B.tv_episodes("Room-222-Season-2", B_CACHE["Room-222-Season-2"])
check("a file with only a number takes the season its item names",
      r222[0]["seasonNumber"] == 2 and r222[0]["bundleTitle"] is None and r222[0]["episodeNumber"] == 1)
check("control: no season word, no season", B.item_season("FireballXL5.complete") is None
      and B.item_season("the-dick-van-dyke-show-the-complete-series-1961-1966") is None
      and B.item_season("thesmithfamilyseasontwo") == 2)

check("control: a promo is not an episode", B.tv_episodes("show_promos", B_CACHE["show_promos"]) is None)

frag = [dict(r, runtimeSeconds=300) for r in rows]
m3, _ = T.map_items_to_canonical(frag, canon)
check("control: a fragment of an episode does not take it", not m3)

# names seen in the trial rebuild of 2026-10-20
pris = [{"season": 1, "number": n, "title": t, "overview": None, "stillURL": None, "airDate": "1967-10-01",
         "runtimeSeconds": 3000} for n, t in enumerate(["Arrival", "The Chimes of Big Ben", "A. B. and C."], 1)]
row = lambda aid, t: {"archiveID": aid, "sourceID": aid.split("@")[0], "title": t, "bundleTitle": t,
                      "runtimeSeconds": 3000, "seasonNumber": 1, "episodeNumber": 9}
m4, _ = T.map_items_to_canonical([row("the-prisoner@s1e00", "Prisoner. Arrival"),
                                  row("the-prisoner@s1e02", "Prisoner. A B And C")], pris, "The Prisoner")
check("the show's own name in front of a title is not part of it",
      {k: it["archiveID"] for k, (c, it) in m4.items()} == {(1, 1): "the-prisoner@s1e00", (1, 3): "the-prisoner@s1e02"})
addams = [{"season": 2, "number": 22, "title": "Happy Birthday, Grandma Frump", "overview": None,
           "stillURL": None, "airDate": None, "runtimeSeconds": 1500},
          {"season": 1, "number": 17, "title": "Mother Lurch Visits the Addams Family", "overview": None,
           "stillURL": None, "airDate": None, "runtimeSeconds": 1500},
          {"season": 1, "number": 18, "title": "Mother Lurch Returns", "overview": None,
           "stillURL": None, "airDate": None, "runtimeSeconds": 1500}]
m5, x5 = T.map_items_to_canonical([row("a@s2e22", "Happy Birthday Gra"), row("a@s1e17", "Mother Lurch Visits"),
                                   row("a@s1e01", "Mother Lurch")], addams, "The Addams Family")
check("a file name cut short still finds its one episode", (2, 22) in m5 and (1, 17) in m5)
check("control: a prefix two episodes share places neither", len(m5) == 2 and len(x5) == 1)
old1x = {"archiveID": "FireballXL51x01", "title": "Fireball XL5 - 1x01 - Planet 46", "downloadURL": "y",
         "videoFile": {"name": "Fireball XL5 Ep-01 Planet 46.mp4"}}
m6, x6 = T.map_items_to_canonical(T.expand_bundles([old1x, whole])[0], canon, "Fireball XL5")
check("an item that is one episode takes its slot back from a file of a whole-series item",
      m6[(1, 1)][1]["archiveID"] == "FireballXL51x01" and not x6)

odd = entry([f"Fireball XL5 - {n:02d}. {t}.mp4" for n, t in [(1, "XL5 to H2O"), (2, "1875"), (3, "03")]])
odd_rows = {r["archiveID"]: r["bundleTitle"] for r in B.tv_episodes("odd", odd)}
check("a title with no word in it is still a title; a bare number is not",
      odd_rows.get("odd@e01") == "XL5 to H2O" and odd_rows.get("odd@e02") == "1875" and odd_rows.get("odd@e03") is None)

two = [{"season": s_, "number": n_, "title": f"Ep {s_}-{n_}", "overview": None, "stillURL": None,
        "airDate": None, "runtimeSeconds": 1500} for s_ in (1, 2) for n_ in range(1, 3)]
bare = {"archiveID": "sp@e03", "sourceID": "sp", "title": "Episode 3", "bundleTitle": None,
        "seasonNumber": None, "episodeNumber": 3, "runtimeSeconds": 1500}
m7, _ = T.map_items_to_canonical([bare], two)
check("a file that names no season counts the whole run", list(m7) == [(2, 1)])

T._BUNDLE_CACHE["im1958"] = entry([f"The Invisible Man {n:02d} - {t}.mp4" for n, t in
                                   enumerate(["Secret Experiment", "Crisis in the Desert", "Behind the Mask",
                                              "The Locked Room", "Picnic with Death"], 1)])
im75 = [{"season": 1, "number": n_, "title": t, "overview": None, "stillURL": None, "airDate": "1975-09-08",
         "runtimeSeconds": 3000} for n_, t in enumerate(["Pilot", "The Klae Dynasty", "Behind the Mask"], 1)]
show = {"id": 1, "name": "The Invisible Man", "premiered": "1975-09-08", "_embedded": {"episodes": [
    {"season": 1, "number": c["number"], "name": c["title"], "airdate": c["airDate"], "runtime": 50}
    for c in im75]}}
T.canonical_episodes = lambda sh: im75
pilot = {"archiveID": "im75pilot", "title": "The Invisible Man S01E01 Pilot",
         "downloadURL": "https://archive.org/download/im75pilot/p.mp4", "videoFile": {"name": "p.mp4"}}
sr, rw = T.rebuild_show(show, [pilot, {"archiveID": "im1958", "title": "The Invisible Man", "downloadURL":
                                       "https://archive.org/download/im1958/a.mp4", "videoFile": {"name": "a.mp4"}}],
                        repick=False)
eps7 = sorted(e["archiveID"] for se in sr["seasons"] for e in se["episodes"])
check("another show's upload stays one entry, not its episodes", eps7 == ["im1958", "im75pilot"]
      and rw.get("wrongShowBundles") == ["im1958"])
T.canonical_episodes = lambda sh: canon
sr2, rw2 = T.rebuild_show({"id": 2, "name": "Fireball XL5", "premiered": "1962-10-28"}, [whole], repick=False)
check("control: the right show's upload is expanded", sr2 and sr2["episodesCount"] == 5
      and not rw2.get("wrongShowBundles"))

T._BUNDLE_CACHE["fxl5-again"] = fxl5
sr3, rw3 = T.rebuild_show({"id": 2, "name": "Fireball XL5", "premiered": "1962-10-28"},
                          [whole, {"archiveID": "fxl5-again"}], repick=False)
check("control: a second upload of the same episodes is not another show",
      not rw3.get("wrongShowBundles") and sr3["episodesCount"] == 5)

tagged = entry([f"the avengers-s5e{n}-restored-720p-hd.mp4" for n in range(1, 5)])
check("words every file shares are a tag, not a title",
      all(r["bundleTitle"] is None and r["seasonNumber"] == 5 for r in B.tv_episodes("tagged", tagged)))

check("colorized is read from the id or title", B.is_colorized("the-twilight-zone-s-2-e-1-colorized-720p-hd")
      and B.is_colorized("fireball-xl5-colourized") and not B.is_colorized("FireballXL5.complete"))

print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
