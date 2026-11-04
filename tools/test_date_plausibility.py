#!/usr/bin/env python3
"""A stored year is evidence only until the item's own record names a later one
(Decision 179), and an audio upload is not a film. The cases are real items; the
controls are the ways this reading went wrong before. Run: python3 tools/test_date_plausibility.py
"""
import sys
from collections import Counter
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R


def it(aid, title, year, **kw):
    return {"archiveID": aid, "title": title, "year": year, **kw}


MOVE = [
    (it("AffairInMonteCarlo1954", "Monte Carlo", 1926, imdbID="tt0017166"), 1954),
    (it("BudSpencerTerenceHill1968AceHigh", "Ace High", 1918, imdbID="tt0008814"), 1968),
    (it("upenn-f16-0473_udaihur_jaijur_ambur_agra_1955", "Udaipur, Jaipur, Amber, Agra", 1920), 1955),
    (it("10-night-on-bald-mountain-1933-720p-blu-ray-dd-2.0-x-264-r-40", "Grotesqueries", 1907), 1933),
    (it("24304AirForceScrapBook1907to1957Vwr", "The Air Force Scrapbook", 1907), 1957),
    (it("33174keewaydincampfootage1928to1939mosvwr", "Keewaydin Canoe Camp", 1928), 1939),
    (it("0379_HM_Christmas_in_Vallejo_1930-1943_10_00_4", "Home Movies", 1930), 1943),
    (it("1953_Movie_Trailers_Coming", "Movie Trailers", 1930), 1953),
    (it("westfront-1918_1930", "Westfront", 1918), 1930),
    (it("Aristocr1940", "Aristocrats of Fashion", 1930), 1940),
    (it("010074-001", "1960s waves breaking at Bald Head", 1896), 1960),
    (it("x", "1940's Canadian National Railway", 1898), 1940),
    (it("19414-china", "China: Century of Revolution", 1927,
        synopsis="focuses on Chinese history 1800-1927. It was produced in 1967 by the prolific filmmaker David."), 1967),
    (it("ph-24864-vwr", "Inventions in America's Growth 1850-1910", 1910, synopsis="In this 1956 film by Coronet Instructional"), 1956),
    (it("90284-vwr", "50 Years Before Your Eyes", 1900, synopsis="This 1950 Warner Brothers film documents the half century"), 1950),
    (it("yn", "Yesterday's Newsreel", 1915, synopsis='one of the episodes of "Yesterday\'s Newsreels", an early 1950s TV show made from'), 1950),
    (it("30294", "The Ramparts We Watch", 1914, synopsis="This is a 1940’s era, black and white movie about"), 1940),
    (it("ew1", "The Heroic Days", 1902, synopsis="Shell Films produced this black-and-white film, “The Heroic Days,” in 1951."), 1951),
    (it("koko", "Mt. Vesuvius", 1926, synopsis="It likely dates to the 1930s."), 1930),
]
STAY = [
    it("koko-in-1999_1927", "Koko in 1999", 1927),                         # the year is the title
    it("2000_leagues_under_the_sea_ipod", "20,000 Leagues Under the Sea", 1916),
    it("space-1999-pilot", "Space: 1999", 1925),                           # Decision 169
    it("studio-one-1984", "Studio One 1984", 1925),
    it("hsj2023-17_kntv_ryden_agnes_moorehead", "KNTV interview", 1925),   # an accession number
    it("nosferatu-2000sdvd", "Nosferatu", 1922),                           # not date-shaped
    it("nosferatu-hd-restoration-2013-theatrical-trailer", "Nosferatu HD Restoration 2013", 1922),
    it("frankenstein-1910-1080p-hd-2017-restoration", "Frankenstein", 1910),
    it("metropolis-restored-2010", "Metropolis", 1927),
    it("TilliesPuncturedRomance1914--1939SoundRe-issue", "Tillie's Punctured Romance -- 1939 sound re-issue", 1914),
    it("cabiria-1913-1914-riedizione-2021-restored-remix", "Cabiria", 1914),
    it("img-1943", "My Old Kentucky Home", 1926),                          # a camera's file number
    it("macbeth_202004", "Macbeth", 1922),                                 # archive.org's own suffix
    it("pandoras-box_1930", "Pandora's Box", 1929),                        # a year apart: release against reissue
    it("miracle-of-the-wolves_1930", "Miracle of the Wolves", 1924, imdbID="tt0015141"),   # before the age line: no rights consequence
    it("she-1925-to-1968", "She", 1925, yearSource="agent-reviewed"),      # a person's year
    it("series:popeye-75th-anniversary-1960-1929", "Popeye 75th Anniversary - 1960", 1929),
    it("metropolis-1927", "Metropolis", 1927, imdbID="tt0017136", synopsis="This 1984 film is the Moroder version"),   # a match outranks an aside
    it("mt-tam", "Mt. Tamalpais Railway", 1898, synopsis="The film was compiled from paper prints in 1959"),
    it("restored", "A Film", 1920, synopsis="This film was made in 1920 and restored in 1998 at the archive"),
    it("rereleased", "A Film", 1914, synopsis="Re-released in 1939 with a sound track"),
    it("subject", "Maginot", 1925, synopsis="Footage shows the Maginot Line in 1939, and troops"),
    it("late", "A Film", 1935, synopsis="produced in 1967"),               # already past the age line: not this rule's
    it("court-martial-1955", "Court Martial", 1955),
]
AUDIO = [
    it("acidplanet-audio-01121693", "Othello", 1921, imdbID="tt0013469", collections=["acidplanet", "folksoundomy"], fileRuntimeSeconds=290),
    it("acidplanet-audio-01367455", "The Nameless", 1923, imdbID="tt0014303", collections=["acidplanet", "folksoundomy"]),
    it("DEEP_PURPLE_Speed_king_1970", "Speed King", 1923, imdbID="tt0166357", collections=["folksoundomy"], fileRuntimeSeconds=255),
    it("blma_20220120", "Blaze Away", 1922, imdbID="tt0418537", collections=["folksoundomy"], fileRuntimeSeconds=181),
    it("Sermon071314Rev1", "Camping Out", 1919, imdbID="tt0794267", collections=["audio_religion"], fileRuntimeSeconds=851),
]
FILM = [
    it("wings.-1927.720p.-blu-ray.x-264.-yify", "Wings", 1927, imdbID="tt0018578", collections=["folksoundomy"], fileRuntimeSeconds=8657),
    it("HaroldLloyd1919AskFather.DVDRip", "Ask Father", 1919, imdbID="tt0009887", collections=["folksoundomy"], fileRuntimeSeconds=815),
    it("a.-w.-o.-l.-1918-charles-r.-bowers", "A.W.O.L.", 1918, imdbID="tt0008811", collections=["opensource_audio"], fileRuntimeSeconds=325),
    it("dom-168217-lesvampires", "Les Vampires", 1915, collections=["audio_religion"], fileRuntimeSeconds=1863),
    it("danger_ahead_201907", "Danger Ahead", 1918, imdbID="tt0327618", collections=["folksoundomy"], fileRuntimeSeconds=3536),
    it("a-short-film", "A Short", 1920, imdbID="tt1", collections=["feature_films"], fileRuntimeSeconds=180),
]
bad = [f"{c['archiveID']}: {R.old_year_on_newer_upload(c)}, want {want}" for c, want in MOVE if R.old_year_on_newer_upload(c) != want]
bad += [f"{c['archiveID']} moved to {R.old_year_on_newer_upload(c)}" for c in STAY if R.old_year_on_newer_upload(c)]
bad += [f"audio not caught: {c['archiveID']}" for c in AUDIO if not R.audio_track(c)]
bad += [f"a film taken for audio: {c['archiveID']}" for c in FILM if R.audio_track(c)]

x = it("AffairInMonteCarlo1954", "Monte Carlo", 1926, imdbID="tt0017166", artworkSource="tmdb", posterURL="p",
       contentType="silent-film", isSilentFilm=True)
R.fix_old_year_on_newer_upload(x)
if not (x["year"] == 1954 and x["yearWas"] == 1926 and x["imdbID"] is None and not x["isSilentFilm"]
        and x["yearSource"] == "source_naming"):
    bad.append(f"apply: {x}")
items = [dict(AUDIO[0]), dict(FILM[0]), {**AUDIO[1], "excluded": True, "excludedReason": "trailer"}]
s = Counter()
R.exclude_audio_tracks(items, s)
if not (items[0].get("excludedReason") == "not_a_film" and not items[1].get("excluded")
        and items[2]["excludedReason"] == "trailer" and s["audio_track_excluded"] == 1):
    bad.append(f"exclude: {items}")
for b in bad:
    print("FAIL", b)
print(f"{'PASS' if not bad else 'FAIL'}: {len(MOVE)} moves, {len(STAY)} controls, {len(AUDIO)} audio, {len(FILM)} films")
sys.exit(1 if bad else 0)
