"""Unit tests for the pure-logic parts of registry_pipeline."""
import sqlite3
import sys
sys.path.insert(0, ".")

from registry_pipeline import (
    normalize_title, compute_local_id, resolve_canonical_id,
    parse_year, parse_runtime_seconds, classify_work_type,
    classify_rights, score_source, SCHEMA,
    upsert_work, upsert_source, _merge_rights, _merge_json_list,
    compute_quality_score, compute_popularity_score, _log_normalize,
    _title_looks_like_junk, score_all_works,
)

# --- normalize_title -------------------------------------------------------

def test_normalization_collapses_variants():
    """Different spellings of the same title should normalize identically."""
    variants = [
        "The Kid",
        "THE KID",
        "the  kid",
        "Kid, The",
        "The Kid!",
        "The Kid (1921)",
    ]
    normalized = {normalize_title(v) for v in variants}
    assert normalized == {"kid"}, f"Expected {{'kid'}}, got {normalized}"
    print("✓ normalize_title collapses variants")

def test_normalization_handles_accents():
    assert normalize_title("Café Society") == "cafe society"
    print("✓ normalize_title strips diacritics")

def test_normalization_handles_non_english_articles():
    assert normalize_title("Le Voyage dans la Lune") == normalize_title("Voyage dans la Lune")
    print("✓ normalize_title drops non-English articles")

# --- compute_local_id ------------------------------------------------------

def test_local_id_is_deterministic():
    a = compute_local_id("The Kid", 1921, "Charlie Chaplin")
    b = compute_local_id("the kid", 1921, "charlie chaplin")
    c = compute_local_id("Kid, The", 1921, ["Charlie Chaplin"])
    assert a == b == c, f"Expected same ID, got {a}, {b}, {c}"
    assert a.startswith("lic:")
    print(f"✓ compute_local_id is deterministic: {a}")

def test_local_id_distinguishes_different_works():
    a = compute_local_id("The Kid", 1921, "Charlie Chaplin")
    b = compute_local_id("The Kid Brother", 1927, "Harold Lloyd")
    assert a != b
    print("✓ compute_local_id distinguishes works")

# --- resolve_canonical_id --------------------------------------------------

def test_canonical_id_priority():
    # Wikidata wins
    assert resolve_canonical_id(wikidata_qid="Q123", imdb_id="tt456", title="X") == "wd:Q123"
    # IMDb next
    assert resolve_canonical_id(imdb_id="tt456", title="X") == "imdb:tt456"
    assert resolve_canonical_id(imdb_id="456", title="X") == "imdb:tt456"  # auto-prefix
    # Fallback
    r = resolve_canonical_id(title="Unknown", year=2020, creator="X")
    assert r.startswith("lic:")
    print("✓ resolve_canonical_id priority works")

# --- parse_year / parse_runtime -------------------------------------------

def test_parse_year():
    assert parse_year("1921") == 1921
    assert parse_year("1921-05-23") == 1921
    assert parse_year(None, "c. 1915") == 1915
    assert parse_year("MCMXXI") is None  # Roman numerals not parsed
    assert parse_year(["1921", "bogus"]) == 1921
    print("✓ parse_year handles various formats")

def test_parse_runtime():
    assert parse_runtime_seconds("1:23:45") == 1*3600 + 23*60 + 45
    assert parse_runtime_seconds("5:00") == 300
    assert parse_runtime_seconds("85 min") == 85 * 60
    assert parse_runtime_seconds("85 minutes") == 85 * 60
    assert parse_runtime_seconds("5100") == 5100  # big number = seconds
    assert parse_runtime_seconds("45") == 45 * 60  # small number = minutes
    print("✓ parse_runtime_seconds handles various formats")

# --- classification --------------------------------------------------------

def test_classify_work_type():
    assert classify_work_type(["feature_films"], [], None, "Some Film") == "feature_film"
    assert classify_work_type(["classic_cartoons"], [], None, "Cartoon") == "animated_short"
    # 3000 sec = 50 min, which is > 40 min, so feature_film
    assert classify_work_type([], [], 3000, "x") == "feature_film"
    assert classify_work_type([], [], 600, "x") == "short_film"
    assert classify_work_type([], [], None, "Nosferatu Trailer") == "trailer"
    assert classify_work_type([], ["documentary"], None, "x") == "documentary"
    print("✓ classify_work_type routes correctly")

