# Project Scratchpad — Archive Watch

> **How this file works.** It is loaded into every session, so it stays
> small: a true Current State, the open owner decisions, and the two most
> recent session-log entries. When you add a session-log entry, MOVE the
> oldest one here into `docs/SESSION-LOG.md` (verbatim, newest first).
> Rewrite Current State when it is wrong rather than appending to it.
> Ship state (what is LIVE where) is read from Pulse, not from this file —
> a number written here rots; `ops/pulse.json` is refreshed daily.

## Current State (rewritten 2026-09-14)

**Archive Watch is live on every platform it targets.** One catalog, one
data plane (Decisions 017/018/028), five native fronts plus the web:

| Platform | Where | Ship route |
|---|---|---|
| tvOS / iOS / iPadOS / macOS | one universal Xcode project (`ArchiveWatch/ArchiveWatch.xcodeproj`), App Store record `app.archivewatch.tvos` | `appstore-build.yml` → `appstore-submit.yml` (fully API-driven, Decision 101). Repo is at **1.42.118 (1130)** — `AppVersion.xcconfig` is the ONE version number; bump both on every commit |
| Android phone + Google TV | `android/`, package `com.archivewatch.app`, Play | `play-release.yml` builds; `tools/play_promote.py` promotes the SAME artifact (Decision 110). Repo versionCode 60 |
| Fire TV | `amazon` flavor of the Android app (minSdk 23, Decision 100/115) | `tools/submit-amazon.py` over the Amazon Submission API (Decision 111/115) |
| Roku | `roku/`, channel 881015 | `tools/roku_package.py` + Dashboard; signing key must NEVER be regenerated. Search feed at `archivewatch.org/roku-search/` (Decision 113/117) |
| Web PWA | `archivewatch.org` (viewer at `/`, curator at `/curate/`, Pulse at `/pulse/`) | GitHub Pages via `deploy-pages.yml` |
| webOS / Tizen | packages build from the same web root | **NOT SUBMITTED** — owner steps (LG Seller Lounge; Samsung Public Seller is US-only, cert backed up, Decision 112) |

**The catalog** (~26–27k visible items after the rights audit, Decision
027/114) is built and enriched entirely in GitHub Actions — ~38 scheduled
workflows audited daily by `workflow-health.yml`; their discipline is
Decisions 057/066/089/093/094/107. `catalog.json` + `catalog.sqlite` live
on a GitHub Release, never in git.

**Reading how it is doing**: <https://archivewatch.org/pulse/> — seven
audience views, every store read by the route it actually offers, refreshed
daily 07:17 MT (Decisions 108/109/123, `docs/PULSE-ANALYTICS.md`). The
social programme posts daily to five platforms (`docs/SOCIAL-PROGRAM.md`,
Decision 120).

**Where the rules live** (read before changing the thing they govern):
`docs/ENGINEERING-PROCESS.md` (the ten disciplines) · `PARITY.md` (what
ships where) · per-platform binding design docs `docs/tvOS-DESIGN.md`,
`docs/iOS-DESIGN.md`, `docs/IPAD-DESIGN.md`, `docs/macOS-DESIGN.md`,
`docs/ANDROID-DESIGN.md`, `docs/TV-DESIGN.md`, `docs/ROKU-DESIGN.md`,
`docs/WEB-DESIGN.md` · `docs/DEVICE-TESTING.md` (real hardware only, never
emulators) · `docs/CAPTIONS.md` · `docs/SHAREPLAY.md` ·
`docs/PLAYLIST-SHARING.md` · `docs/CATALOG-CONTRACT.md`.

### Open owner items (nothing else is blocked)

1. **Roku 1.0.65** was scheduled to go live 2026-09-14 5:00 PM PT. Pulse
   detects it (App Health crash logs carry an `App Version`); confirm and
   update `ops/stores-manual.json`.
2. **Roku Search feed** is registered and validates 100%, but publishing to
   end users — and clearing 53 phantom per-asset errors — is a Partner
   Success request (Decision 117).
