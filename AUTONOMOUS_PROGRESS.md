# Autonomous Loop — Database Health + App Stability

Started 2026-07-18. Owner directive:

> "significant work on both the database health (videos that don't play, issues
> with metadata having the wrong title/description/length/category) as well as
> multiple instances of the app not functioning as expected after a long period
> of not using the app (screens not refreshing, account not syncing) … Every
> video should have the exact right metadata and it should also play every
> single time (otherwise it should not be available on the app and should
> certainly not be highlighted on the home screen) … ship new app versions
> across all platforms at the end of the loop."

Two workstreams — **DATA** (catalog health) and **APP** (stability/performance)
— run on one alternating cadence, converging on a cross-platform release wave.

---

## Cadence

```
tick % 6  →  workstream
  0       →  DATA — playability verification (coverage + hard gate)
  1       →  APP  — cold-resume / refresh / sync defect (Apple: tvOS+iOS+macOS)
  2       →  DATA — metadata correctness (runtime, synopsis, contentType, title)
  3       →  APP  — same defect class, Android + web parity
  4       →  DATA — shelf-quality gate + measurement re-run
  5       →  OPT  — net-remove lines; re-measure both scorecards
```

Every **3rd cycle** (ticks 17, 35, 53 …) the opt tick becomes a **RELEASE WAVE**:
ship all five platforms if — and only if — the exit criteria below are met.

One tick = one commit = one push = one CI run. Never batch.

---

## Exit criteria (must ALL be green to ship a release wave)

### DATA
| Metric | Baseline 2026-07-18 | Gate |
|---|---|---|
| Shelf items ever playability-verified | 9,842 / 21,860 (45%) | **≥95%**, re-verified within 90d |
| Items on Home/hero/community shelves NOT verified-playable | unbounded | **0** |
| Shelf items missing runtime | 3,751 (17%) | **≤3%** |
| Items with implausible runtime (1–59s, non-commercial) | 930 | **≤100** |
| Catalog items with empty synopsis | 4,763 (15%) | **≤5%** on shelf items |
| Catalog items with stub synopsis (<80 chars) | 3,940 (12%) | **≤10%** on shelf items |
| contentType audited against real signals | never | **audit shipped + applied** |

### APP
- Every ranked cold-resume defect (below) fixed on every platform that has it.
- A resumed-after-days app observably re-checks the catalog, re-queries its
  views, and re-syncs the account — verified, not assumed.
- No regression in playback: stall diagnostics clean on a real title.

---

## Scorecard — live catalog (32,106 items, 21,860 on shelves)

Measured 2026-07-18 against the published `catalog.sqlite`.

- **Playability is the biggest hole.** Only **31%** of the catalog (9,899) has
  *ever* been liveness-checked, and **55% of shelf items have never been
  verified to play at all**. Nothing gates an unverified item off Home. This
  is exactly the failure the owner saw.
- 290 items carry **no `downloadURL`** (none currently on a shelf).
- **Runtime**: 5,408 items (17%) have none; 930 more claim <60s.
- **Synopsis**: 27% empty or stub.
- **Titles are clean** — only 168 suspicious (Decision 043's cleanup held).
- **contentType** skew worth auditing: `documentary` has 9 items,
  `trailer` 10 — near-dead categories; 1,511 `tv-special` is the known
  orphan-episode residue (Decisions 035/036).

---

## Backlog

Populated from the tick-0 audits. Items are pulled in cadence order; each
carries its per-platform state.

_(tick 0 audit results appended below as they land)_

---

## Tick log

### Tick 0 — 2026-07-18 — SETUP: charter + baseline
- **Context:** loop created. No prior autonomous state for these two workstreams.
- **Implementation:** this file — cadence, exit criteria, measured baseline
  against the live published DB.
- **Verification:** all numbers queried from the released `catalog.sqlite`
  (2026-07-18 16:56Z), not estimated. CI reviewed: all nightly catalog
  workflows green over the last 24h.
- **Next:** tick 1 pulls from the two audit punch lists — DATA side starts with
  playability verification coverage, since it is both the largest gap and the
  defect the owner actually hit.