def test_classify_rights():
    assert classify_rights("https://creativecommons.org/publicdomain/mark/1.0/", "archive_org") == "public_domain"
    assert classify_rights("https://creativecommons.org/licenses/by/4.0/", "archive_org") == "creative_commons"
    assert classify_rights(None, "archive_org") == "unknown"
    print("✓ classify_rights reads license URLs")

# --- scoring ---------------------------------------------------------------

def test_score_source_ordering():
    # LoC MP4 downloadable should beat AVI archive.org
    loc_mp4 = score_source("loc", "mp4", True, 500_000_000)
    ia_avi  = score_source("archive_org", "avi", True, 700_000_000)
    assert loc_mp4 > ia_avi, f"loc_mp4={loc_mp4}, ia_avi={ia_avi}"
    # h.264 beats raw AVI within archive.org
    ia_h264 = score_source("archive_org", "h.264", True, 500_000_000)
    ia_avi  = score_source("archive_org", "avi",    True, 500_000_000)
    assert ia_h264 > ia_avi
    print(f"✓ score_source orders correctly (loc_mp4={loc_mp4}, ia_avi={ia_avi}, ia_h264={ia_h264})")

# --- merge helpers ---------------------------------------------------------

def test_merge_rights():
    assert _merge_rights("unknown", "public_domain") == "public_domain"
    assert _merge_rights("public_domain", "unknown") == "public_domain"
    assert _merge_rights("creative_commons", "rights_reserved_free_stream") == "creative_commons"
    print("✓ _merge_rights keeps the more-permissive status")

def test_merge_json_list():
    merged = _merge_json_list('["a", "b"]', ["b", "c"])
    import json
    assert json.loads(merged) == ["a", "b", "c"]
    print("✓ _merge_json_list deduplicates and preserves order")

# --- end-to-end merging logic with a real SQLite DB ------------------------

def test_federation_merges_duplicate_works():
    """The core federation test: same work from two sources merges into one work."""
    conn = sqlite3.connect(":memory:")
    conn.executescript(SCHEMA)

    # Simulate ingesting "The Kid (1921)" from archive.org
    cid1 = compute_local_id("The Kid", 1921, "Charlie Chaplin")
    upsert_work(conn, canonical_id=cid1, id_scheme="local",
                title="The Kid", year=1921, runtime_sec=4080,
                work_type="feature_film", rights_status="public_domain",
                description="Chaplin's first feature.",
                languages=["eng"], subjects=["comedy"])
    upsert_source(conn, canonical_id=cid1, source_type="archive_org",
                  source_id="TheKid1921", source_url="https://archive.org/details/TheKid1921",
                  stream_url="https://archive.org/download/TheKid1921",
                  format_hint="mpeg4", file_size=700_000_000,
                  downloadable=True, raw_json="{}")

    # Now simulate ingesting the same film from LoC with a different title form
    cid2 = compute_local_id("THE KID", 1921, "Charles Chaplin")  # slightly different creator
    # Different creator spelling produces a DIFFERENT ID. That's expected —
    # this is where the Wikidata promotion pass resolves things. But let's
    # verify the same creator-name merges:
    cid3 = compute_local_id("Kid, The", 1921, "Charlie Chaplin")
    assert cid1 == cid3, "Same film with different title form should collide"

    upsert_work(conn, canonical_id=cid3, id_scheme="local",
                title="Kid, The", year=1921, runtime_sec=None,
                work_type="feature_film", rights_status="public_domain",
                description=None,
                languages=["eng"], subjects=["silent film"])
    upsert_source(conn, canonical_id=cid3, source_type="loc",
                  source_id="loc_thekid", source_url="https://loc.gov/item/thekid/",
                  stream_url="https://loc.gov/files/thekid.mp4",
                  format_hint="mp4", file_size=None,
                  downloadable=True, raw_json="{}")

    # Now we should have ONE work with TWO sources
    works = conn.execute("SELECT COUNT(*) FROM works").fetchone()[0]
    sources = conn.execute("SELECT COUNT(*) FROM sources WHERE canonical_id=?", (cid1,)).fetchone()[0]
    assert works == 1, f"Expected 1 work, got {works}"
    assert sources == 2, f"Expected 2 sources, got {sources}"

    # And the best-source view should pick LoC (higher score)
    row = conn.execute(
        "SELECT best_source_type, source_count FROM works_with_best_source WHERE canonical_id=?",
        (cid1,),
    ).fetchone()
    assert row[0] == "loc", f"Expected best_source=loc, got {row[0]}"
    assert row[1] == 2

    # Subjects should have merged, not overwritten
    subjects = conn.execute("SELECT subjects FROM works WHERE canonical_id=?", (cid1,)).fetchone()[0]
    import json
    assert set(json.loads(subjects)) == {"comedy", "silent film"}

    print("✓ federation merges duplicate works (1 work, 2 sources, best=LoC, merged subjects)")

