-- Watch Together rooms (SHAREPLAY §11). One row per live room, and no row
-- outlives the watching — see together.js for why that is the whole posture.
CREATE TABLE IF NOT EXISTS rooms (
  code         TEXT PRIMARY KEY,   -- four Crockford Base32 characters
  film_id      TEXT NOT NULL,
  position     REAL NOT NULL,      -- seconds into the film
  at_server_ms INTEGER NOT NULL,   -- the SERVER's clock when position was true
  rate         REAL NOT NULL DEFAULT 1,
  paused       INTEGER NOT NULL DEFAULT 0,
  generation   INTEGER NOT NULL DEFAULT 1,
  touched_ms   INTEGER NOT NULL,
  -- THE CODE IS PUBLIC; THIS IS NOT. A code is read aloud on a call, so it
  -- cannot also be the credential that drives the film — the lesson Tidbits
  -- Trivia states on its own screen ("the room code alone cannot drive the
  -- show"). Returned once at creation and never by a read.
  host_key     TEXT
);
-- The sweep asks "what is stale", so that is what is indexed.
CREATE INDEX IF NOT EXISTS rooms_touched ON rooms (touched_ms);

-- PRESENCE (owner, 2026-09-23: a host should see how many friends joined).
-- An anonymous token per joined device — random, made fresh for each join,
-- tied to nothing — and when it was last seen. Only the COUNT of recent
-- tokens is ever read out. Rows go when the room goes, and are swept with it.
CREATE TABLE IF NOT EXISTS room_presence (
  code     TEXT NOT NULL,
  token    TEXT NOT NULL,
  seen_ms  INTEGER NOT NULL,
  PRIMARY KEY (code, token)
);

-- THE DAILY TALLY (owner, 2026-09-25: "track how many rooms are being opened
-- ... anonymously within our privacy framework"). A date, what happened, a
-- count -- the counter's own grain, and deliberately LESS than the counter:
-- no film (the owner's choice), no code, no token, no host key. It is written
-- when a room is created and when a new guest token first arrives, and it
-- outlives the rooms because it describes none of them.
CREATE TABLE IF NOT EXISTS together_days (
  day    TEXT NOT NULL,    -- YYYY-MM-DD (UTC)
  kind   TEXT NOT NULL,    -- 'room' | 'guest'
  count  INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, kind)
);
