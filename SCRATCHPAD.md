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
daily ~07:00 MT — cron 08:17 UTC, because GitHub runs this repo's schedules 4–5 h late (Decisions 108/109/123, `docs/PULSE-ANALYTICS.md`). The
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

### 2026-09-16 (audit loop, cont.) — Credits residue, Family genre, the rights confirm run by hand (Decision 125)
Owner /loop: "uploader information and reviews instead of information about
the film ... every piece of information ... accurate and unbiased."
- **Family is subject-only**: `genres_from_subjects` matched map keywords
  against the TITLE, so "The Family Doctor" and every Prelinger "Home Movie:
  Ohio Family" wore the Family genre; 205 unvouched tags come off no-id items
  every build. `test_family_genre.py` 7/7 (3/7 on the old code).
- **916 visible no-id items carried TMDb credit rows** (D125): "501" (a
  NetZero reel) wore a 2008 Danish film entire; Godzilla 1954 wore Aaron
  Taylor-Johnson behind a Wikidata QID. Strip is evidence-based; the KEEP is
  the cast reverse-matched to a same-titled film (`anchor_orphan_credits.py`
  grew the caches, 118/253). 269 visible items lose another film's credits;
  6 upload-dated features (Three Ages 1923, Smart Alecks 1942...) get their
  year from the same anchor instead of being hidden as "confirmed modern".
- **The rights confirm has failed in CI for three days** (archive.org refuses
  the runner, 4/4 each run). Ran it locally: 112 confirmed, Wormwood (2017,
  Errol Morris) among ~110 modern items now bucketed to hide on the next
  publish. Follow-up: schedule the confirm on the owner's Mac.
- publish-db dispatched three times (Family, residue, confirmed catalog).

Older entries: `docs/SESSION-LOG.md` (verbatim, back to 2026-04-17).

### 2026-09-14 (evening) — Party Play answers "what is this?" on every TV; playlist Share is visible; three Roku Library defects
Owner: *"I've been leaving the 'Party Play' going on my TVs ... enable sound
whenever I want ... go directly to the title that is playing ... shortcut to
simply add the item to the history"* — and a film they could not identify
("foreign language ... wheelchair chase scene down a highway").

**Audited before building.** Apple TV: sound toggle already a transport-bar
button, history automatic after 60 s, no route to the title. Google/Fire TV:
toggle in the options panel, NO history for lineups, no route. Roku: none of
the three — the player consumed no key but Instant Replay. Roku's Party pool
is the whole colour catalog (Apple's is cartoons + shorts), which is why the
unidentifiable film was a foreign feature: the catalog holds ~70 Hindi films
from 1959-78, and nothing in their metadata mentions a wheelchair, so the film
itself is still unnamed — the feature is the answer.

**Shipped, each verified on hardware** (1.42.120/1132, vc61, Roku 00073):
tvOS "Open Title" + "Remember" transport actions (tvOS-DESIGN §9.3a; console
trace + Detail on the Bedroom ATV); Android TV "Open title" + "Remember this
film" in the options panel and history-only writes after 60 s for lineups
(TV-DESIGN §5.6; Detail on the Google TV, row read out of user.sqlite); Roku
Up → OptionsList headed by the film's name with sound / open / remember
(ROKU-DESIGN §6.9; console, HUD line, Detail, Library Watched row on the
Streaming Stick). Roku defects found on the glass and fixed: Detail's Resume
judged against catalog runtime not the file's; Watched ids never resolved for
Library; a service query issued before the catalog task started was LOST
(deep-linked Library sat on "Nothing here yet"); a repaint from empty to rows
left focus on the Group.

**Earlier the same day**: playlist Share on iPhone was ONLY a leading swipe
(and Mac ONLY a right-click); now a toolbar icon on the playlist screen +
long-press menu, and a shelf-title icon on Mac (iOS-DESIGN §4.3 reserves
swipes for destructive verbs). 1.42.119 SUBMITTED for review on all three
Apple platforms (the workflow's own submit failed on empty notes; submitted
from here with notes). UI test `test_12_playlistShareIsVisible` on the
iPhone 12.

**Then, the same evening — the Minnie Mouse slideshow.** Owner: *"a slideshow
of Minnie Mouse stills ... shouldn't be a part of the database."* It was the
1922 silent *Minnie* by identity: Decision 032's wants hunt asked archive.org
for "Minnie" and `resolve_title` scored a fan gallery 115 (a one-word want gets
full overlap; no year on the gallery, so no wrong-year penalty), ingest dressed
it in the want's imdb/cast/poster, remediate adopted the canonical title. Not
one: **2,306 of 3,033 title-resolved wants were wrong**, 1,654 visible — porn as
"Her Son" (1920), a Holocaust-denial video as "The Denial", Shawn Mendes at the
VMAs as a 1921 silent. The catalog could not judge them (the title had been
overwritten), only archive.org's own title/date could: `audit_title_wants.py`
fetched all 3,033 (evidence committed), hid the 2,306 with `wrongMatchTitle`;
`audit_rights` gained the `wrongmatch_title` bucket so the reconcile keeps them
hidden; `resolve_title` now scores both ways and treats gallery/tribute/
gameplay/podcast titles as noise (`test_resolve_title.py` 8/8, 5/7 on the old
scorer). Catalog published (30,178 visible), publish-db dispatched.
The 727 kept matches are trusted on an archive title that agrees; the 1–2
stray-word band was NOT reviewed by hand.

**Legacy Roku (owner's Roku 2 XD)**: researched — Roku's store does not carry a
2026 channel on OS 9.1 (sunset 2019; cert 3.1); our package floor is already
v8.0.0; sideload works and is the only route. Write-up + the account-add test
for the owner in ROKU-SUBMISSION.md §Legacy players.

**Ship state at hand-off**: Apple 1.42.120 WAITING_FOR_REVIEW on all three
(1.42.119's submission cancelled and folded in); Play vc62 on internal
(person-on-hardware before promotion, D110); Roku 1.0.65 LIVE (Dashboard
Sep 15); a 00073 package with the Party verbs is built for the owner's
upload. Red-X emails fixed at the source: asc_release treats an in-flight
version as a warning, appstore-build skips submit with no notes, play-publish
retries a Google 5xx. Apple build 1132 + Play vc61 (internal track)
dispatched in CI; Roku package `build/roku/*.pkg` built for the owner's
Dashboard upload (00073). Per D110 the Play internal build wants a person on
hardware before promotion. Android TV's options panel still says "Play Next
Episode" in a lineup of films — a label, not fixed here.
