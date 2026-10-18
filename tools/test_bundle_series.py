#!/usr/bin/env python3
"""An item whose files are a series becomes a spine; one film's pieces do not
(Decision 166).

Cases: the UFO naming (number after a shared name, the title after it), a
serial's "episodeN", SxxEyy in season folders, and that a token is the
episode's own number (adding a file moves nothing). Controls, each of which
must NOT be a series: a film in reels, a film in parts, a studio's shorts with
no numbers, files named by year, and an item with two copies of one episode.
"""
import sys
from pathlib import Path
R = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(R / "tools"))
import build_bundle_series as B

MB = 200_000_000
ok = True


def check(name, cond):
    global ok
    ok &= bool(cond)
    print(f"  {'ok  ' if cond else 'FAIL'} {name}")


def files(names, fmt="h.264", source="derivative"):
    out = []
    for n in names:
        orig = n.rsplit(".", 1)[0] + ".avi"
        out.append({"name": orig, "format": "Cinepack", "source": "original", "size": MB})
        out.append({"name": n, "format": fmt, "source": source, "original": orig,
                    "size": MB, "length": "3000.5"})
    return out


ufo = files([f"UFO.{i:02d}.{t}.mp4" for i, t in
             [(1, "Identified"), (2, "Exposed"), (3, "The Cat With Ten Lives"), (10, "The Square Triangle"),
              (4, "Conflict"), (5, "A Question of Priorities"), (6, "ESP"), (7, "Kill Straker"),
              (8, "Sub Smash"), (9, "Destruction")]])
rows, why = B.parse_bundle(ufo)
check("UFO naming is a series", rows is not None)
check("ordered by the number, not the size or the name",
      [r["episode"] for r in rows or []] == list(range(1, 11)))
check("the title is what follows the number", rows and rows[6]["title"] == "Kill Straker")
check("the token is the number", rows and B.token_of(rows[0]) == "e01")
check("one work per original: the .avi and .mp4 are one episode", len(rows or []) == 10)

serial = files([f"spy smasher-episode{i}-1942-colorized serial-720p-hd.mp4" for i in range(1, 13)])
rows, why = B.parse_bundle(serial)
check("a serial's episodeN is a series", rows is not None and len(rows) == 12)
check("chapter 10 sorts after chapter 9", rows and [r["episode"] for r in rows][8:10] == [9, 10])
check("the shared tail is not a title", rows and rows[0]["title"] is None)

it = {"archiveID": "spy-smasher-x", "title": "Spy Smasher - Complete Serial: 12 Episodes (1942)", "year": 1942}
spine = B.build_spine(it, rows, serial)
eps = spine["seasons"][0]["episodes"]
check("the series title drops 'Complete Serial'", spine["title"] == "Spy Smasher")
check("an untitled episode is named by the file's own word", eps[0]["title"] == "Episode 1")
check("ids are <item>@<token>, distinct", eps[0]["archiveID"] == "spy-smasher-x@e01"
      and len({e["archiveID"] for e in eps}) == 12)
check("every episode plays its own file", eps[4]["downloadURL"].endswith("episode5-1942-colorized%20serial-720p-hd.mp4"))
check("the spine names its source", spine["sourceID"] == "spy-smasher-x" and eps[0]["sourceID"] == "spy-smasher-x")
check("item_of recovers the item", B.item_of(eps[3]["archiveID"]) == "spy-smasher-x")

seasons = files([f"Season {s}/Show S{s:02d}E{e:02d}.mp4" for s in (1, 2) for e in (1, 2, 3)])
rows, why = B.parse_bundle(seasons)
check("SxxEyy across season folders", rows is not None and B.token_of(rows[-1]) == "s2e03")
rows, _ = B.parse_bundle(files([f"Beaver/Season 1/S01E{e:02d} - {t}.mp4" for e, t in
                                [(1, "Beaver Gets Spelled"), (2, "Captain Jack"), (3, "The Black Eye")]]))
check("no marker is left in a title read from S01E01 names", rows and rows[0]["title"] == "Beaver Gets Spelled")

more = files([f"UFO.{i:02d}.T{i}.mp4" for i in range(1, 6)] + ["UFO.06.T6.mp4"])
fewer = files([f"UFO.{i:02d}.T{i}.mp4" for i in range(1, 6)])
a = {B.token_of(r): r["root"] for r in B.parse_bundle(more)[0]}
b = {B.token_of(r): r["root"] for r in B.parse_bundle(fewer)[0]}
check("adding a file moves no other episode's id", all(a[k] == v for k, v in b.items()))

for label, names in [
    ("control: a film in reels", [f"Metropolis reel{i}.mp4" for i in range(1, 6)]),
    ("control: a studio's shorts, no numbers", ["Felix Saves the Day.mp4", "Feline Follies.mp4",
                                                "Felix in Hollywood.mp4", "Felix the Cat Trifles with Time.mp4"]),
    ("control: files named by year", ["Felix 1922.mp4", "Felix 1923.mp4", "Felix 1924.mp4", "Felix 1925.mp4"]),
    ("control: two copies of one episode", ["Show S01E01.mp4", "Show S01E01 alt.mp4", "Show S01E02.mp4",
                                            "Show S01E03.mp4"]),
]:
    rows, why = B.parse_bundle(files(names))
    check(f"{label} ({why})", rows is None)

