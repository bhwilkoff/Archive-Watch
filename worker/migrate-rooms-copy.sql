-- 2026-09-26 (Decision 143): a room carries the host's copy. schema-rooms.sql
-- creates the column on a NEW database; `CREATE TABLE IF NOT EXISTS` never
-- alters an existing one, so an existing database needs this once. Applied to
-- the live D1 on 2026-09-26. A second run fails with "duplicate column", which
-- is the harmless answer.
ALTER TABLE rooms ADD COLUMN copy TEXT;