# --- quality score --------------------------------------------------------

def test_junk_title_detection():
    assert _title_looks_like_junk("IMG_1234")
    assert _title_looks_like_junk("DSC00123")
    assert _title_looks_like_junk("untitled")
    assert _title_looks_like_junk("Untitled")
    assert _title_looks_like_junk("test")
    assert _title_looks_like_junk("video 3")
    assert _title_looks_like_junk("")
    assert _title_looks_like_junk(None)
    assert _title_looks_like_junk("ABCDEF12345")
    # Real titles should pass
    assert not _title_looks_like_junk("The Kid")
    assert not _title_looks_like_junk("Plan 9 from Outer Space")
    assert not _title_looks_like_junk("Nosferatu")
    print("✓ _title_looks_like_junk catches junk, accepts real titles")

def test_quality_score_real_feature_film():
    """A real feature film with full metadata should score high."""
    q = compute_quality_score(
        title="The Kid", runtime_sec=4080,  # 68 min
        file_size=700_000_000, description="A" * 400,
        work_type="feature_film", rights_status="public_domain",
        has_year=True,
    )
    assert q >= 70, f"Expected high quality score, got {q}"
    print(f"✓ real feature film scores high (q={q})")

def test_quality_score_junk_item():
    """A 15-second clip named IMG_1234 with no metadata should score low."""
    q = compute_quality_score(
        title="IMG_1234", runtime_sec=15,
        file_size=1_000_000, description=None,
        work_type="unknown", rights_status="unknown",
        has_year=False,
    )
    assert q < 40, f"Expected low quality score, got {q}"
    print(f"✓ junk item scores low (q={q})")

def test_quality_score_ordering():
    """Better items should score higher than worse items."""
    good = compute_quality_score(
        title="Night of the Living Dead", runtime_sec=5700,
        file_size=800_000_000, description="George Romero's 1968 horror classic. " * 5,
        work_type="feature_film", rights_status="public_domain", has_year=True,
    )
    medium = compute_quality_score(
        title="Home Movie 1974", runtime_sec=600,
        file_size=50_000_000, description=None,
        work_type="home_movie", rights_status="unknown", has_year=True,
    )
    junk = compute_quality_score(
        title="test", runtime_sec=10, file_size=500_000, description=None,
        work_type="unknown", rights_status="unknown", has_year=False,
    )
    assert good > medium > junk, f"Expected good({good}) > medium({medium}) > junk({junk})"
    print(f"✓ quality score orders correctly (good={good}, medium={medium}, junk={junk})")

# --- log normalization ----------------------------------------------------

def test_log_normalize_compresses_long_tail():
    """300k downloads should map to a bounded value, not dominate the score."""
    assert _log_normalize(0) == 0
    assert _log_normalize(None) == 0
    low = _log_normalize(10, scale=3.5)
    med = _log_normalize(1_000, scale=3.5)
    high = _log_normalize(300_000, scale=3.5)
    assert low < med < high
    # The key property: even 300k downloads doesn't blow past scale*6 = 21
    assert high <= 3.5 * 6, f"log-norm should cap, got {high}"
    # And med should be well inside that bound
    assert med < high
    print(f"✓ _log_normalize compresses long tail (10→{low:.1f}, 1k→{med:.1f}, 300k→{high:.1f})")

# --- popularity score -----------------------------------------------------

def test_popularity_famous_film_beats_obscure():
    """A Wikipedia-known film with high downloads should beat an obscure one."""
    famous = compute_popularity_score(
        downloads=300_000, num_favorites=1_500,
        avg_rating=4.5, num_reviews=200,
        work_type="feature_film", year=1922,
        wikipedia_article_count=25,  # Nosferatu-level
        has_poster=True, has_imdb=True, has_director=True, has_cast=True,
        source_count=3,
    )
    obscure = compute_popularity_score(
        downloads=20, num_favorites=0,
        avg_rating=None, num_reviews=0,
        work_type="home_movie", year=2008,
        wikipedia_article_count=0,
        has_poster=False, has_imdb=False, has_director=False, has_cast=False,
        source_count=1,
    )
    assert famous > obscure + 40, f"famous={famous}, obscure={obscure}"
    assert famous >= 80, f"famous should score very high, got {famous}"
    assert obscure <= 15, f"obscure should score very low, got {obscure}"
    print(f"✓ popularity: famous ({famous}) >> obscure ({obscure})")

