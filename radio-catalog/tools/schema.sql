-- The radio catalog. One row per broadcast (episodes), one per playable file
-- (recordings), keyed by series + air date. Every episode carries its rights
-- state and the evidence for it; clients play only keep_* states.
CREATE TABLE series (
  key TEXT PRIMARY KEY,          -- otr_parse.norm_series of the name
  name TEXT,                     -- RadioEchoes' name when the spine has it
  genre TEXT,                    -- RadioEchoes' human genre tag (OTR-Drama, ...)
  first_date TEXT, last_date TEXT,
  episodes INTEGER,
  is_librivox INTEGER,
  foreign_evidence TEXT,         -- JSON, when the series is judged non-US
  claim TEXT,                    -- JSON: editorial claim or government-work entry
  in_spine INTEGER
);
CREATE TABLE episodes (
  id TEXT PRIMARY KEY,           -- "<series>|<YYYY-MM-DD>" | "<series>|n<num>" | "<series>|t<title>" | "x:<item>/<file>"
  series_key TEXT,
  air_date TEXT, date_source TEXT,   -- filename | album_tag
  num INTEGER, title TEXT, aka TEXT, decade TEXT,
  recordings INTEGER,
  median_length_s REAL,
  has_transcript INTEGER,
  spine TEXT,                    -- JSON: the matching RadioEchoes episode
  state TEXT,                    -- keep_clean | keep_unclaimed | hide_claim | hide_unidentified
  rec_bucket TEXT, work_bucket TEXT,
  evidence TEXT                  -- JSON list, each with a source a reader can open
);
CREATE TABLE recordings (
  episode_id TEXT, rank INTEGER,   -- rank 0 is the default copy
  archive_id TEXT, file TEXT, url TEXT,
  format TEXT, source TEXT, size INTEGER, length_s REAL, kbps INTEGER, md5 TEXT,
  variant TEXT,                  -- AFRS | AFRTS | Audition | Rehearsal
  partial INTEGER,               -- under 60% of the episode's median length
  has_transcript INTEGER,
  PRIMARY KEY (episode_id, rank)
);
CREATE TABLE items (
  id TEXT PRIMARY KEY, title TEXT, collections TEXT, licenseurl TEXT, uploader TEXT,
  publicdate TEXT, is_dark INTEGER, reviews INTEGER, avg_stars REAL, transcripts INTEGER
);
CREATE TABLE wants (series_key TEXT, air_date TEXT, title TEXT, length TEXT);  -- spine episodes with no archive.org copy
CREATE TABLE meta (k TEXT PRIMARY KEY, v TEXT);
CREATE INDEX ep_series ON episodes(series_key, air_date);
CREATE INDEX ep_state ON episodes(state);
CREATE INDEX rec_item ON recordings(archive_id);
CREATE TABLE scripts (
  id TEXT PRIMARY KEY, source TEXT, series_key TEXT, air_date TEXT, title TEXT,
  url TEXT,                      -- the source's own page; clients link here
  text_cached INTEGER,           -- text held for search and matching only
  episode_id TEXT,               -- matched broadcast, on series + air date
  display TEXT                   -- full (clean episode) | link (everything else)
);
CREATE INDEX script_ep ON scripts(episode_id);