3. **Content decisions reserved for the owner** (Decision 027 reserves
   hides of this kind): the television rights audit (below); the
   1,000–5,000-vote band of 1964–77 films (Hammer, Carry On, Gamera, gialli
   — Decision 114); the 313 visible `safe_pd_age` items whose archive id
   contradicts their pre-1930 year (Decision 113, fifth amendment).
4. **`editors-picks` never appears on Home** — 5 eligible items against
   `minPerShelf = 9`; needs more picks in `featured.json` (editorial, not
   code).
5. LG and Samsung store submissions (accounts + a device to test on).

---

## OPEN — OWNER DECISION: television has never passed the rights audit

Found 2026-09-06 from the owner's question "2 Stupid Dogs is a show from the
1990s, so how is it public domain?" It is not. The gates are working — on
FILMS. Television was built on a parallel path that never had them.

**Why.** `audit_rights.py` (Decision 027) runs over `catalog.json`. Episodes
are NOT catalog items: they live only in `series/*.json`, put there by
`backfill_tv_episodes.py`, which searches archive.org by show title and
applies no rights test of any kind. So **all 4,702 episodes across all 489
spines have never been seen by the rights audit.** `2-stupid-dogs-season-1`
is not in `catalog.json` at all — a 2024 user upload of a 1993 Hanna-Barbera
show, no `licenseurl`, no `rights` statement.

**Scope, measured.** 202 of the 489 spines have `yearStart >= 1978`, carrying
1,949 episodes. Fed through the FILM audit's own `bucket()`, all 202 come out
`modern_copyright_unconfirmed` — the audit wants a licence check before
hiding, by design (it never hides on a failed fetch). A 24-show sample of
that confirm step: **23 have no licence at all**; one (The Man from Snowy
River, 1994) carries a genuine CC public-domain dedication and would be
correctly rescued. Names in the hide set include Murphy Brown, Knight Rider,
The Dukes of Hazzard, Freddy's Nightmares, Designing Women, Minder, Count
Duckula, Honey I Shrunk the Kids, and a 2025 documentary.

**The fix is understood but NOT applied**, because hiding ~194 shows and
~1,870 episodes is a content decision of the same kind Decision 027 reserved
for the owner (who set the 1964-77 keep and the 1995 commercials cutoff):
  1. run `audit_rights`'s confirm pass over the spine items,
  2. carry `excluded` into the spine build so a hidden item cannot be served,
  3. gate `backfill_tv_episodes` at ingest so this cannot refill.
Step 2 matters on its own: `gather_raw_targets` re-pools existing spine files
with NO `excluded` check, so even once an item IS judged, the spine would
keep serving it.

---

## Session Log

Older entries: `docs/SESSION-LOG.md` (verbatim, back to 2026-04-17).