def test_popularity_wikipedia_presence_matters():
    """Even without engagement data, Wikipedia presence should lift a score."""
    with_wiki = compute_popularity_score(
        work_type="feature_film", year=1950,
        wikipedia_article_count=5, has_poster=True, has_imdb=True,
        source_count=1,
    )
    without_wiki = compute_popularity_score(
        work_type="feature_film", year=1950,
        wikipedia_article_count=0,
        source_count=1,
    )
    assert with_wiki > without_wiki + 15
    print(f"✓ Wikipedia presence lifts popularity ({without_wiki} → {with_wiki})")

def test_popularity_early_film_survival_bonus():
    """A 1920s film that's still around deserves a small bonus."""
    early = compute_popularity_score(
        work_type="feature_film", year=1925, source_count=1,
    )
    modern = compute_popularity_score(
        work_type="feature_film", year=2015, source_count=1,
    )
    assert early > modern, f"early={early}, modern={modern}"
    print(f"✓ pre-1940 survival bonus applied (1925→{early}, 2015→{modern})")

def test_popularity_multi_source_bonus():
    """Having copies at multiple archives means the film matters."""
    three = compute_popularity_score(
        work_type="feature_film", year=1950, source_count=3,
    )
    one = compute_popularity_score(
        work_type="feature_film", year=1950, source_count=1,
    )
    assert three > one
    print(f"✓ multi-source bonus applied (1 src→{one}, 3 srcs→{three})")

def test_popularity_download_saturation():
    """A ratings-only boost shouldn't match a mega-hit with 300k downloads.
    But more importantly: 1M downloads shouldn't be 10x better than 100k."""
    hundred_k = compute_popularity_score(
        downloads=100_000, work_type="feature_film", year=1950, source_count=1,
    )
    one_m = compute_popularity_score(
        downloads=1_000_000, work_type="feature_film", year=1950, source_count=1,
    )
    # Log-normalized, so the delta should be small (log10(10)=1 unit * scale)
    assert 0 < (one_m - hundred_k) < 10
    print(f"✓ download count saturates (100k→{hundred_k}, 1M→{one_m})")

# --- end-to-end scoring pass ----------------------------------------------

