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
  touched_ms   INTEGER NOT NULL
);
-- The sweep asks "what is stale", so that is what is indexed.
CREATE INDEX IF NOT EXISTS rooms_touched ON rooms (touched_ms);
