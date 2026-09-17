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
6. **Roku 1.0.75 (deep-link fix + options panel, Decision 126)**: uploaded to
   the beta (published) and the store (App Behavior Analysis running; then
   **Schedule publishing** is the owner's press). Ticket 110523 needs a reply
   asking for the Search Beta re-test — the Dashboard's Submit for review is
   disabled while the feed is FEED VALIDATED (= in certification).
7. **Watch Together Studio — BLOCKED ON THE OWNER, and it is the only
   blocker.** Everything else is built and verified on real hardware
   (`docs/WATCH-TOGETHER.md`, Decision 127). Three one-time owner steps:
   (a) a **Google Cloud project** with YouTube Data API v3 → an OAuth client
   id of type **iOS**, bundle id `app.archivewatch.tvos`, and a **Twitch
   application** with client type **public** → a client id, both into the
   gitignored `Secrets.xcconfig` as `YOUTUBE_CLIENT_ID` / `TWITCH_CLIENT_ID`.
   `Secrets.xcconfig.example` carries the click-by-click steps. Two strings
   and nothing else: **no client secret** (neither flow uses one) and no
   derived redirect string (the scheme is the bundle id, already declared in
   `Info.plist`). The sign-in code is written and its request shapes are
   proven against the real endpoints (Decision 128,
   `tools/test_studio_signin.swift`, 26/26). Without the ids the go-live
   sheet says sign-in is not set up and greys out Go Live;
   (b) **pair an iPhone** on the Apple TV via the system Continuity picker
   (once — a paired phone is found automatically after);
   (c) **allow camera + mic** on the iPhone (Settings ▸ Archive Watch) — there
   is no supported way to pre-grant on a device, and the harness refuses
   rather than hanging on a prompt.
   Also open, for the owner: widening the rights tier from `guaranteed`
   (4,210 films) to `strict` (7,517) is a Decision-027 content call.
8. **Fireplace TV is off limits for testing** (owner 2026-09-17, mid-run: "I'm
   actively watching on it now"). Bedroom and Movie Room are fine — but both
   are Apple TV 4K **3rd** gen, and Fireplace is the only **2nd** gen, i.e.
   the Studio's hardware floor. The §8.3 ten-minute soak passes on the 3rd gen
   (`docs/WATCH-TOGETHER.md` §9); the 2nd-gen repeat needs a window the owner
   offers, and **no window is currently agreed** — ask before touching
   Fireplace. Movie Room is NOT in the tvOS provisioning profile — it fails to
   install; Bedroom works.

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

### 2026-09-17 (audit loop) — The uploader-synopsis pass is DONE; misdated moderns and off-air tapes hidden by table; a spliced catalog repaired
Owner /loop, 5-minute ticks: "uploader information and reviews instead of
information about the film ... every piece of information ... accurate and
unbiased."
- **Every visible `synopsisSource: archive` item has now been read by the
  agent** — 0 of 4,057 unreviewed (was ~8,140 on 09-16). 120 per tick via
  `metadata_review.py select --limit 120 --source archive`, decisions keyed
  by id prefix, `apply` stamps `agentReviewHash`. Totals at the end: 3,328
  rewritten, ~4,000 kept, the rest nulled. Classes closed on the way, each
  measured before it became a rule: NARA/DoD/USIA header dumps, Media History
  Project boilerplate, Hoffmann/Dewenter collection biographies, California
  Revealed `Description:/Source:/Rights:` wrappers, Prelinger "shots to be
  logged", home-movie catalog-id and `N min., color:` prefixes, `notes on
  can` tails, drive-in compilation tails, Fleischer Screen Song boilerplate
  (x25), Bill Sprague "no complaints" stubs (x20+), Public-Domain-Day tails,
  "Aired during …" commercial breaks, and the AI-colourised apologies.
- **Two new id-keyed tables**, re-applied by remediate every build:
  `shared/editorial/not_films.json` (`excluded=True`, `excludedReason:
  not_a_film` — ~350 entries: off-air VHS network blocks typed "commercial",
  full newscasts, studio cartoon/feature collections (Disney, Lantz, WB,
  Marx Brothers), fan mashups and machinima, MIT OCW courses, recipes, rants,
  conspiracy videos, and copyrighted features wearing silent-era years —
  The Crow 1919, Titfield Thunderbolt 1919, Journey to the Center of the Earth
  1910, a 2025 Dupieux feature 1912) and `year_corrections.json` (~35: The
  Third Man 1943→1949, Flash Gordon 1969→1936, Cinderella 1907→1922 …).
  Hides of television are NOT taken here — Decision 027 reserves them.
- **Incident**: a backgrounded `overlay_publish.sh` woke during a local
  apply; the two writers interleaved and the spliced 133 MB file was
  published (publish-db failed on it; no bad DB shipped). Repaired from the
  three intact segments + the rolling SQLite's blobs (minus the 2,189
  episodes build_sqlite materialises), ~150 excluded items lost to
  re-derivation. `catalog_release.py publish` now refuses a file that does not
  parse; the publish step is foreground-only and skips a tick when a build is
  in flight. Memory: `catalog_write_race_2026_09_17`.
- Also: `_COPYRIGHT_CLAIM` learned "rights are reserved for"; a
  whitespace-only synopsis is nulled; Space: 1999's "Dragon's Domain" was
  credited to Michael Crichton (Charles).
- **For the owner**: the television rights list grew (full series of Fawlty
  Towers, Space: 1999, Planet of the Apes 1974, The World at War, Here's Lucy,
  Doctor Who seasons, ITV sitcom bundles); `gov.nps.rmrs.wildfire` is a 2000s
  USDA video wearing 1929; `The White House Story` (1960s) wears 1897.
  Next audit fields per Decision 124: `director`/`cast` from the Archive
  `creator` field, subject-inferred genres.
- **Later the same night — every other displayed field, measured**:
  - *Credits*: 637 no-id directors / 249 casts, almost all right (the D125
    anchors). Nulled 13 "Unknown/n/a/Uncredited"; nine "Public Domain
    Animation 19xx" reels wore TMDb ids whose credits were Chinese generals.
  - *The rights hole the credits pass exposed*: 184 visible 1970s features
    with an anchored cast (Eraserhead, Suspiria, Young Frankenstein, A Bridge
    Too Far) sat at `rightsAudit: None` — no id, no `imdbVotes`, so D114's
    5,000-vote gate never saw them. `tools/anchor_rights_footprint.py` (local:
    TMDb → OMDb) writes `shared/editorial/anchor_footprint.json`; remediate
    carries the votes (id fields stay cleared); the audit's own rules hide
    47 + 4. Then the LOOP: a hide made the item excluded, the anchor skipped
    excluded items, the residue strip took cast + votes, the reconcile un-hid
    49. Fixed: the anchor judges excluded items, a stripped anchored cast is
    restored from `tmdb_cast_cache`, the cleared-residue strip keeps the
    footprint. Also: a government-collection item never anchors (a NASA
    "Avatar" wore Sam Worthington); an item under half its feature's runtime
    is an `excerpt` (Close Encounters' Mothership Scene, 981k-vote Twelve
    Angry Men → the promo rule).
  - *Genres*: 243 tags rested on a TITLE word; "adventures"/"noir"/"western"
    are blind there and inside the show's own name as a subject (29 Ozzie &
    Harriet episodes were "Action"). *TV items wearing an unverified FILM
    match*: 87 cleared (Betty White Show → Planet of the Apes, The Flash →
    Muriel's Wedding) — an episode has no aka. *Far-year matches*: 4.
    *Residue*: writer/studio/keyword/rating on id-less cast-less items.
  - *Titles*: brand prefix, subtitle-language and ".3gp/.HD" tails, wrapping
    quotes, all-caps audited titles (132 visible); `title_corrections.json`
    (34) has the last word. *Reviews*: 12 file-quality complaints off the
    "From archive.org viewers" shelf; a full re-score would have dropped 485.
  - *TV spines*: every episode overview is TVmaze's (unstamped). *Language*:
    122 raw values, rendered nowhere.
- **Later still (owner stopped the loop ~06:10 MT)**: OMDb's "Plot" for
  obscure silents is often an IMDb user review ("*** (out of 4)", "I strongly
  suspect some of this film is missing") — `_OMDB_REVIEW` extended, 31
  nulled; a checked API is not a checked FIELD. Reviews shelf: file-quality
  complaints and contact/licensing requests come off (`comment_fit` +
  remediate re-judge; a full re-score dropped 485 genuine ones, so only the
  NEW signals re-judge). The daily publish-db summary now reports
  `synopsis.unreviewed` / `synopsis.unstamped` (both 0); the first day's
  drift was the ~150 corruption-lost items re-ingested by discovery —
  reviewed, and a `keep` now stamps `synopsisSource: archive` (16 had
  reached the client unlabelled). The rights confirm (archive.org refuses
  CI) now runs inside the local publish step; 4 targets stay refused.
  Steady state: excluded 11,780, `un-hidden=0` over six builds, remediate
  idempotent (two runs, 0 field diffs).
- **Roku options panel** (owner, on the Roku 2 XD: "a strange circle
  selection that doesn't actually highlight the option", then "still don't
  think this selection area looks well designed"): the LabelList rows are
  now a MarkupList of `OptionRow` — the 60 px §13.5 pill, label in Inter
  Medium inset 30 px, 24 px gutters, pill loaded synchronously. Verified on
  the XD (Detail More, Party Play Up) and the Streaming Stick 4K; both are
  SIDELOADED with it — the store channel needs a 00074 package.
  ROKU-DESIGN 14.13. Found on the way: a contact-request "review" on
  Bamboo Isle (fixed above).
- **Roku Search certification FAILED the deep link** (ticket 110523: "redirects
  to the channel's home screen instead of playing"). Not the feed, not the
  params: the single-id lookup shared the service's query record with Continue
  Watching's `resolveIds`, the task served the merged record once, and the ids
  branch won — only on a device WITH history, which the harness never was.
  Own field pair `lookupId`/`lookupResult`, Decision 126; verified on both
  Rokus; 1.0.75 packaged and uploaded to beta + store. Also: last night's
  publish-db/deploy-pages failures were the spliced catalog (above), already
  repaired — every run since is green.
- **WATCH TOGETHER STUDIO, built the same day** (owner: reframe Live Riffing as
  "Watch Together" and "Watch Together Studio"; SharePlay is the private half,
  the world is the public one). Decision 127, rules in
  `docs/WATCH-TOGETHER.md`, iOS-DESIGN §8.8/§8.9, tvOS-DESIGN §8.8/§10.2a.
  Phase 0 answered: **1080p30 holds on both hardware floors** — iPhone 12
  render 8.71 ms and Apple TV 4K 2nd gen 10.70 ms of a 33.3 ms budget, 0
  dropped, thermal nominal — so §3.3's ReplayKit fallback is closed and in-app
  composition is the architecture. Our OWN `RTMPPublisher` (no encoder
  dependency) reaches all four real ingests from the Mac, the iPhone AND the
  Apple TV with an invalid key, i.e. no credential. Audio: the film tapped off
  its own mix + the mic, ducked 12 dB, A/V aligned to **10 ms over 15 s** in
  mediamtx's own recording. Rights: `audit_rights.bucket()` now rides the
  client DB (schema 2) so the client applies the AUDIT's answer, tier
  `guaranteed` → **4,210 of 24,943 films**; an unknown verdict refuses, and a
  cached schema-1 device proved that on the glass unprompted. Overlay: five
  layouts, four cards, chat in the program, all rendered over a worst-case
  stand-in film and LOOKED at.
  Findings worth the trip: RTMP's `connect` must be transaction **1** (YouTube
  hardcodes it; two other servers echoed ours and hid the bug); a cached
  full-frame overlay composite cost 5.6 ms until it was cropped to its
  content; `AVPlayerItemVideoOutput` asked for 32BGRA returns NOTHING on tvOS;
  `.playAndRecord` fails on tvOS because there is nothing to record from until
  a Continuity mic port exists; and a readout can be correct and still lie —
  it said IDLE while encoding 5.5 Mbps because it reported the publisher's
  state, not the show's.
- **Live Riffing research** written: `docs/LIVE-RIFF-RESEARCH.md` — YouTube
  and Twitch take RTMP from any encoder (no WHIP for general creators);
  HaishinKit (Apple) / RootEncoder (Android) on-device; LiveKit Egress or
  Cloudflare RealtimeKit for guests-by-link and the web; the feature bar
  from OBS/StreamYard/Moblin; a phased plan (iPhone spike → phone studio →
  **Apple TV studio via Continuity Camera (tvOS 17, Apple TV 4K 2nd gen+,
  third-party apps get the iPhone's camera AND mic through AVFoundation)** →
  Mac → Android → guests). Nothing built; no design rule changed.

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
- **Later ticks, each on the live catalog**: subject keywords match plurals
  ("cartoons" → Animation, 111), bare "music" ≠ Musical, Family needs an
  AUDIENCE subject; uploader-voice grew (!!, emoticons, "please click",
  10/10, ownership disclaimers in any language); a YEARLESS item is never
  cast-anchored (Follow That Man / "A Family Affair" 2024 — 90 stripped);
  director/producer library-catalog forms normalized; title tails
  (fullwidth ｜, ALL-CAPS genre, a cast name + genre word); and 1,140
  placeholder synopses ("To come.", "510", the title echoed, "The Red Dragon
  1929 Warner Oland...") become empty. Tests: test_family_genre,
  test_uploader_voice, test_title_cast_tail, test_placeholder_synopsis,
  test_unanchored_tmdb_residue. publish-db dispatched after each batch.
- **The text loops end here** (sample miss rates 4–12 of 40–50, every one a
  phrasing, none a class). The tail now goes through
  `metadata_review.py select --source archive` — the agent judges each uploader
  synopsis keep/rewrite/null, popularity-first; first batch of 60 applied and
  published (22 rewrites, 5 nulls, 33 keeps). ~8,140 remain; the top ~2,000
  by popularity is the bounded pass worth doing.

Older entries: `docs/SESSION-LOG.md` (verbatim, back to 2026-04-17).
