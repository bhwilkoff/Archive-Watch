Close out a session (or a milestone) in SCRATCHPAD.md.

SCRATCHPAD.md is loaded into every session, so it holds only a true
Current State, the open owner items, and the TWO most recent session-log
entries. History lives in `docs/SESSION-LOG.md`, verbatim, newest first.

1. Invoke the `learning-orientation-design` skill — run the four-
   question test against what shipped. Report the assessment.
2. Write the new session-log entry at the TOP of the Session Log in
   SCRATCHPAD.md (state found → work done → verified vs merely built →
   state left; quote the owner's request where applicable).
3. MOVE the oldest entry now in SCRATCHPAD.md into the top of the
   Session Log in `docs/SESSION-LOG.md` — moved verbatim, never edited or
   summarized — so the scratchpad keeps exactly two.
4. Rewrite "Current State" and "Open owner items" wherever they are now
   wrong; do not append corrections underneath stale text. Ship state
   (what is LIVE where) belongs in Pulse / `ops/stores-manual.json`, not
   here.
5. Update `PARITY.md` if a user-facing feature shipped
   (`cross-platform-parity-discipline`).
6. If the work introduced any non-obvious technical decision, invoke
   `/decision`.
7. Confirm with one line: what was completed, what comes next, and that
   SCRATCHPAD.md is still under ~20 KB (`wc -c SCRATCHPAD.md`).