def test_score_all_works_end_to_end():
    """Full scoring pass against a real DB with mixed-quality data."""
    conn = sqlite3.connect(":memory:")
    conn.executescript(SCHEMA)

    # A real film: well-known, Wikipedia-ed, high IA engagement
    good_id = compute_local_id("Night of the Living Dead", 1968, "George Romero")
    upsert_work(conn, canonical_id=good_id, id_scheme="local",
                title="Night of the Living Dead", year=1968, runtime_sec=5700,
                work_type="feature_film", rights_status="public_domain",
                description="George Romero's genre-defining zombie horror film. " * 4,
                languages=["eng"], subjects=["horror"])
    upsert_source(conn, canonical_id=good_id, source_type="archive_org",
                  source_id="night_of_the_living_dead", source_url="https://archive.org/details/night_of_the_living_dead",
                  stream_url=None, format_hint="h.264", file_size=800_000_000,
                  downloadable=True, raw_json="{}")
    # IA engagement
    conn.execute("""INSERT INTO engagement
        (source_type, source_id, downloads, num_favorites, num_reviews, avg_rating)
        VALUES ('archive_org', 'night_of_the_living_dead', 250000, 1200, 150, 4.4)""")
    # Enrichment — has everything
    conn.execute("""INSERT INTO enrichment
        (canonical_id, wikidata_qid, imdb_id, wikipedia_url, directors, cast_list,
         genres, countries, poster_url)
        VALUES (?, 'Q189577', 'tt0063350', 'https://en.wikipedia.org/wiki/Night_of_the_Living_Dead',
                '["George A. Romero"]', '["Duane Jones", "Judith O''Dea"]',
                '["horror"]', '["USA"]', 'https://example.com/poster.jpg')""",
        (good_id,))

    # A junky home movie: no metadata, short, small file, no engagement
    junk_id = compute_local_id("IMG_0042", 2009, "upload")
    upsert_work(conn, canonical_id=junk_id, id_scheme="local",
                title="IMG_0042", year=2009, runtime_sec=22,
                work_type="unknown", rights_status="unknown",
                description=None, languages=[], subjects=[])
    upsert_source(conn, canonical_id=junk_id, source_type="archive_org",
                  source_id="img_0042_user_upload", source_url="https://archive.org/details/img_0042_user_upload",
                  stream_url=None, format_hint="mp4", file_size=2_000_000,
                  downloadable=True, raw_json="{}")

    # A middling item: reasonable film, no Wikipedia, moderate engagement
    mid_id = compute_local_id("Industrial Training Film", 1952, "Jam Handy")
    upsert_work(conn, canonical_id=mid_id, id_scheme="local",
                title="Industrial Training Film", year=1952, runtime_sec=1800,
                work_type="industrial_film", rights_status="public_domain",
                description="Employee training film from Jam Handy Organization.",
                languages=["eng"], subjects=[])
    upsert_source(conn, canonical_id=mid_id, source_type="archive_org",
                  source_id="jam_handy_1952_training", source_url="https://archive.org/details/jam_handy_1952_training",
                  stream_url=None, format_hint="mpeg4", file_size=150_000_000,
                  downloadable=True, raw_json="{}")
    conn.execute("""INSERT INTO engagement
        (source_type, source_id, downloads, num_favorites, num_reviews, avg_rating)
        VALUES ('archive_org', 'jam_handy_1952_training', 800, 5, 2, 3.5)""")

    # Run the scoring pass
    updated = score_all_works(conn)
    assert updated == 3, f"Expected 3 works scored, got {updated}"

    # Check results
    rows = {}
    for cid in (good_id, junk_id, mid_id):
        row = conn.execute(
            "SELECT quality_score, popularity_score FROM works WHERE canonical_id = ?",
            (cid,),
        ).fetchone()
        rows[cid] = row

    good_q, good_p = rows[good_id]
    junk_q, junk_p = rows[junk_id]
    mid_q,  mid_p  = rows[mid_id]

    # Quality ordering
    assert good_q > mid_q > junk_q, f"quality: good={good_q}, mid={mid_q}, junk={junk_q}"
    # Popularity ordering
    assert good_p > mid_p > junk_p, f"popularity: good={good_p}, mid={mid_p}, junk={junk_p}"
    # Absolute thresholds: good should be in the default view, junk shouldn't
    assert good_q >= 40 and good_p >= 25, f"good should pass default cutoffs: q={good_q}, p={good_p}"
    assert junk_q < 40, f"junk should fail quality cutoff: q={junk_q}"

    # The default view should contain good, exclude junk, and
    # borderline-include mid depending on scores
    default_rows = conn.execute(
        "SELECT canonical_id FROM works_default"
    ).fetchall()
    default_ids = {r[0] for r in default_rows}
    assert good_id in default_ids, "good film should be in default view"
    assert junk_id not in default_ids, "junk should be filtered out"

    print(f"✓ score_all_works end-to-end: good=(q={good_q}, p={good_p}), "
          f"mid=(q={mid_q}, p={mid_p}), junk=(q={junk_q}, p={junk_p})")
    print(f"  default view: {len(default_ids)} works (junk filtered, good kept)")

# --- run all ---------------------------------------------------------------

if __name__ == "__main__":
    test_normalization_collapses_variants()
    test_normalization_handles_accents()
    test_normalization_handles_non_english_articles()
    test_local_id_is_deterministic()
    test_local_id_distinguishes_different_works()
    test_canonical_id_priority()
    test_parse_year()
    test_parse_runtime()
    test_classify_work_type()
    test_classify_rights()
    test_score_source_ordering()
    test_merge_rights()
    test_merge_json_list()
    test_federation_merges_duplicate_works()
    # Scoring tests
    test_junk_title_detection()
    test_quality_score_real_feature_film()
    test_quality_score_junk_item()
    test_quality_score_ordering()
    test_log_normalize_compresses_long_tail()
    test_popularity_famous_film_beats_obscure()
    test_popularity_wikipedia_presence_matters()
    test_popularity_early_film_survival_bonus()
    test_popularity_multi_source_bonus()
    test_popularity_download_saturation()
    test_score_all_works_end_to_end()
    print("\n  All tests passed ✓")
