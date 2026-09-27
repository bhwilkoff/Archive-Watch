-- The feeds and assistant tally (worker/src/tally.js): a date, a kind, a
-- count. Nothing about who asked or what they watched.
CREATE TABLE IF NOT EXISTS feeds_days (
  day    TEXT NOT NULL,    -- YYYY-MM-DD (UTC)
  kind   TEXT NOT NULL,    -- 'signin' | 'play' | 'channel' | 'mcp'
  count  INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, kind)
);