for label, names in [
    ("control: a film as 1of5..5of5", [f"nosferatu-{i}of5.mpg" for i in range(1, 6)]),
    ("control: a DVD's title set", [f"VTS_01_{i}.mp4" for i in range(1, 5)]),
    ("control: numbered reels beside reel1", ["robeson02.mov", "robeson03.mov", "robeson04.mov", "robesonreel1.mov"]),
]:
    rows, why = B.parse_bundle(files(names))
    check(f"{label} ({why})", rows is None)

rows, why = B.parse_bundle(files([f"Les Vampires {i:02d}.ogv" for i in range(1, 11)], fmt="Ogg Video"))
check(f"control: episodes with no MP4 are not playable everywhere ({why})", rows is None)
rows, _ = B.parse_bundle(files([f"Show S01E{i:02d}.mp4" for i in range(1, 5)]))
check("archive.org's file title loses the number it repeats",
      B._own_title("E02 - Beaver's House Guest") == "Beaver's House Guest"
      and B._own_title("Chapter 1--Cornered By Redskins") == "Cornered By Redskins"
      and B._own_title("1. The Mystery of the Desert") == "The Mystery of the Desert"
      and B._own_title("A F&#00225;bula do Jeep") == "A Fábula do Jeep"
      and B._own_title("1984") == "1984")
rows, _ = B.parse_bundle(files([f"The.Last.Frontier.E{i:02d}.mp4" for i in range(1, 6)]))
check("E01 is an episode word", rows and all(r["named"] for r in rows))

film = {"archiveID": "fh", "title": "The Four Horsemen of the Apocalypse", "contentType": "silent-film"}
rows, _ = B.parse_bundle(files([f"fh{i}.mp4" for i in range(1, 6)]))
check("a feature's bare-numbered pieces have no evidence of a series", rows and B.series_evidence(film, rows) is None)
check("the same files typed television are a series",
      B.series_evidence(dict(film, contentType="tv-special"), rows) == "typed television")
rows, _ = B.parse_bundle(files([f"Red Circle {i:02d} {t}.mp4" for i, t in
                                enumerate(["The Monstrous Plot", "The Mysterious Friend", "The Executioner",
                                           "Sabotage", "The Ray of Death"], 1)]))
check("a title per episode is evidence", B.series_evidence({"contentType": "silent-film"}, rows) == "episode titles")
rows, _ = B.parse_bundle(files([f"Nosferatu Part {i}.mp4" for i in range(1, 5)]))
check("control: a film in parts is not a series", rows and B.series_evidence({"contentType": "silent-film"}, rows) is None)
rows, _ = B.parse_bundle(files([f"Insurrection Part {i} April {22 + i}th, 1916.mp4" for i in range(1, 9)]))
check("'Part N' is a series only when typed television",
      B.series_evidence({"contentType": "short-film"}, rows) is None
      and B.series_evidence({"contentType": "tv-special"}, rows) == "typed television")
rows, _ = B.parse_bundle(serial)
check("control: a de-emphasized item is never a series card",
      B.series_evidence({"collections": ["fringe", "deemphasize"]}, rows) is None
      and B.series_evidence({"noRecommend": True}, rows) is None
      and B.series_evidence({"contentType": "commercial"}, rows) is None
      and B.series_evidence({}, rows) == "episode names")

half1 = files([f"Chapter {i}--T{i}.mp4" for i in range(1, 6)])
half2 = files([f"Chapter {i}--T{i}.mp4" for i in range(6, 13)])
sp1 = B.build_spine({"archiveID": "bwbb1", "title": "Battling with Buffalo Bill", "year": 1931},
                    B.parse_bundle(half1)[0], half1)
sp2 = B.build_spine({"archiveID": "bwbb2", "title": "Battling with Buffalo Bill, Chapters 6-12", "year": 1931},
                    B.parse_bundle(half2)[0], half2)
check("'Chapters 6-12' is not part of the series title", sp2["seriesID"] == sp1["seriesID"])
m = B.merge_uploads([sp2, sp1])
eps = [e for s in m["seasons"] for e in s["episodes"]]
check("a serial uploaded in halves is one show, in order",
      m["episodesCount"] == 12 and [e["episodeNumber"] for e in eps] == list(range(1, 13))
      and eps[0]["archiveID"] == "bwbb1@e01" and eps[5]["archiveID"] == "bwbb2@e06"
      and m["sourceIDs"] == ["bwbb2", "bwbb1"])
dup = B.build_spine({"archiveID": "bwbb3", "title": "Battling with Buffalo Bill", "year": 1931},
                    B.parse_bundle(half1)[0], half1)
check("control: a second copy of the same chapters adds nothing",
      B.merge_uploads([sp1, dup])["episodesCount"] == 5 and "sourceIDs" not in B.merge_uploads([sp1, dup]))

print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