### 2026-09-14 (later) — Context put in order: 382 KB of always-loaded docs → ~80 KB
Owner: *"Let's get our context and documentation in order so that it isn't
costing us on tokens every time we try to do something."* Measured first:
every session was loading ~382 KB (~95k tokens) before the first prompt —
SCRATCHPAD.md 192 KB (a session log back to April, imported whole),
DECISIONS.md 158 KB (past Decision 092's own ceiling), MEMORY.md 20 KB, and
a SessionStart hook that re-printed CLAUDE.md and Current State on top of
Claude Code loading them natively.

**Cut, nothing lost.** Decisions 081–115 moved verbatim into
`docs/decisions/DECISIONS-081-115.md` (35 entries, byte-checked against
HEAD); 67 session-log entries and the April plan boards moved verbatim into
`docs/SESSION-LOG.md` (69 blocks, byte-checked); MEMORY.md rewritten to one
short hook per line (124 links, all resolving); the hook now prints one
212-byte line of git + version state instead of 12.5 KB of duplication.
After: SCRATCHPAD ~16 KB, DECISIONS 41 KB, MEMORY 12 KB, CLAUDE 12 KB.

**Corrected while there, because stale context costs more than tokens.**
CLAUDE.md said the web was "an editorial dashboard, not a consumer viewer",
that `tvOS-DESIGN.md` did not exist yet, that the Xcode project sat at repo
root, and framed the product as tvOS-only; the scratchpad's Current State
said 1.1.0 build 12 with empty icon assets. All rewritten to the September
truth — and pointed at Pulse for ship state rather than restating numbers
that rot. The `amazon_appstore_api_access` memory — the confident negative
Decision 111 says cost five weeks — now says the opposite.

**New rules, written where the next session will meet them:** DECISIONS.md
stays under ~50 KB (was ~120); SCRATCHPAD.md keeps exactly two session-log
entries and rolls the oldest into `docs/SESSION-LOG.md`; `/milestone` and
`/decision` carry both.

### 2026-09-14 — Pulse becomes the console; playlist sharing verified on every Android form factor
Owner: *"The whole point of Pulse is that I never have to go into the
individual dashboards."* Binding design: **docs/PULSE-ANALYTICS.md**.

**PULSE IS NOW SEVEN VIEWS**, one per audience — Overview, Reach, Engagement,
Health, Voice, **Program** (split out: *"Social Media should not be combined
with usage metrics"*), Ops — plus a tab per platform. All 22 tabs verified
rendering, every headline number cross-checked against `ops/pulse.json`.

**THREE ROUTES THOUGHT IMPOSSIBLE, ALL LIVE:**
- **Amazon installs are in the SALES report** (corrects Decision 111): for a
  free app every install is a `$0.00 Charge` row with a timestamp and country.
  30 installs; the 09-10 spike is Decision 115's minSdk fix landing.
- **Amazon's live version** is read by creating an edit (Amazon seeds it from
  live), reading its APKs, deleting it — and the reader deletes ONLY an edit
  it created, because an existing one is somebody's in-flight submission.
  **vc57 is live.**
- **Roku delivers to our own $0 endpoint.** No API exists (Looker); its four
  dashboards POST daily to the Cloudflare Worker that already ran the web
  counter. All four parse: 51 tiles, 112 installs, visitors/viewers/bounce/
  minutes, crashes, and **40 App Stability device tiles all empty** — nothing
  crashed on any Roku model.

**WHICH FILMS PEOPLE WATCH**, from data the counter already received and threw
away at the edge. `day | id | open|play|ambient | count`, never summed. Live:
28 plays across 10 films, 47 opens across 40. **privacy.html gained the counter
section it had been promising and never had**, and its false "no servers of its
own" claim was corrected.

**FOUR READER BUGS, each silent:**
- **macOS read ZERO** — Apple has two product-type families and the Mac one
  (`F1`, `FI1`) was missing. `skippedProductTypes` now records every uncounted
  code so the next forgotten family is a line on the dashboard.
- **Play installs were called "broken"** — they never were. Two ordinary lags
  stack (~6 days, plus the month's file appearing part-way through), and
  `tools/play_bucket_probe.py` settles it by listing the bucket.
- **Roku showed 0 installs** for a platform with 112, because a missing column
  defaulted to zero. Absence is written, not drawn.
- **`HEALTH_OWNS` had a hole** — three sections were DELETED rather than
  preserved when their readers were dark. A test now asserts full coverage.

**AND A RULE THAT COST A ROUND:** a degraded run may not overwrite a good
reading. A local `--apply` without CI's credentials replaced fresh Apple data
with a stale copy; `--apply` now refuses when a third of readers are dark.

**PLAYLIST SHARING** verified through the IMPORT on both Android form factors
(release builds, persistence across force-stop), plus the old-version path: an
app that predates `/list/` correctly falls through to the web.

**Also**: US spellings throughout the user-visible copy (the shared-playlist
sentence was British on five platforms); `sw.js` SHELL v74 → v75, without which
returning visitors keep the old shell; Samsung set on 1.42.100.

**OWNER, when you are back:**
1. **Roku 1.0.65** was scheduled for 5pm PT 2026-09-14. Pulse now detects it
   automatically — App Health's crash logs carry an `App Version`, so a build
   appearing there is proof it shipped. Watch the Roku tab.
2. **Fire TV vc57 is live** and `ops/stores-manual.json` is corrected.
3. Nothing else is blocked.
