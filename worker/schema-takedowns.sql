-- Removal requests (docs/TAKEDOWNS.md, Decision 175). The ONLY place a
-- requester's details exist: the repository is public and carries a case
-- number. sweepTakedowns blanks the personal columns three years after a case
-- closes; the row and its outcome stay, so a public case number still resolves.
CREATE TABLE IF NOT EXISTS takedown_cases (
  ref          TEXT PRIMARY KEY,   -- TD-XXXXXXXX, the only thing the repo sees
  created_ms   INTEGER NOT NULL,
  closed_ms    INTEGER,
  status       TEXT NOT NULL,      -- open | held | approved | removed | declined | closed
  kind         TEXT NOT NULL,      -- copyright | other
  complete     INTEGER NOT NULL,   -- every element of 17 U.S.C. 512(c)(3)
  source       TEXT NOT NULL,      -- form | email | google
  external_ref TEXT,               -- e.g. Google's reference id, Lumen notice
  links        TEXT NOT NULL,
  work         TEXT,               -- the work claimed, in the requester's words
  reason       TEXT,
  verdict      TEXT,               -- takedown_check's JSON: no personal data
  note         TEXT,
  name         TEXT,
  org          TEXT,
  email        TEXT,
  phone        TEXT,
  address      TEXT,
  signature    TEXT
);
CREATE INDEX IF NOT EXISTS takedown_status ON takedown_cases (status);
