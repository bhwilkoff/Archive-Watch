# Archive Watch — Architecture & Technology Decisions

Entries are ordered by date. This file is **append-only** — never
edit or remove past decisions. Platform noted where specific;
unlabeled = both.

## Format

- **Entries 001–015** use the older "Decision / Rationale /
  Alternatives / Trade-offs" format. They stay as-is.
- **Entries 016 onward** use the lead-with-WHY format — see the
  `architectural-decision-log` skill. The new entry template:

  ```
  ## NNN — Short imperative title
  *Date: YYYY-MM-DD*

  One paragraph stating the concrete decision. Lead with WHAT in
  specific terms — the first sentence is the choice.

  **Why**: the constraint, past incident, or alternative-rejected
  that makes this choice make sense.

  **How to apply**: when the next developer encounters this
  decision, what should they do or not do?

  (Optional) **Consequences**: forward-looking implications.
  ```

Each new entry must answer: *"what would the next developer get
wrong if they didn't know this?"* — if the answer is "nothing," the
entry isn't earning its keep.

Invoke `/decision` to log a new entry.

---

## Decision 001 — Vanilla HTML/CSS/JS for Web
*Date: YYYY-MM-DD*

**Decision**: No framework, no build step, no dependencies for the web app.

**Rationale**: GitHub Pages serves static files directly. Framework
abstractions cost more than they save at this scale. Aligns with
clarity-over-cleverness.

**Alternatives considered**: React, Vue, Svelte — all require a build step.

**Trade-offs**: Manual DOM manipulation, no reactive state. Revisit if
component count exceeds ~20.

---

## Decision 002 — Xcode Project at Repository Root
*Date: YYYY-MM-DD*

**Decision**: The `.xcodeproj` lives at the repository root, not in a
subdirectory. Project name has no spaces.

**Rationale**: Xcode Cloud requires `.xcodeproj` at the repository root.
Spaces in paths cause issues with shell scripts, CI/CD, and Xcode Cloud's
project discovery. Lesson learned from Bsky Dreams where
`BskyDreams-iOS/Bsky Dreams/Bsky Dreams.xcodeproj` (two levels deep, spaces)
caused persistent "Project does not exist at root" errors.

**Alternatives considered**: Subdirectory with Xcode Cloud custom workspace
path — fragile, undocumented, breaks on Xcode updates.

**Trade-offs**: Web and iOS files share the same root directory. Use
`.gitignore` to keep build artifacts out of the web deployment.

---

## Decision 003 — Shared Version Config (xcconfig)
*Date: YYYY-MM-DD*

**Decision**: `AppVersion.xcconfig` at repo root defines
`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. All targets reference it.

**Rationale**: Editing version numbers via Xcode's identity panel creates
per-target overrides in `project.pbxproj` that shadow the xcconfig, causing
targets to drift. A single xcconfig is the single source of truth.

**Trade-offs**: Must remember to edit the xcconfig, not the Xcode UI.

---

## Decision 004 — SwiftUI + @Observable + SwiftData (iOS)
*Date: YYYY-MM-DD*

**Decision**: SwiftUI for all UI. `@Observable` (iOS 17 macro) for state
management. SwiftData for local persistence. UIKit only where SwiftUI lacks
a native equivalent.

**Rationale**: Modern Apple stack, minimal boilerplate, no third-party
dependencies.

**Trade-offs**: iOS 17+ minimum deployment target.

---

## Decision 005 — Dual-Platform Feature Parity Model
*Date: YYYY-MM-DD*

**Decision**: Both platforms implement the same core feature set. Track
parity in SCRATCHPAD.md. Platform-specific implementation choices are
acceptable (e.g., Keychain vs localStorage for auth).

**Rationale**: Users expect the same capabilities regardless of platform.
Implementation details can differ to leverage each platform's strengths.

**Trade-offs**: Every feature is effectively built twice. Mitigated by
shared API contracts and design tokens.

---

## Decision 006 — tvOS as the primary (only consumer) platform
*Date: 2026-04-17*

**Decision**: Archive Watch is a tvOS 17+ app. The web scaffold in this
repo is retained only as a future editorial dashboard (curated
`featured.json` on GitHub Pages, consumed by the tvOS client). There is
no iOS companion viewer in the roadmap.

**Rationale**: The Internet Archive's strongest suit — feature films,
classic TV, newsreels, silent cinema — is best experienced at the 10-foot
viewing distance on a large screen with native transport controls. An
iPhone/iPad viewer would dilute focus without meaningfully extending
reach; archival viewing is a living-room activity.

**Alternatives considered**: Universal iOS+tvOS app (would force UI
compromises; tvOS HIG is sufficiently distinct that shared SwiftUI views
degrade both platforms). iPadOS-first (wrong form factor for the
content).

**Trade-offs**: Template's Dual-Platform Feature Parity Model does not
apply. Web directory stays, but only for the editorial curation page.

---

## Decision 007 — TMDb as primary metadata provider (non-commercial tier)
*Date: 2026-04-17*

**Decision**: The Movie Database (TMDb) is the primary source for
posters, backdrops, cast, crew, runtime, genre, and synopsis enrichment.
Use the free non-commercial tier (~40 req/10s). Required attribution
("This product uses the TMDB API but is not endorsed or certified by
TMDB" plus TMDB logo) is rendered on a dedicated About/Attribution
screen.

**Rationale**: TMDb has the most complete free metadata and artwork
coverage for films and TV. Community-supplied image library is vastly
richer than Archive.org's uploader thumbnails. Its `/find` endpoint lets
us match by IMDb ID, which Archive items commonly carry in their
`external-identifier` field. This identifier chain (Archive → IMDb →
TMDb) is the backbone of our enrichment pipeline.

**Alternatives considered**:
- OMDb — poster access gated behind donation; 1000 req/day too tight.
- IMDb directly — no free public API.
- Wikidata-only — coverage is thin for obscure ephemera and artwork
  must be resolved through Commons anyway.

**Trade-offs**: TMDb commercial terms require negotiation for paid apps.
Resolved by shipping Archive Watch as a **free App Store release** — see
Decision 010.

---

## Decision 008 — Identifier-chaining enrichment cascade
*Date: 2026-04-17*

**Decision**: Every Archive item is enriched through a fixed cascade:

```
archive.org/metadata/{id}
  → read external-identifier (urn:imdb:tt...)
  → if missing: SPARQL Wikidata by P724 (Internet Archive ID)
  → TMDb /find/{imdb_id} → full movie detail + images
  → Artwork resolver (TMDb poster → Wikidata P18 → Commons category
    → Library of Congress → Archive thumb as final fallback)
  → Normalize to ContentItem schema with controlled taxonomy
```

All enrichment results cache to SwiftData with a tiered TTL (TMDb 30d,
Wikidata 90d, Commons/LoC 180d, Archive metadata 7d). Artwork bytes
cache to `URLCache` at 500 MB disk.

**Rationale**: No single source has sufficient coverage or quality.
Cascading fallbacks make every card look "produced" regardless of which
source ultimately serves it. Persistent caching means the network cost is
paid once per title, across all users of a given install.

**Alternatives considered**: Single-source-per-item (fragile); build an
off-device enrichment pipeline on GitHub Pages (defers complexity but
adds a second deployment surface).

**Trade-offs**: Four external services to harden against failure. Each
step has its own rate limit and User-Agent requirement. Mitigated by a
single `HTTPClient` base that handles 429 + `Retry-After` uniformly.

---

## Decision 009 — No user accounts; all state local
*Date: 2026-04-17*

**Decision**: Archive Watch has no sign-in, no cloud sync, no account
system. Continue Watching, Favorites, and Search History live in local
SwiftData. A future CloudKit sync is possible but explicitly out of
scope for v1.

**Rationale**: Removes the largest friction point for trial use,
simplifies the privacy policy to near-zero, and aligns with the
learning-orientation values ("no funnel, no upsell"). Matches the no-
friction ethos of UHF.

**Alternatives considered**: "Sign in with Apple" + CloudKit sync.
Deferred — low marginal value for a living-room app; most users install
on one device.

**Trade-offs**: No sync across Apple TV units in a household. If the
user buys a new Apple TV, Continue Watching starts fresh. Acceptable for v1.

---

## Decision 010 — Free App Store release (resolves TMDb commercial question)
*Date: 2026-04-17*

**Decision**: Archive Watch ships as a free, non-commercial App Store
app. No in-app purchases, no subscription, no ads.

**Rationale**: All content is public domain; charging for access would
be ethically awkward. TMDb's non-commercial free tier is the natural
match: no paid relationship with TMDb needed. The app's sustainability
path, if any, is donations to the Internet Archive (surface a link in
Settings) — never to the app itself.

**Alternatives considered**: Paid upfront, "tip jar" IAP, optional
donation sub. All rejected for the reasons above.

**Trade-offs**: No revenue. Development is a labor of love / portfolio
piece. Server-side costs are zero (no backend; curated picks ride on
GitHub Pages). Operational cost is effectively the Apple Developer
Program membership.

---

## Decision 011 — Hybrid curation: editor's picks + popularity-driven shelves
*Date: 2026-04-18*

**Decision**: Home is composed of two shelf types maintained in a
single `featured.json` (versioned in this repo, served from GitHub
Pages):

1. **Curated shelves** — explicit hand-picked Archive identifiers, each
   with an optional curator note. The seed for v1 is the owner's own
   favorites. Edited via the dashboard at `/index.html`.
2. **Dynamic shelves** — `(query, sort, limit)` triples that the tvOS
   app resolves at runtime by calling Archive's scrape API
   (`mediatype:movies AND collection:feature_films` sorted by
   `-downloads` etc.). Popularity is the default ranking.

The dashboard is a static page that reads `featured.json`, lets the
curator add/remove/reorder Archive IDs (with live metadata preview from
Archive.org), and exports a new `featured.json` for commit.

**Rationale**: A purely curated catalog ages and feels light; a purely
algorithmic feed loses voice. Hybrid lets a small editorial gesture
("Editor's Picks") sit atop a self-refreshing popularity backbone
without any backend, recommendation engine, or ML.

**Alternatives considered**:
- Fully manual curation — too much maintenance, content gets stale.
- Fully algorithmic — abandons the editorial voice that's core to the
  product positioning.
- Server-side curation pipeline — adds infrastructure and cost.

**Trade-offs**: Dynamic shelves depend on the live Archive scrape API;
when Archive is down, those shelves go empty. Mitigated by caching the
last-good response in SwiftData.

---

## Decision 012 — Adult content filter on by default
*Date: 2026-04-18*

**Decision**: The tvOS app filters out items belonging to adult-content
collections by default. The list of excluded collections lives in
`featured.json` under `adultCollections`. A Settings toggle ("Show
mature collections") opts back in, off by default.

**Rationale**: Archive.org's collection taxonomy is permissive; some
adult-leaning collections drift into general searches. Default-on
filtering protects unintended audiences (a TV in a living room is a
shared device) without being paternalistic — the toggle remains
available.

**Alternatives considered**: No filter (rejected — wrong default for
a 10-foot device). Hard removal (rejected — denies user agency).

**Trade-offs**: The `adultCollections` list must be kept current. Worst
case, an undeclared adult collection slips through; the curator updates
the list and the next app launch picks it up.

---

## Decision 013 — Per-category accent colors
*Date: 2026-04-18*

**Decision**: Each major content category gets its own accent color,
declared in `featured.json` and read by both the dashboard and the
tvOS app. v1 palette:

| Category    | Accent     | Notes                              |
|-------------|------------|------------------------------------|
| Feature Film| `#FF5C35`  | Marquee orange (the primary)       |
| Classic TV  | `#2D5BFF`  | CRT phosphor blue                  |
| Silent Era  | `#C9A66B`  | Sepia / nitrate                    |
| Animation   | `#FF4D8D`  | Saturated playful pink             |
| Newsreel    | `#8A8F98`  | Newsprint gray                     |
| Documentary | `#3FA796`  | Muted teal                         |
| Ephemeral   | `#7C5BBA`  | Faded violet                       |
| Short Film  | `#E8A317`  | Warm amber                         |

Accent appears as: shelf title underline, focused-card glow tint, the
category dot in the dashboard, and the app icon background tint when
generated dynamically (see Decision 015 once we log it).

**Rationale**: Differentiates shelves at a glance, gives each category
identity without resorting to skeuomorphism, leaves a single neutral
background as the unifying canvas. Bounded palette (8 colors) prevents
the rainbow look.

**Alternatives considered**: Single accent only (rejected — flat,
indistinguishable shelves). Per-collection accents (rejected — too many
collections; would chase its own tail).

**Trade-offs**: Color choices are subjective. Owner has final say;
revisit if any feel discordant on a real 4K display.

---

## Decision 014 — Random actions are M1 features
*Date: 2026-04-18*

**Decision**: Three serendipity actions ship in M1 (not deferred to
polish):

- **Random Movie** — picks a random item from a popularity-floored
  query (`-downloads > 1000`) and goes straight to playback.
- **Random Category** — picks a random major category and lands on a
  shelf-only Browse view for that category.
- **Random Collection** — picks a random Archive collection and shows
  it as a single-shelf Browse view.

All three appear as primary actions on the Home screen (under the hero
carousel) and accept Siri Remote dictation ("hey Siri, surprise me").

**Rationale**: A cinematheque rewards wandering. Random actions are
low-effort to build (one query + a navigation push), high-value for the
"I don't know what to watch" mood, and align with the app's
learning-orientation values (invite participation, support human
agency).

**Alternatives considered**: Single "Surprise me" button (too narrow);
deferring to M3 polish (would miss the opportunity to seed habit on
launch).

**Trade-offs**: Random Movie that lands on a broken/un-playable item
ruins the moment. Mitigated by: (a) requiring `videoFile` to exist in
the metadata before navigating, (b) silently re-rolling up to 3 times
on failure, (c) the `tools/validate-pipeline.sh` script and the
dashboard preview both surface "not playable" so curators can spot
broken items in advance.

---

## Decision 015 — tvOS home screen integration: Top Shelf + NSUserActivity + App Intents; skip Apple TV App partner program for v1
*Date: 2026-04-18*

**Decision**: Three integrations land in v1, one is deferred:

1. **Top Shelf extension** with `.sectioned` style, surfacing
   Continue Watching + Editor's Picks + What's New when our app icon
   is focused on the tvOS Home Screen. **Ships in M4.** Reads from a
   shared App Group container (`group.com.bhwilkoff.archivewatch`)
   that the main app refreshes via `BGAppRefreshTask`.

2. **NSUserActivity** declared on Detail screens to enable
   *"Hey Siri, add this to my Up Next"* (which adds to the Apple TV
   app's system-wide watchlist). **Ships in M2.** Tiny code surface,
   real user value, no partnership required.

3. **App Intents** (`AppIntent` + `AppShortcutsProvider`) for the
   three random actions, enabling *"Hey Siri, surprise me on Archive
   Watch"*. **Ships in M2** alongside Decision 014's random actions
   and the deep-link routing they need.

4. **Apple TV App partner program** (third-party content surfacing
   directly inside Apple's TV app's Up Next, Universal Search,
   Single-Sign-On, Subscription Registration) is **deferred to v2**.
   It requires a formal partnership with Apple, ongoing engineering
   to maintain Apple's prescribed metadata feed, and is fundamentally
   designed for premium streaming services. Revisit once we have
   meaningful install count.

Deep-link routing (`archivewatch://item/{id}`, `/play/{id}`,
`/random/...`) is a prerequisite for #1 and #3 and lands in M2.

**Rationale**: These three integrations capture ~95% of what makes
tvOS feel like a first-class home for the app, with very little
incremental engineering on top of what M2 and M4 already require.
Skipping the partner program keeps the project free of contractual
obligations to Apple.

**Alternatives considered**:
- Ship only the Top Shelf and skip NSUserActivity / App Intents
  (rejected — the Siri integrations are nearly free given the random
  actions are already specified).
- Pursue full Apple TV App integration in v1 (rejected — wrong
  trade-off for a free, labor-of-love app; partner program is a
  multi-month commitment).

**Trade-offs**: Top Shelf adds a second target to maintain, an App
Group entitlement to manage, and `BGAppRefreshTask` complexity. The
research doc (`docs/research/tvos-home-screen-integration.md`)
captures the full implementation plan including known gotchas
(extension memory limits, image-size requirements, deep-link
defensiveness).

---

## 016 — Canonical TV spine from TVmaze; Archive items map onto it
*Date: 2026-06-01*

TV is built around a canonical series→season→episode spine fetched from
TVmaze (free, no API key), with our Archive items mapped onto canonical
episodes. `tools/build_canonical_tv.py` resolves each show to TVmaze
(disambiguating by year), pulls the authoritative episode list, maps our
items by `SxE`/episode-number/fuzzy-title, re-picks each mapped item's
H.264 MP4 derivative, and emits `series/{slug}.json` (version 2, with
`tvmazeID` + `canonicalEpisodesCount`). `tools/reconcile_tv_catalog.py`
then rebuilds the catalog's tv-series cards from those files, drops
singles that became episodes, and reclassifies whole-show single files to
`tv-special`. Result: 1,467 mixed "tv-series" cards → 366 real series
(233 canonical + 133 preserved non-TVmaze clusters) + 1,029 reclassified
single items.

**Why**: the old pipeline synthesised "series" by clustering Archive
items on filename similarity. That produced 1,064 single items mislabelled
as series, real shows truncated to a few episodes, and episodes with no
real S/E numbers, titles, overviews, air dates, or artwork (46–66%
missing). Movies don't have this problem because one Archive item == one
title; TV needs an external authority for structure. TVmaze provides
complete episode lists with stills/summaries and needs no key; year-based
disambiguation separates same-named shows (1980 vs 2024 Shōgun).

**How to apply**: don't reintroduce filename-based series clustering. New
TV shows enter through the canonical builder. A show that doesn't resolve
on TVmaze (foreign, compilation, channel, ephemera) is NOT a series —
keep its existing clustered file if it has real episodes, otherwise leave
its items as single playable cards. A matched show with items we can't
align still becomes a series (canonical series-level metadata + items as
best-effort episodes) — never demote a real multi-episode show to a
single. Series JSON is fetched from GitHub Pages at runtime, so new/
renamed `series/*.json` only take effect after a push to `main`.

**Consequences**: TVmaze becomes a fourth runtime-relevant data source
(build-time only). `canonicalEpisodesCount` vs available count feeds the
episode-wants backfill (what to look for on Archive next). TMDb can later
supplement episode artwork for old shows where TVmaze stills are sparse,
if `TMDB_BEARER_TOKEN` is added.

---

## 017 — Deliver the catalog as a prebuilt SQLite DB on GitHub Pages
*Date: 2026-06-02*

The app will move from downloading + decoding a monolithic `catalog.json`
into memory to downloading a **prebuilt `catalog.sqlite.gz`** from GitHub
Pages, caching it in `Library/Caches`, and **querying it on disk** (read-only
`libsqlite3` + FTS5) for Home/Browse/Search/Detail. The pipeline gains
`tools/build_sqlite.py`; `catalog.json` stays as the editorial source of
truth + dashboard input. Rollout is phased and non-breaking (publish SQLite
first, migrate the app behind existing view APIs, then retire the in-app JSON
load). Full design + research in `docs/architecture/catalog-delivery.md`.

**Why**: the binding constraint is memory, not download. URLSession already
gzip-downloads the catalog (~19 MB over the wire), but it then decompresses
to 97 MB and decodes ~29k structs held in `@Observable` — 150–250 MB resident
today, 500 MB–1 GB at 100k items, on a 3 GB Apple TV shared with tvOS + 4K
AVPlayer. That is jetsam territory. GitHub Pages can't do byte-range partial
fetch (tested: `Range:` → 200, not 206), so JSON sharding only shrinks the
constant; SQLite query-on-disk fixes the model — resident memory becomes the
visible rows, and it scales to 1M+ with FTS5 search. SQLite is built into
tvOS, so this adds no third-party Swift package.

**How to apply**: don't grow the in-memory `[Catalog.Item]` model as the
catalog scales — it's an interim path. New browse/search/detail work should
target the `CatalogDB` query layer (Phase 2+). Keep the bundled seed lean and
bulk ingest `--no-seed`. The IMDb dedup + heavy/lean field split move into the
SQLite export, not runtime. Version the published DB filename so the CDN never
serves a stale DB.

**Consequences**: a `CatalogDB` actor becomes the app's catalog source of
truth; `AppStore` derived lists become queries. The weekly/daily pipeline
publishes both JSON (dashboard/source) and SQLite (app). Refresh validates
the downloaded DB (`PRAGMA integrity_check` + row-count floor) before swap.

---

## 018 — Full catalog.json lives in a GitHub Release, not git
*Date: 2026-06-02*

The full ~95 MB `catalog.json` (30k+ items, heading for 100k–1M) is moved OUT
of git and hosted as a gzipped asset on a rolling `catalog-source` GitHub
Release (~20 MB), mirroring the SQLite delivery in Decision 017. Catalog-
mutating workflows `python tools/catalog_release.py fetch` at the start
(download + gunzip to `./catalog.json`) and `… publish` at the end (gzip +
clobber the release asset). Every tool keeps reading/writing the local
`./catalog.json` unchanged. The file is gitignored. The bundled first-paint
seed is no longer a committed 14 MB `ArchiveWatch/ArchiveWatch/catalog.json`;
`build_sqlite.py` derives a small `seed.sqlite` (all TV-series cards + shelf
items + top ~1,500 by popularity) directly from the full catalog.

**Why**: Decision 017 made the *app* lightweight (it downloads the SQLite from
a Release and queries on disk) but the *git repo* kept bloating — the 95 MB
`catalog.json` was committed on every rebuild across 26 commits, pushing `.git`
to 624 MB and `catalog.json` to the edge of GitHub's 100 MB hard push limit
(beyond which pushes FAIL, not just warn). The full catalog is a generated
accumulator, not hand-authored source, so it fails the "does this belong in
git" test. Keeping it in git made every rebuild PR a ±155k-line, 95 MB diff
that also flaked PR creation. The GitHub Pages editorial dashboard reads only
`featured.json`, never the full catalog, so nothing user-facing depends on it
being in the repo.

**How to apply**: never re-add `catalog.json` (or a full seed
`catalog.json`) to git — they're gitignored. New catalog-mutating tools/
workflows must `catalog_release.py fetch` before and `publish` after. The
editorial source of truth that DOES stay in git is small and hand-authored:
`featured.json`, `series/*.json` spines, discovery seeds, tools, and the slim
bundled `seed.sqlite`. Keep the seed small (it ships in the app bundle and is
committed); bulk-ingest into the full catalog, not the seed.

**Consequences**: the catalog is no longer line-diffable in git (acceptable —
it's machine-generated). The pipeline is now stateful (download → mutate →
upload); each workflow that mutates the catalog must serialise via the
existing `catalog-writers` concurrency group to avoid clobbering. Git history
was rewritten once (git filter-repo) to purge the historical `catalog.json` /
seed blobs, reclaiming ~600 MB; this rewrote all commit hashes and required a
force-push + fresh clones.

---

## 019 — On-device catalog DB decompression via Apple's Compression framework
*Date: 2026-06-02*

The app downloads the catalog DB as a raw-DEFLATE asset (`catalog.sqlite.zz`,
~24 MB) from the catalog-db Release and inflates it on device with Apple's
native **Compression** framework (`compression_stream`, `COMPRESSION_ZLIB`),
streaming file→file in 64 KB chunks. `build_sqlite.py` emits the `.zz` via
Python `zlib.compressobj(wbits=-15)` (raw DEFLATE, no wrapper); `publish-db`
uploads it alongside the still-uncompressed `catalog.sqlite` (for already-
shipped builds). `CatalogRefreshService` downloads `.zz`, inflates to a staging
file in Caches, size-validates, then atomically swaps.

**Why**: the DB is ~96 MB uncompressed but ~24 MB compressed, and app refreshes
were fetching the full 96 MB every time. GitHub Release assets are served
`application/octet-stream` with **no `Content-Encoding`** (verified), so
URLSession can't transparently decompress — it must happen in-app. Apple's
Compression framework is the right platform tool: hardware-accelerated, in the
tvOS SDK (no third-party zlib to vendor). It decodes **raw DEFLATE only** —
verified by test: a standard `.gz` fails (`COMPRESSION_ZLIB` is not the gzip
container) unless its header is stripped, which is fragile, so we publish raw
DEFLATE instead. Streaming keeps peak memory ~64 KB instead of holding 96 MB in
RAM — the same constraint that drove Decision 017 on a 3 GB Apple TV shared
with 4K AVPlayer.

**How to apply**: keep the publish format raw DEFLATE (`wbits=-15`), NOT gzip
or zlib-container — the app's inflate expects raw DEFLATE. When streaming with
`compression_stream`, let the framework advance `src_ptr`/`src_size` through a
STABLE source buffer; only refill when a chunk is fully consumed. Re-binding
the source pointer every iteration silently corrupts well-compressing data
(passed on a high-entropy sample, failed on the real DB) — verified the fix is
byte-identical to the original + `PRAGMA integrity_check ok` end-to-end on the
tvOS simulator.

**Consequences**: a new app build is required to consume `.zz`; the
uncompressed `catalog.sqlite` asset stays published until older builds age out,
then can be dropped. The `.gz` asset is retired.

---

## 020 — Catalog-mutating builds must be additive (merge-guarded), never replace
*Date: 2026-06-03*

Any workflow that REBUILDS rather than incrementally enriches the catalog must
union its output INTO the fetched full catalog and abort if the result would
shrink — it may never publish a from-scratch build as the whole catalog.
`rebuild-catalog` now runs `tools/merge_catalogs.py` after `build-catalog.mjs`:
the merge keeps every existing item (with its accumulated enrichment), only ADDS
items the catalog lacks, refreshes the `shelves` assignment, and exits non-zero
if `merged < base`. The weekly cron stays (it seeds new Wikidata films + refreshes
shelf assignments — part of the autonomous pipeline); the merge is what makes it
safe.

**Why**: `build-catalog.mjs --seed-from-wikidata` writes a FRESH ~1.1k catalog
(Wikidata seed + per-shelf query results) and overwrites `catalog.json`. On
2026-06-03 a run published that 1.1k straight over the full ~30k catalog, and
`publish-db` rebuilt the app DB from it. Because the catalog lives on a Release,
not git (Decision 018), there was NO diff to catch it — the safety net that
normally flags a 95 MB / 155k-line change is gone by design. A generated
accumulator with no line-diff review needs a structural guard instead.

**How to apply**: never let a build step's output BE the published catalog. Fetch
the full catalog, run the build, then `merge_catalogs.py base overlay out` (which
is enrichment-preserving: it does NOT overwrite a base item's fields, only adopts
its refreshed `shelves`, so a TMDb-only rebuild can't strip OMDb/Commons/Wikipedia
data the daily/weekly crons accumulated). The catalog GROWS via discover-content +
ingest; `rebuild-catalog` only seeds + refreshes shelves. If you add a new
catalog-mutating workflow, it must fetch → mutate-in-place → remediate → publish,
never rebuild-and-replace.

**Consequences**: the catalog is recoverable even without git line-diffs — see
`docs/runbooks/catalog-recovery.md` (dangling pre-Decision-018 git commit via the
activity API; or the simulator's cached `catalog.sqlite`). The 2026-06-03 loss was
fully recovered (30,645-item pre-018 commit `5ef1795`), so the merge guard is the
permanent fix, not the recovery.

---

## 021 — Stream Archive video through a custom AVAssetResourceLoaderDelegate
*Date: 2026-06-03*

Playback routes every Archive/LoC progressive MP4 through `ResilientStreamLoader`
(an `AVAssetResourceLoaderDelegate` on a custom `aw-stream://` scheme) instead of
handing the `https` URL straight to `AVPlayerItem`. The loader serves
AVFoundation's byte-range requests with short-timeout (12s), 2 MB chunked range
GETs over our own `URLSession`, retrying and RESUMING from the exact byte offset
on any timeout/reset. Non-HTTP URLs pass through untouched. Both player screens
retain the loader in `@State` (the `resourceLoader` delegate is held weakly).
`preferredForwardBufferDuration = 300s` and the artwork-via-`commonIdentifierArtwork`
Now Playing fix ride alongside it.

**Why**: on-device diagnostics (a temporary overlay that logged buffer + access-log
stats) proved the stalls were NOT a throughput or quality problem — observed
bandwidth was 18–84 Mbps for a 1.15 Mbps file and the forward buffer banked to
120–210s, yet playback stalled ~every 30s, going `ahead=140s → 0s` in one second
on each `nw_read` timeout / TCP `RST`. That is AVFoundation **flushing its entire
forward buffer when Archive resets the idle connection**, then re-downloading it;
one case never recovered at all. A bigger buffer cannot fix a flush-on-reset, and
lowering bitrate was explicitly rejected (highest quality is a product goal). Only
by owning the connection can a reset be handled as an invisible ranged re-request
instead of a buffer-discarding stall. Verified on real Apple TV hardware: 5
minutes on a previously-stalling title with zero stalls.

**How to apply**: build player assets via `ResilientStreamLoader.makeAsset(for:)`,
never `AVPlayerItem(url:)` for remote video. Keep the publish-time derivative
selection at HIGHEST quality (this decision makes high-bitrate files safe to
stream; do not add a bitrate ceiling). If you touch the loader, preserve: short
request timeout (a long one re-creates the original drain), resume-from-offset on
error (never restart at 0 — that re-introduces the flush), and `@unchecked
Sendable` state confined to its serial `queue`. `nw_read … Operation timed out`
lines in the console are now EXPECTED and harmless — they are our short timeout
firing before an instant resume; judge health by playback continuity / stalls, not
by their presence.

**Consequences**: AVFoundation's own networking (HTTP/2, its access-log
`observedBitrate`, transparent caching) is bypassed for video; the loader is the
sole network path for playback and must stay robust (seeks issue new range
requests; cancellation must stop in-flight tasks). This is the client-side
counterpart to keeping the source files full-quality — it does not change which
derivative plays.

---

## 022 — Sign in with Apple + CloudKit private DB for cross-Apple-TV sync
*Date: 2026-06-03*

Favorites, playlists, and watch progress sync across a household's Apple TVs via
**Sign in with Apple** (identity) + the **CloudKit private database** (storage).
No third-party/external auth. Sign-in is OPTIONAL and gates ONLY sync — browsing
and playback work fully signed-out. Implemented as `AccountStore`
(AuthenticationServices) + `CloudKitSyncService` (gated by
`CloudSync.entitlementConfigured`, default false, so the simulator build stays
clean until the owner adds the iCloud + Sign in with Apple capabilities — see
`docs/runbooks/cloudkit-setup.md`).

**Why**: this reverses the "all state local" half of Decision 009. The original
no-accounts stance was about removing trial friction; #11 (owner-requested) needs
the same favorites/progress on every Apple TV in a home. CloudKit's private DB
keeps that data in the user's own iCloud (we never see it), and Apple-native auth
avoids any contractual/privacy surface a third-party login would add — consistent
with the free, no-funnel ethos (Decisions 009/010). The Top Shelf App-Group
"no-op until configured" pattern proved a capability-gated feature can live in the
tree without breaking sim builds, so sync ships the same way.

**How to apply**: never add a non-Apple login. Sign-in must stay optional —
nothing in browse/playback may require it. New synced user-state must be added to
`CloudKitSyncService` (push + pull) AND the SwiftData schema. Keep the gate
(`entitlementConfigured`) the single switch; don't call `CKContainer` outside the
service. v1 is union/upsert + last-writer-wins; deletion propagation + live
refresh are #11b.

**Consequences**: the SwiftData store (`Favorite`/`Playlist`/`WatchProgress`)
gains a CloudKit mirror; a future iOS/web companion could read the same private DB.
Privacy manifest may need a data-collection note once sync is enabled (it stays in
the user's iCloud, but document it).

---

## 023 — Frame-extracted covers are hosted on an archive.org item, wired as generated art
*Date: 2026-06-05*

Items with no third-party poster (every vintage commercial, plus the long tail of
features/silents/animation enrichment missed) get a cover extracted from their own
video by the mac-based protocol (`tools/batch_covers.py` → `frame_cover.py`,
ffmpeg + opencv face/sharpness scoring). The JPEGs are uploaded to a single
**archive.org item, `archivewatch-covers`** (`tools/upload_covers.py`, IAS3 API),
giving each a stable public URL `https://archive.org/download/archivewatch-covers/
<slug>.jpg`. `tools/apply_covers.py` then sets the item's `posterURL`,
`artworkSource="generated"`, and `hasRealArtwork=true` in the catalog. Each cover
is a real still from the film — never hallucinated art. Full runbook:
`docs/runbooks/cover-generation.md`.

**Why**: 56% of the catalog (20,962 items, including all 2,390 commercials) had no
designed poster, falling back to the procedural typographic card. Commercials in
particular have NO third-party source that will ever cover them, yet they are the
backbone of the Channels EPG (Decision: commercials, 2026-06-05). Hosting was
chosen as archive.org (owner decision, 2026-06-05) over a GitHub Release or R2: it
is free, unlimited, durable, needs no per-image git/CDN budget, and is on-brand —
the app exists to celebrate the Internet Archive. The app fetches `posterURL` via
URLSession, so the `download/...` 302-to-storage-node redirect and the lack of a
CORS header are both non-issues (unlike the web tool, Decision 018).

**How to apply**: never commit generated covers to git or re-add them to the
catalog repo — the durable copies live on the archive.org item, indexed by
`tools/covers_out/uploaded.jsonl` (the working dir `tools/covers_out/` is
gitignored, like the catalog itself). IAS3 credentials live ONLY in the
environment (`IAS3_ACCESS_KEY` / `IAS3_SECRET_KEY`) or CI secrets — never in a
tracked file. New items from `discover-content` are covered by re-running the three
resumable stages (generate → upload → wire); each skips what it already did.
`artworkSource="generated"` is treated as real art by `build_sqlite.py` (it sorts
ahead of poster-less tiles on Home/Browse); if generated stills ever need to be
visually distinguished from designed marketing art, add a third artwork state
rather than special-casing `"generated"` at every reader.

**Consequences**: archive.org becomes a runtime artwork host for the app (read
path only). The generate stage is a ~1.5-day network-bound batch at full catalog
scale; it runs unattended on a Mac and is fully resumable. A CI workflow to
automate the three stages for newly-ingested items is deferred until the IAS3
secrets are added to the repo.

---

## 024 — Cover frames are selected on-device with Apple Vision, not a paid API
*Date: 2026-06-05*

The best frame for a generated cover (Decision 023) is chosen by
`tools/CoverScorerCLI` — a macOS Swift package (adapted from BOBA-Playbook's
`CardRecognitionCLI`) that runs the **Apple Vision framework on-device**: OCR text
coverage, face count + size, and Apple's image aesthetics score + `isUtility`
flag. `batch_covers.py` grabs N=16 frames per item and keeps the best frame Vision
does NOT reject (a frame is rejected if `isUtility` is true or text covers >12% —
i.e. a title card / intertitle / document / receipt-like image). It falls back to
the opencv heuristic only if the Swift binary isn't built.

**Why**: the opencv-only scorer had two failure modes a quick audit caught — it
false-ACCEPTED a textured sepia document (the Nosferatu "Bill of Lading"
intertitle, whose grayscale histogram is too spread for a flat-card rule to catch)
AND false-REJECTED good frames (the crab-temple silent, which actually has
aesthetics ~0.47 scenes, came back empty). Pixel heuristics can't reliably judge
"is this a good movie-poster cover" or "is this a page of text." Apple's Vision
models can, and on a macOS box it is free, fast, fully on-device (no key, no
per-image cost, nothing leaves the machine), which beat the alternative of wiring
a paid vision API into the pipeline.

**How to apply**: build the scorer once (`cd tools/CoverScorerCLI && swift build
-c release`) before a generation run; the binary path is
`tools/CoverScorerCLI/.build/release/coverscorer` (the `.build/` dir is
gitignored). Keep the reject rule (`isUtility || textCoverage > 0.12`) as the
text-card / document guard — do NOT re-add the opencv dominant-tone rule as the
primary gate (it misses textured documents). The CLI is generic: it takes image
paths and emits per-image JSON (textCoverage, faceCount, faceMaxArea, aesthetics,
isUtility, score, reject), so it can score any candidate set, not just covers.
Aesthetics needs macOS 15+; faces + text work on macOS 14.

**Consequences**: a generation run now requires a built macOS Swift binary, so the
full batch is macOS-only (the opencv fallback keeps a Linux CI path alive at lower
quality). Vision adds ~1s/item, negligible against the network-bound frame grab.

---

## 025 — Color vs B&W is classified from video frames (ffmpeg saturation), stored as `colorMode`
*Date: 2026-06-07*

Every catalog item gets a `colorMode` ("color" | "bw", nil = unclassified) derived
from its ACTUAL video by `tools/classify_color.py`: sample ~3 frames across the
runtime with ffmpeg `signalstats` and average SATAVG (mean chroma saturation).
B&W footage — silent or sound — reads ~0; color reads ~15–25, so a threshold of 8
splits them cleanly. The flag rides in `catalog.json` → `item_json` → the Swift
`Catalog.Item` (no SQLite schema change; CatalogDB decodes the full JSON). First
consumer: Cartoon Mode prioritizes `isColor`, Party Play drops `isBlackAndWhite`;
it also enables a future color/B&W Browse filter or badge.

**Why**: "prioritize color cartoons" (and color party content) needs a real
color signal. There is none in TMDb/OMDb for most PD titles, and the year/keyword
heuristic we shipped first is only a guess (a 1945 B&W cartoon outranks a 1935
color one). Measuring the frames is authoritative and cheap: ffmpeg `signalstats`
gives a per-frame saturation average, and on a calibration set the separation was
decisive (Night of the Living Dead 1968 → 0.0; Carnival of Souls 1962 → ~0;
Santa and the Three Bears 1970 → ~22; Sita Sings the Blues 2008 → ~22). Frame
analysis (not poster analysis) is required because B&W films often shipped
colorized posters.

**How to apply**: don't reintroduce a year/keyword color guess as the primary
signal — it stays only as the fallback for items not yet classified. New ingests
are covered by re-running `classify_color.py` (resumable: it skips items that
already have `colorMode`); the `color-classify.yml` workflow does a bounded pass
daily, and the full first pass is run locally under `caffeinate` (network-bound,
like the cover pipeline). Keep the threshold at ~8 — a heavily sepia-TINTED
silent can exceed it and read "color"; that's an accepted edge case (tinting is
a color cast), not a bug. `colorMode` is optional everywhere so older catalogs/
builds decode unchanged.

**Consequences**: ffmpeg becomes a build-time dependency for this tool (already
used by the cover pipeline). A full classification pass touches every playable
item once. If a true tri-state is ever needed (color / bw / tinted), extend the
string rather than special-casing "bw" at every reader.

---

## 026 — External matches are verified against the Archive item's OWN signals
*Date: 2026-06-07*

`tools/verify_external_match.py` re-checks every TMDb/OMDb-matched item against
the signals the matcher SHOULD have used, in priority order, and re-resolves or
clears wrong matches: Tier 1 = the Archive `external-identifier` `urn:imdb:tt…`
(authoritative — re-resolve to it via OMDb if the stored id differs); Tier 2 =
the Archive `date`/`year` (re-resolve by title+year, or clear and keep the
Archive year, when it disagrees with the matched year by >2); Tier 3 = the color
flag (Decision 025) — a frame-verified B&W film matched to a modern (>=1970)
release is wrong → clear. Items with no contradicting signal are left untouched.
Runs weekly in CI (`verify-matches.yml`), resumable via a `matchVerified` marker.

**Why**: wrong matches (the 1946 B&W Welles "The Stranger" showing the 2025
film) come from enrichment matching by fuzzy TITLE when the Archive record had no
year to constrain on — a title-only search returns the most popular/newest film.
Investigation showed the broken items' Archive records are often nearly empty
(no year, no id), so title-only matching was doomed; ~71% of matched items DO
carry an Archive `date` and ~14% an Archive IMDb id, and those matched correctly.
The fix is corroboration-required matching anchored on the Archive item's own
truth + the video's color, not popularity. Verified high-precision: on 20 popular
items it cleared 0 (no false positives); the Welles item resolves to `cleared_bw`
once classified.

**How to apply**: don't trust a title-only external match — adopt one only when
the Archive IMDb id, the Archive date, or the color era agrees. New
enrichment/match tools should consult `archive.org/metadata/{id}`
external-identifier + date BEFORE a fuzzy title search. The verifier marks
`matchVerified` (an extra JSON key the Swift model harmlessly ignores); a changed
match is re-checked by a `--refresh` run. OMDb is only called to re-resolve a
wrong match, so it stays within the daily quota (401 is handled — the item is
left unmarked and retried).

**Consequences**: a per-item Archive metadata fetch is the bulk cost (bounded per
CI run). This complements, not replaces, `tmdb_verify_matches.py` (#75, which
compares the stored tmdbID's canonical TMDb title) and the internal cleaners in
`remediate_catalog.py`.

---

## 027 — Copyright rights audit: hide modern non-PD titles behind a reversible `excluded` flag, confirmed by the Archive's OWN licenseurl
*Date: 2026-06-08*

Before the first App Store submission, `tools/audit_rights.py` buckets every
catalog item by how confidently it can be called public domain and HIDES the ones
that are likely still under copyright by setting a reversible `excluded: true`
flag (the item stays in `catalog.json`; `build_sqlite.py`, the bundled seed
selection, and `build_catalog_index.py` all skip `excluded` items, so they vanish
from every app/web surface but can be restored by clearing the flag). The risk
decision is anchored on the Archive item's OWN `licenseurl` (a network confirm
phase): a genuine `publicdomain/zero` (CC0) or `creativecommons.org/licenses/*`
dedication KEEPS a modern title; a bogus uploader-applied `publicdomain/mark`, a
bare/old PD claim on a post-1978 work, or no license HIDES it. The same fetch
reads the Archive `date` to re-anchor wrong-dated old films (Tier-2 of Decision
026) so they leave the risk set instead of being hidden. US year tiers: <1929
PD-by-age (keep); 1929–1963 presumed-PD per the Archive's curatorial stance
(keep); 1964–1977 renewal zone KEEP ALL (owner decision 2026-06-08 — this era is
full of genuinely-PD-by-notice-defect classics like *Night of the Living Dead*,
and absence of a license tag on a 1960s film is NOT proof of copyright); >=1978
confirm-then-hide. Commercials are a separate surface: modern brand ads (year
>=1995, owner decision) and screen-recording/rip/compilation slop are hidden
regardless of an uploader's PD/CC0 claim (a CC0 tag on a Coca-Cola ad is
worthless). Every apply emits `tools/rejected_audit.csv` — a per-item manifest
(Archive URL, stored year, Archive date, license, colorMode, downloadURL,
evidence) with a `SUSPECT_old_video` flag on any hidden item the Archive itself
dates pre-1978 or that is B&W with no corroborating date, so a wrong hide can be
caught by review.

**Why**: 96% of the catalog was labelled `public_domain`, but 7,400+ items dated
>=1978 carried that label wrongly — uploaders routinely slap a "Public Domain
Mark" on copyrighted studio films (verified: "The Peanuts Movie" 2015,
"Nosferatu" 2024, "Azaad" 2025). Shipping those is a copyright-infringement and
App-Store-rejection risk. Catalog-only signals can't separate a genuine
creator-dedicated PD film (Sita Sings the Blues = real CC0) from a bogus claim —
the Wikidata-"flagged" PD set was full of copyrighted slop (Mr Bean complete
series, hololive clips) sitting next to Sita. The Archive item's own `licenseurl`
is the only authoritative signal, and the CC0-vs-PD-Mark distinction is decisive:
on a 60-item sample only ~10% of modern PD-labelled items had a real CC0/CC
license. Removal is a flag (not a delete) because Decision 020 requires
catalog-mutating steps to be additive/reversible, and because mis-hides must be
recoverable for an App Store reviewer's spot-check.

**How to apply**: never hard-delete a rights-flagged item — set `excluded=true`
(reversible). A modern (>=1978) PD-labelled item may only be KEPT with a real
CC0/CC `licenseurl`; "PD Mark"/bare-PD/no-license on a post-1978 work is NOT a
rescue. NEVER hide 1964–1977 wholesale (owner policy). Trust the Archive's own
`date`/`licenseurl`/`external-identifier` over a fuzzy title match. New ingests
are covered by re-running `audit_rights.py --confirm` (resumable via
`rightsConfirmed`) then `--apply`; wire it after enrichment in CI, before
`build_sqlite`. Always review the `SUSPECT_old_video` rows of
`tools/rejected_audit.csv` before publishing — a B&W or Archive-old hidden item
is probably a wrong match that should be re-dated and kept, not removed.

**Consequences**: the published DB and seed shrink by the hidden count (well
above the app's 10 MB validity floor — safe). `excluded`/`rightsConfirmed`/
`archiveLicense`/`archiveDate`/`rightsAudit` are additive JSON keys the Swift
model ignores. This is the rights complement to Decision 026 (match correctness):
026 makes a match point at the right film; 027 decides whether that film may ship.

---

## 028 — Expand to iOS / Web / Android as fully-native apps over the SAME data plane; per-ecosystem sync on the user's own cloud
*Date: 2026-06-09*

Archive Watch goes multi-platform (iOS, then iPad, then Web PWA, then Android)
following the TriAppTemplate model: **feature parity, not design consistency** —
each platform is fully native (iPhone feels like iOS, Android like Material 3, web
like the web), NOT the tvOS UI shrunk down. All clients consume the **same shared
data plane unchanged** — the `catalog.sqlite` on the GitHub Release (+ editorial
JSON + the Python pipeline with rights/adult flags baked into the DB) — and rebuild
only the UI + query/player/persistence layer per platform. Each platform reads the
catalog natively: **iOS reuses the tvOS Swift `CatalogDB`/loader/`ResilientStreamLoader`
verbatim** (~60–70% reuse, and shares the Apple TV's CloudKit DB); **Android**
downloads + raw-inflates + queries via Room/SQLite, Media3 for playback;
**Web** queries the SQLite *in place* over HTTP **range requests** (`sql.js-httpvfs`,
FTS5, no full download) from GitHub Pages as an installable PWA. Sync is **three
independent islands, each on the user's OWN cloud, with no separately-run backend**:
Apple via CloudKit (iCloud), Android+Web via the **Google Drive "App Data" folder**
(Sign in with Google). No cross-ecosystem sync. Full plan: `docs/MULTIPLATFORM-PLAN.md`;
live matrix: `PARITY.md`.

**Why**: the app already has a clean seam — a platform-agnostic data plane vs a UI
layer — so the cost of a port is the UI, not the backend or the 30k-item catalog
pipeline. Native-per-platform (vs a cross-platform framework like Flutter/RN/Compose
Multiplatform) is required because the tvOS work proved native idioms (focus engine,
Liquid Glass, Material, web URL-state) carry the experience; a lowest-common-
denominator UI would degrade all three. iOS first maximizes reuse and gives free
iPhone↔Apple TV sync. The owner explicitly rejected a neutral sync backend
(Cloudflare/Supabase) as unneeded complexity and wants per-ecosystem sync only;
routing each ecosystem through the user's own free cloud (iCloud / Google Drive App
Data) delivers that with zero server to run — the Drive App Data folder is the exact
no-backend analog to CloudKit's private DB.

**How to apply**: never make the tvOS app the canonical UI to reskin — build the
native idiom per platform (`PARITY.md` "same verb, native idiom"; create
`docs/{iOS,WEB,ANDROID}-DESIGN.md` binding docs per platform once each passes ~5
views). Never re-implement or re-host the catalog/pipeline per platform — consume
the one published `catalog.sqlite` + JSON (author `docs/CATALOG-CONTRACT.md` as the
shared schema). Never stand up a custom sync backend — sync via the user's own cloud
(CloudKit / Drive App Data), sign-in optional and gating only sync (browse/play work
offline-first). Update `PARITY.md` in the same change set as any user-facing feature.

**Consequences**: the repo adopts the TriApp sibling layout (`ios/` UI alongside the
shared Swift Core, `android/` module, web at root). A Google OAuth client (public
ID, no secret backend) is the only new infra, shared by Android + Web. The publish-db
CI already emits the single asset all four clients consume; no pipeline change. New
per-platform binding design docs + a catalog-contract doc + small project skills
(`web-catalog-data-layer`, `media3-resilient-streaming`) are the authoring backlog.

---

## 029 — Web viewer data plane: catalog-index + metadata API now; chunked SQLite via Actions-deployed Pages later
*Date: 2026-06-09*

The consumer web viewer (`/watch/`) reads the catalog from `catalog-index.json`
(GitHub Pages, CORS, ~2.9 MB popularity-sorted tuples — extended to schema 2
with a designed-poster column) plus the archive.org `/metadata` API (CORS) for
detail + playable-derivative resolution at view time; posters and video load
through `<img>`/`<video>` elements, which need no CORS. It does NOT query the
published `catalog.sqlite` over HTTP range requests yet.

**Why**: measured 2026-06-09 — GitHub Pages serves `206 + Access-Control-Allow-
Origin: *` on ranged GETs (the 2026-06-02 "no 206" finding was a HEAD artifact),
so `sql.js-httpvfs` IS viable, but only for a DB hosted **on Pages**, and Pages
serves from git: committing the ~124 MB (or even a slimmed/chunked) SQLite per
daily publish re-creates the exact repo bloat Decision 018 purged. The other
hosts both fail the browser: GitHub Release assets range-serve with **no CORS**,
and archive.org `download/` storage nodes likewise send no CORS on `fetch()`.
The index + metadata-API plane needs zero new infrastructure and zero owner
action, so the viewer ships now at full visual dignity (designed poster art via
the index) with title search, at the cost of FTS5 search and enriched synopsis.

**How to apply**: never `fetch()` Release assets or `archive.org/download/*`
from browser JS — they will fail CORS (media/img elements are exempt). Don't
commit any SQLite to git for the web. The upgrade path (FTS5 search, cast,
enriched synopsis, Channels-grade queries on web) is: switch the repo's Pages
source to **GitHub Actions**, have `publish-db` deploy the site + a slim
chunked `catalog.sqlite` as a Pages artifact (nothing in git), and query it
with `sql.js-httpvfs`. That flip is one owner click (Settings → Pages →
Source: GitHub Actions) plus a deploy job — see `docs/WEB-DESIGN.md` §2.4.

**Consequences**: until the upgrade, web search is client-side title-substring
over the index, and the index (already committed on every publish) carries a
poster column (schema 2; schema-1 rows still decode — additive rule). The
viewer's share URLs `/Archive-Watch/item/{id}` are now real (404.html forwards
into the hash router), which retroactively makes the Share buttons shipped in
the iOS/tvOS apps land somewhere meaningful.

---

## 030 — archivewatch.org is the site root: viewer at /, editorial tool at /curate/
*Date: 2026-06-10*

The repo's GitHub Pages site now serves the custom apex domain
**archivewatch.org** (owner purchased + configured it; `CNAME` committed), and
the site was restructured around it: the consumer web viewer moved from
`/watch/` to the **site root** (`index.html` + `watch.js`/`watch.css`/`sw.js`/
`manifest.json` at `/`), and the curator dashboard moved from the root to
**`/curate/`** (its pages reference the shared `/css`, `/js`, `/assets` with
`../`, and `js/app.js` fetches `featured.json`/`catalog-index.json`
root-absolute). `404.html` forwards `/item/{id}`, `/series/{id}`, and legacy
`/watch/*` (old PWA installs arrive there via GitHub's 301 from
`bhwilkoff.github.io/Archive-Watch/*`, hash intact) into the viewer's hash
router. App share URLs now emit `https://archivewatch.org/item/{id}`;
`SeriesStore` fetches spines from `archivewatch.org/series/`.

**Why**: the product IS "watch Archive.org on the web" — the viewer earns the
front door, and a memorable apex domain beats a project-page path. The
restructure also unblocks what the project-page URL could never do: a root
custom domain can serve `/.well-known/apple-app-site-association`, so
**Universal Links** (blocked since the iOS wave) become possible — the AASA
for `L2G756LY8N.app.archivewatch.tvos` (`/item/*`, `/series/*`) now ships on
the site. Old URLs keep working: GitHub 301-redirects every
`bhwilkoff.github.io/Archive-Watch/<path>` to `archivewatch.org/<path>`, and
the 404 forwarder maps retired paths, so links shared from already-installed
apps never break.

**How to apply**: new share/canonical URLs are always
`https://archivewatch.org/...` — never the github.io form. Anything that
serves from Pages is reachable at the apex (`featured.json`, `series/*.json`,
`catalog-index.json`); native apps may keep `raw.githubusercontent.com` for
git-pinned fetches. Don't move the viewer's data files out of the repo root —
the curate tool and viewer both resolve them root-absolute. The viewer's
service worker must skip `/curate` (the tool stays uncached/live). Completing
Universal Links needs the owner to add the **Associated Domains** capability
(`applinks:archivewatch.org`) to the iOS app in Xcode/the developer portal —
deliberately NOT added to the entitlements here to avoid breaking the
in-flight signing; the AASA is already live and validated once that lands.

**Consequences**: the App Store listing's marketing/support URLs
(`docs/app-store-listing.md`) should be updated to archivewatch.org in ASC;
GitHub Pages enforces HTTPS for the domain (owner should leave "Enforce
HTTPS" on); `www.archivewatch.org` behavior depends on the owner's DNS
(CNAME www → apex recommended).

---

## 031 — Stream loader delivers bytes as they arrive and pins the storage node
*Date: 2026-06-11*

`ResilientStreamLoader` (Decision 021) now (a) delivers every arriving Data
slice straight to AVFoundation via a per-task `URLSessionDataDelegate`
(`ChunkStream`) instead of buffering whole chunks with `session.data(for:)`,
(b) pins the post-redirect archive.org storage-node URL after the first
response and requests it directly, dropping the pin on failure so the next
attempt re-resolves through the origin, and (c) uses 8 MB ranges instead of
2 MB.

**Why**: the owner reported 1–2 stalls per film (sometimes a dozen) even with
the Decision-021 loader. Measured 2026-06-10: every chunk paid the
`archive.org/download` 302 round trip (~0.5–1.0 s extra time-to-first-byte vs
the node directly), the player received ZERO bytes until each 2 MB chunk
completed (so the buffer grew in steps with multi-second gaps), and a mid-chunk
timeout discarded the partial chunk and re-downloaded it — each such event a
multi-second hole in buffer feed. Same title, same network, before → after:
in-chunk throughput 8.7 → 34.9 Mbps, per-chunk turnaround 2.6 s/2 MB →
0.9 s/8 MB, 100% of requests on the pinned node, and the 300 s forward buffer
fills in seconds instead of plateauing. Streaming delivery also makes failure
recovery byte-exact: `offset` advances with each delivered slice, so a retry
resumes at the exact byte and AVFoundation never sees a gap.

**How to apply**: keep delivery STREAMING — never go back to whole-chunk
`session.data(for:)` (it holds bytes hostage for the chunk duration and makes
every failure cost the whole chunk). Keep the pin-and-fallback shape: nodes
rotate/expire, so a failed pinned request must clear the pin and retry via the
origin before burning the retry budget (416 means ranged-past-EOF → clean
finish, not an error). All Decision-021 invariants still bind: short idle
timeout, resume-from-offset, queue-confined state, no bitrate ceiling.
Diagnostics are permanent but env-gated (`AW_PLAYBACK_DIAG=1` logs AWSTREAM
chunk/retry/pin lines, AWSTALL stall events, AWBUF buffer depth; `AW_AUTOPLAY=1`
+ `AW_START_ITEM` drive unattended playback runs on the simulator).

**Consequences**: requests per film drop ~4× (fewer chances to hit an idle
reset); startup metadata reads go from ~1.5 s to ~50 ms once pinned. The
pinned URL lives only for the loader's lifetime (one playback session), so
node rotation between sessions is harmless.

---

## 032 — Title-first PD discovery: a metadata-sourced wants list hunted on archive.org
*Date: 2026-06-12*

Discovery gains an INVERTED direction: `tools/discover_pd_wants.py` enumerates
films the metadata world says are public domain or lost-copyright — Wikipedia's
curated "List of films in the public domain in the United States" (each row
carries the year AND the lapse reason: not renewed / no notice / dedicated),
TMDb `/discover` for everything released before the rolling US PD-by-age cutoff
(`current year − 95`, popularity-first), and Wikidata films published before the
cutoff that have an IMDb id but no P6216 flag — and queues each title we don't
already hold as an `iaid`-less candidate in `shared/editorial/
discovery_candidates.json`. The EXISTING ingest step then hunts archive.org for
each want by title+year (`archive_lib.resolve_title`), confirms a playable
derivative, and ingests through the same enrichment / match-verify / rights
gates as every other item. Wired into `discover-content.yml` ahead of ingest;
per-run report at `shared/editorial/wants_report.csv`.

**Why**: every prior feed walks archive.org-first (collections, scrape, Wikidata
P724) and so can only find what Archive's own metadata surfaces — obscure or
badly-labelled PD uploads stay invisible. Going metadata-first flips the search:
a curated/derivable list of titles KNOWN to be free (the renewal-failure canon,
PD-by-age) hunts the Archive for copies, and every want arrives with identity
attached (IMDb/Wikidata/TMDb ids), so the match is corroborated per Decision 026
and enrichment is instant — "impeccable metadata" from the moment of ingest.
First full run validated the approach AND the back catalog: 125 of the 126
curated Wikipedia US-PD films were already held.

**How to apply**: new wants sources (other curated PD lists, registries,
national-archive catalogs) belong in this tool as feeds, not as new pipelines —
emit into the same candidate queue and let ingest/audit do the rest. A want must
carry at least title+year and ideally an external id; never queue a bare title.
`PD_YEAR_CUTOFF` is computed, not hardcoded — don't pin it. The Wikipedia list
parse keys on table rows that lead with a wikilink and carry a year column; if
the page's table format changes, fix the parser rather than switching to a
category crawl (the "films in the public domain" CATEGORY does not exist —
verified 2026-06-12).

**Consequences**: the candidate queue can now contain wants whose Archive copy
doesn't exist yet — `status="unresolved"` marks a miss and is never retried
daily; a periodic `--retry-unresolved` sweep (future) could re-hunt as new
uploads appear. The rights gate stays Decision 027's audit — a want's
`pdEvidence` documents the nomination reason but never bypasses confirmation.

---

## 033 — Clip Studio: native on-device clip/GIF/fan-edit creation differentiates the phone apps
*Date: 2026-06-16*

The native iPhone/iPad app gains **Clip Studio** — a rights-gated editor,
launched from a scissors "Create" button on Detail, that trims a public-domain
archive.org film, reframes it for social (1:1 / 9:16 / 16:9), burns in a
user caption plus an always-on `archivewatch.org · Public Domain` provenance
credit, and exports an MP4 or looping GIF to Photos / the share sheet. The
processing engine is **100% native frameworks** — AVFoundation
(`AVMutableComposition` + `AVMutableVideoComposition` + `AVAssetExportSession`),
ImageIO (`CGImageDestination` for GIF), PhotoKit, `AVAssetImageGenerator` — with
the Android port on Media3 `Transformer`. The shared engine lives in
`Services/ClipExporter.swift` guarded `#if os(iOS)`; the editor UI is
`iOS/ClipStudioView_iOS.swift`. **tvOS and web stay lean-back viewers** — no
editing affordance (no text entry / direct-manipulation timeline at ten feet or
in a viewer-only PWA). Full plan: `docs/CREATE-STUDIO-PLAN.md`.

**Why**: phones are creation devices, not just consumption screens — the owner's
brief is to differentiate the native phone apps from the tvOS/web viewers by
turning the public-domain catalog into raw material for "fan edits." This passes
the learning-orientation test (CLAUDE.md) — it invites participation and
deepens engagement with archival film — **on one condition: do not ship a
one-tap "auto fan-edit" generator.** The editorial cut is the meaningful human
act; automating it strips the learning. So the rule is *automate the mechanical
(frame extraction, encoding, reframe math, attribution generation), preserve
the meaningful (which moment, what caption, where to cut)*. The distinctive
wedge is auto-generated provenance credits — turning the Internet Archive's
attribution norm into a culturally-native feature.

**How to apply**: clipping is offered ONLY for `Catalog.Item.isClippable`
(playable video + PD/CC/absent rightsStatus; explicit copyright/`unknown` is
not clippable) — defense in depth over Decision 027's upstream exclusion. The
affordance is HIDDEN, not disabled, when not clippable. Editing operates on a
LOCAL file (download to `Caches` first — the editor needs a complete
`moov`-bearing file, not the play-as-you-go `ResilientStreamLoader` range
stream); v2 should range-download just the clip window keyed on the moov index
instead of the whole film. Every export burns the provenance credit and embeds
the `archive.org/details/{id}` source in `AVMetadataItem`s — never remove that.
New craft tools (stitch, transitions, speed ramps, LUT grade, `SpeechAnalyzer`
auto-captions) are ADDITIVE on the same `AVMutableComposition` /
`AVMutableVideoComposition` spine — do not rebuild the engine for them.

**Native-first note** (`native-platform-first`): the engine and every UI
surface use native primitives (AVKit `VideoPlayer`, `Picker(.segmented)`,
`TextField`, `ShareLink`, PhotoKit, `.sheet`/`.toolbar`/`ProgressView`). The
ONE custom element is the trim timeline (filmstrip + drag handles), because
neither Apple nor Google ships a reusable timeline-trimmer:
`UIVideoEditorController` is trim-only / quality-preset-only / UIKit-modal and
can't host reframe+caption+GIF, and Media3 ships only a demo editor UI. Apple's
own editor sample code builds the timeline custom on AVFoundation — so custom
here is the platform-endorsed path, kept thin (it only positions handles over
native thumbnails and seeks a native player). Re-evaluate on each major OS
release in case a reusable trimmer ships. `UIVideoEditorController`-for-trim
remains a one-screen swap if a strictly-native trim bar is ever preferred.

---

## 034 — Stream loader fails over across Archive storage nodes
*Date: 2026-06-18*

`ResilientStreamLoader` now fetches an item's storage-node list from
`archive.org/metadata/{id}` (the chosen `server` + `alternate_locations.workable`
nodes), and on a HARD node failure (5xx/403/404) it blacklists that node's host
and switches its range requests to a healthy known node directly, instead of
re-resolving through the origin's `/download/` 302 (which load-balances and can
re-pin the same bad node). The metadata fetch is best-effort and one-time per
loader; if it fails, `alternateBases` stays nil and behavior is byte-identical to
Decision 031 (origin 302 + pin-from-redirect). When every known node has been
blacklisted, the set is cleared so playback never deadlocks. All new state
(`failedHosts`, `alternateBases`) is confined to the loader's serial `queue`.

**Why**: owner report "Niagara Falls (1941) doesn't play at all." Measured
2026-06-18: archive.org was actively rotating that item across storage nodes and
load-balancing `/download/` between them — one node (`dn720409.ca`) returned 500
on ~3/5 byte-range requests while the primary (`dn600303.us`) served 5/5. The
Decision-031 loader pins whatever node the first 302 lands on and, on failure,
drops the pin and re-resolves through the origin — but the origin can re-pick the
degraded node, so recovery was a coin-flip per retry (and a full failed stream
attempt each time). Archive publishes the healthy alternates in its own metadata,
so switching to them deterministically is strictly better than re-rolling.

**How to apply**: a timeout/connection-reset is the EXPECTED Decision-021 idle
drop — do NOT blacklist a node for it (that would rotate away from a healthy node
on normal resets); only a 5xx/403/404 is a node-health signal. Keep the metadata
fetch best-effort and OFF the first-byte critical path (it's kicked off async from
the content-info probe; the probe itself still uses the origin so first-play
latency is unchanged). Preserve every Decision 021/031 invariant: short idle
timeout, resume-from-offset, streaming delivery, no bitrate ceiling,
queue-confined state. Diagnostics stay env-gated (`AW_PLAYBACK_DIAG=1` →
`AWSTREAM alternates:` / `AWSTREAM node … failed … rotating`). Needs on-device
validation (living-room Wi-Fi, real node weather) before it's considered proven —
the dev box can't reproduce archive.org's load-balancer.

**Consequences**: playback issues one extra `/metadata` GET per play session
(cheap, parallel to the probe). The loader is now resilient to a single bad node
without waiting out the retry budget; the remaining failure mode is ALL nodes
degraded (rare, mid-rotation), which clears the blacklist and falls back to the
origin coin-flip as before.

---

## 035 — Hide orphaned TV-episode duplicates; clear unanchored episode posters
*Date: 2026-06-18*

`tools/dedupe_orphan_episodes.py` (wired into publish-db, idempotent, no network)
hides standalone items that are DUPLICATES of an episode already mapped onto a
series spine: it sets a reversible `excluded=true` (+ `episodeDuplicate`,
`duplicateOf`) when an orphan (`tv-special`/`feature-film`, `seriesID` null) has
BOTH (a) a series identity drawn from its OWN naming — the multi-word series name
appears as a CONTIGUOUS phrase in the title prefix, the synopsis prefix (before
the first colon, near the start), or the archiveID slug — AND (b) a parsed
`(season,episode)` that is a FILLED slot in that same spine (held by a different
archiveID). The matched spine must be unambiguous. Separately, `remediate_catalog`
rule 0d now also clears `tvmaze`/`external`-sourced posters (not just
tvdb/tmdb/omdb) on unanchored items (no imdbID/tmdbID/year) — POSTER ONLY.

**Why**: owner report — "The Devil's Laughter" showed as a film with a foreign
film's poster. It's One Step Beyond S1E11, already correctly in the spine as
`S1E11THEDEVILSLAUGHTER`; the item shown was a SECOND upload
(`OSB-11_The_Devils_Laughter`) the canonical TV pipeline (Decision 016) never
mapped, so it floated as a `tv-special` (which `browseSQL` still surfaces in
Movies — it only excludes `tv-series`) carrying a title-matched TVmaze poster
(`artworkSource="external"` = "host we don't label", treated as real art). 412
orphan episode-like items exist. Matching them is a minefield: descriptions
cross-reference OTHER shows (a *Thriller* episode's synopsis mentions "One Step
Beyond"), generic "Pilot"/"Episode 1" titles collide across series, and
same-named FILMS vs SHOWS are different works ("The Lone Star Ranger" film vs
"The Lone Ranger"; "Man with a Movie Camera" vs "Man with a Camera"; "C-Man" vs
"The Man from U.N.C.L.E"). Token-subset series matching + title-only episode
matching produced 173+ matches riddled with false positives that would hide real
films. Requiring BOTH a contiguous-phrase series name from the item's own naming
AND a filled (S,E) slot collapses it to 7 confirmed, zero false positives.

**How to apply**: precision over recall — it is better to leave a duplicate
visible than to hide a real film. Do NOT loosen to token-subset series matching
or title-only episode matching (both conflate distinct works). Keep the
`_NOT_SINGLE` guard (promos/trailers/whole-season/multi-episode bundles parse a
spurious (S,E) and mis-map). Never hard-delete — `excluded` is reversible, and
the canonical episode stays in its spine so no content is lost. The deeper,
unsolved problem (orphan episodes whose series has NO spine, or whose (S,E) slot
is empty) belongs in the canonical TV pipeline (build/reconcile), not a blanket
exclude. Whether `tv-special` should appear in Movies browse at all is an open
IA question (binding-design-doc-discipline) — left to the owner.

**Consequences**: 7 confirmed duplicates hidden now; the step re-derives them
every build from `series/` + catalog, so new ingests are covered without a
persisted Release mutation. Complements Decision 016 (canonical TV), 026 (match
correctness), 027 (rights exclusion) — same reversible-`excluded` mechanism.

---

## 036 — TV never appears in Movies; orphan episodes fold into series spines
*Date: 2026-06-18*

Two coordinated changes make TV organize itself correctly instead of leaking
into Movies as standalone "films":

1. **Browse taxonomy (app):** `CatalogDB` now excludes BOTH `tv-series` AND
   `tv-special` from every film surface — Movies/Browse grid (`browseSQL`/
   `browseCount`), Home discovery shelves + director/quality rows (new shared
   `notStandaloneTV` clause), and Random Film (`randomPlayable`). `tv-special`
   is requestable ONLY explicitly, surfaced by a new "TV Specials" entry on the
   TV tab (`tvSpecials()` query → `BrowseFilter(category:"tv-special")`).

2. **Orphan fold-in (pipeline):** `build_canonical_tv.gather_raw_targets` now
   also pools episode-marked `tv-special`/`feature-film` orphans (no seriesID) —
   previously INVISIBLE to the builder, so they floated as standalone films.
   Each is pooled under its extracted SERIES name (for TVmaze resolution) while
   keeping its EPISODE title (for the mapper's SxE/fuzzy slotting), so it folds
   into a new or existing spine — creating a spine even for a show where we hold
   ONE episode. `dedupe_orphan_episodes` runs FIRST (tv-canonical) to exclude
   already-mapped duplicates so they don't pool as spine "extras"; reconcile now
   drops a folded item REGARDLESS of its old contentType (the episode_ids check
   moved out of the `tv-series`-only branch — a tv-special folded into a spine
   used to survive as a duplicate card).

**Why**: owner directive — "TV shows should never appear in Movies … every
single tv show that we have data for should organize into its correct
season/episode (even if it is only one) … rather than haphazardly," plus "look
for the other episodes in our regular wants scripts." Research found 2,306
`tv-special` orphans leaking into Movies; 269 are episode-marked (152 belong to
shows with no spine, 117 to existing spines). Identification is reliable: 11/13
sampled no-spine series resolved correctly to TVmaze. Crucially, the
episode-level wants engine ALREADY runs daily (`build_episode_wants.py` →
`episode_wants.json`, 14.6k wants, hunted by `backfill_tv_episodes.py`) but only
for shows that HAVE a spine — so folding orphans in automatically enrolls their
shows in episode-hunting (validated: Fu Manchu's 3 orphans → a new spine with
`canonicalEpisodesCount=13`, so wants generate for the missing 10). No new wants
engine was needed — the spine was the missing link.

**How to apply**: fold-in is CONSERVATIVE by owner decision — episode-marked
orphans only (`_orphan_is_episode`: SxE/NxNN/"Season N Episode M"); do not mine
unmarked tv-specials (many are genuine one-off specials, not episodes). Extract
the series name from the item's OWN naming (synopsis-prefix-before-colon, then
title-before-marker, then archiveID slug) — never a buried cross-reference. The
existing mismap guard (name-plausibility floor + identity-token overlap) and
`audit_series_episodes` still gate inclusion. Always run `dedupe_orphan_episodes`
before `build_canonical_tv` so duplicates are excluded, not folded as extras.
tv-specials that don't resolve stay `tv-special` and live in the TV Specials
grid — never Movies.

**Consequences**: the standalone `tv-special` set shrinks as orphans fold into
spines each weekly TV run; the residual genuine specials surface on the TV tab.
iOS/Android/web get the data-layer exclusion via shared CatalogDB-equivalents
but still need their own TV Specials surface (parity follow-up). Complements
Decision 016 (canonical TV) and 035 (duplicate exclusion).

---

## 037 — Player title+description overlay that fades with the transport controls
*Date: 2026-06-18*

The mobile + web players gain a title+description overlay (top scrim) that
appears and disappears IN SYNC with the playback controls. Each platform uses
its best native hook; tvOS is intentionally untouched (its native Info tab +
externalMetadata already satisfy the owner). Per platform:

- **Android** (`PlayerScreen.kt`): Media3 `PlayerView.setControllerVisibilityListener`
  — a public, exact controls-visibility callback drives a Compose
  `AnimatedVisibility` overlay. Text tracks the CURRENT item via a
  `Player.Listener.onMediaItemTransition` (binge updates on advance). Synopsis
  rides `MediaMetadata.setDescription`; `PlaySpec` gained a `description` field.
- **Web** (`watch.js`/`index.html`/`watch.css`): a `.player-overlay` over the
  `<video>`; HTML5 `<video controls>` exposes no visibility event, so
  `syncOverlay()` mirrors the SAME user-activity signal the browser uses
  (pointer/touch + a 3.2s timer; stays up while paused). Synopsis from
  `Details.get(id)`.
- **iOS** (`PlayerView_iOS.swift`): set `externalMetadata` on the AVPlayerItem
  (`commonIdentifierTitle` + `commonIdentifierDescription` + the empty
  creation-date overrides) — AVPlayerViewController then renders the title in
  its OWN chrome, shown/hidden WITH the transport controls, surviving load and
  recallable on tap. This is the Apple TV app's behavior and mirrors the tvOS
  player verbatim. A FIRST attempt used a custom `contentOverlayView` overlay
  with a tap recognizer + timer; it was WRONG (showed before load, faded on its
  own timer, and AVKit's gestures swallowed the tap so it couldn't be recalled)
  and was removed. `PlaybackQueue.next` returns title+description so the next
  episode's metadata is set on binge-advance.

**Why**: a title/description visible alongside the controls is a standard player
affordance the mobile + web apps lacked (the web title sat in a static header
bar; iOS showed nothing). Owner request 2026-06-18, scoped to "the mobile app
and the web app" — tvOS already does this natively and the owner likes it.

**How to apply**: NEVER replace the native transport. On iOS, do NOT build a
custom synced overlay (a `contentOverlayView` overlay + tap/timer was tried and
failed — see above); use the player's OWN chrome via `externalMetadata`, which
AVKit syncs to its controls for free (no private API, no KVO of control views).
On Android + web (which DO own a custom overlay over the surface), keep it
non-interactive (`pointer-events:none` / non-touchable) so it never blocks the
controls; Android has a true `setControllerVisibilityListener` event (prefer it),
web mirrors the browser's user-activity timer. Description text is clamped.
NOTE: `simctl` screenshots do NOT capture AVPlayerViewController's chrome — the
iOS title overlay can only be verified on a real device / Simulator UI, not via
automated screenshots.

**Consequences**: `PlaySpec` (Android) + `PlaybackQueue.next` (iOS) signatures
changed (additive/internal). Other Android `PlaySpec(` call sites (channels,
explore, series) pass no description yet — the overlay shows title-only there
until they're wired (follow-up). Per-platform binding docs to note the new
overlay surface.

---

## 038 — "Open in Callsheet" via the callsheet:// URL scheme (iOS only)
*Date: 2026-06-19*

The iOS/iPadOS app deep-links a title into **Callsheet** (the cast/crew
companion app) from an actions menu on the share button — Detail and
SeriesDetail (series + per-episode context menu). Uses Callsheet's public URL
scheme (callsheetapp.com/url-schemes): `callsheet://open/movie/{tmdbID}` /
`callsheet://open/tv/{tmdbID}` when we hold a `tmdbID` (47% of titles), else the
title-search fallback `callsheet://search/{movie|tv}?q={title}` (Callsheet
ignores the media type on search, so any nameable title resolves; episodes add
`&season=&episode=`). If Callsheet isn't installed, `UIApplication.open`'s
completion fires `false` and we open its App Store page (id1672356376) — the
native "get the app" fallback. Logic lives in `Callsheet` (CallsheetLink_iOS.swift).

**Why**: owner request + Callsheet's author (Casey Liss) endorsing the URL-scheme
approach over Shortcuts. Callsheet is iPhone/iPad ONLY, so this is an iOS feature
— tvOS/Android can't open it (no app), and a browser can't detect install or
fall back cleanly, so web is out. TMDB ids are required by Callsheet (no IMDb);
we already store `tmdbID`, and search covers the rest.

**How to apply**: keep it to films + TV (`Callsheet.supports` — newsreel/
ephemeral/home-movie/commercial have no Callsheet entry). We detect installation
with `canOpenURL("callsheet://")` to label the action "Open in Callsheet" vs "Get
Callsheet" and route accordingly — which REQUIRES `callsheet` in the Info.plist
`LSApplicationQueriesSchemes` array (added). Opening a scheme alone would need no
declaration; only the canOpenURL probe does. No App-Review/entitlement/portal
change is needed either way. Do not scrape or use undocumented
endpoints — only the published open/search scheme. Person deep-links
(`callsheet://open/person/{id}`) are possible but BLOCKED until the catalog's
`CastMember` carries a TMDB person id (today it stores only name + profilePath) —
a pipeline enhancement, not done here.

**Amendment 2026-06-23 (owner: "all apple platforms"):** the title "(iOS only)" is
superseded — Callsheet ships a Mac app, so the integration now ALSO lives in the
**macOS** target (`macOS/CallsheetLink_macOS.swift`, wired on Detail + SeriesDetail +
per-episode context menu). The macOS twin uses **`NSWorkspace`** instead of
`UIApplication`: `NSWorkspace.urlForApplication(toOpen: callsheet://)` is the
install probe (the AppKit analog of `canOpenURL`) and needs NO `LSApplicationQueriesSchemes`
entry on macOS (that array is an iOS privacy restriction); `NSWorkspace.open` routes the
deep link, falling back to the App Store page. The URL-building / supported-types /
search-vs-open logic is identical to iOS. Still excluded: tvOS (no Callsheet app) and web
(can't probe install or fall back cleanly).

---

## 039 — Subtitles: layered sources, side-loaded as tracks; archive.org ASR first
*Date: 2026-06-19*

Subtitles are delivered as a new additive `captions` field on each catalog item
(`[{lang, label, format, url, source}]`) that every client SIDE-LOADS onto the
progressive MP4 — never re-encoded into the video. Coverage is layered across
sources, cheapest/cleanest first:
1. **archive.org's own caption files** (`tools/enrich_subtitles.py`, Phase 1):
   most Archive video items ship auto-generated ASR captions (`<name>.asr.srt`)
   or uploader subs (`.srt`/`.vtt`, sometimes `Film.es.srt`). FREE, already
   hosted on the same item we stream, zero ToS/redistribution issue. Measured
   ~33% of films overall, ~73% of the most popular — the backbone.
2. **OpenSubtitles** by imdb/tmdb id (Phase 3): human-made, multi-language, for
   titles Archive didn't caption. Non-commercial use + a back-link are their ToS
   conditions — Archive Watch is free/non-commercial (Decision 010), so it fits;
   fetch on-demand (download caps) and attribute.
3. **Whisper-generated VTT** (Phase 4): fills the remaining gaps. We own the
   output (the films are public domain), so it's freely hostable like covers.

**Why**: owner wants robust coverage across all titles, multi-language, even via
multiple sources. No single community DB covers obscure PD films, but archive.org
already ASR-captions a large share for free, so it's the backbone; the others
layer on. Side-loading (not burning into video) keeps the highest-quality
derivative (Decision 021) untouched and lets the user pick a language.

**How to apply (per-platform mechanics — they differ a LOT)**:
- **Android** (Media3): EASY — `MediaItem.SubtitleConfiguration` side-loads SRT
  or VTT directly. Native.
- **Web** (`<video>`): EASY — a `<track kind="subtitles">`, but the element
  requires **VTT**, so convert SRT→VTT client-side (trivial: WEBVTT header +
  `,`→`.` in timestamps) into a blob URL.
- **Apple** (iOS/tvOS, AVPlayer): HARD — AVPlayer cannot side-load a sidecar
  `.vtt`/`.srt` onto a progressive MP4. The native path is to synthesize an HLS
  master playlist (MP4 variant + `EXT-X-MEDIA:TYPE=SUBTITLES` → a VTT subtitle
  playlist) via an `AVAssetResourceLoaderDelegate`. This COLLIDES with
  `ResilientStreamLoader` (Decision 021/031): going HLS hands the connection back
  to AVFoundation and loses the resume-on-reset resilience. So Apple subtitles
  need a careful design (e.g. a subtitle-only HLS layer that still streams the
  MP4 bytes through our loader) and on-device validation — deferred, NOT done in
  Phase 1. Don't naively swap the progressive MP4 for HLS.

Phase 1 (this entry): the pipeline + the `captions` schema on the Swift + Kotlin
models + the weekly `subtitles.yml`. The per-platform players (web `<track>`,
Android `SubtitleConfiguration`, the Apple HLS layer) are the next phases.

---

## 039a — Whisper auto-captioning runs in CI (sharded macOS), not on the owner's Mac
*Date: 2026-06-20*

Phase 4 of Decision 039 (whisper.cpp auto-captioning of uncaptioned PD films) is
amended to run as its PRIMARY venue in GitHub Actions
(`.github/workflows/whisper-subtitles.yml`) across N free **macOS (Apple-Silicon)**
runners, instead of as an unattended batch on the owner's Mac. The target list
(popularity-sorted, already-captioned-filtered) is split with `--shard-index/
--shard-count` across a matrix of `macos-15` runners; each shard runs `--workers 1`
under a `--max-minutes` budget (under the 6 h job cap) and uploads `subs/` + a
compact `--deltas-out` file as artifacts; a single dependent publish job merges them
and applies additively via `whisper_publish.py --apply-deltas` (so parallel shards
never clobber the shared `catalog-source` release). Head-first falls out of the
popularity sort; the long tail is drained by the weekly schedule. The script also
got gentle defaults for any LOCAL run: `--workers 1` (was 3), `--max-minutes`,
`--threads`, and docs to wrap it in `taskpolicy -b` with `ggml-base.en.bin`.

**Why**: Decision 039 specified "Mac-first, not in CI," reasoning whisper.cpp+Metal
is Apple-Silicon-only and the audio pull is bandwidth-heavy. But the owner's machine
is a **fanless 8 GB M3 MacBook Air**, and a `--workers 4` run (4 concurrent
whisper-cli + 4 ffmpeg + the 74 MB catalog held in-process) drove it into memory
pressure + sustained thermal load until it became unusable and **shut down** — only
29 of 22,835 films done. Two facts overturn the original reasoning: (1) this repo is
**PUBLIC**, so GitHub's macOS runners (Apple Silicon, Metal-if-available, else CPU)
are **free** within fair-use — the cost objection is gone; (2) the work is
embarrassingly parallel and bandwidth/heat is the runner's problem, not the Air's.
Offloading removes the resource event entirely while keeping the same additive,
resumable, head-first design. 22,835 films is also not finishable on the Air at any
gentleness, so a free fleet of runners draining it over weeks is the only realistic
path to broad coverage.

**How to apply**: scale whisper transcription by adding SHARDS (separate runners),
never by raising `--workers` on one machine — a single Metal GPU gains nothing from
concurrent jobs but pays multiplied RAM + heat (this is what crashed the Air). Keep
the publish single + additive (`--apply-deltas` from the merged shard delta files);
do NOT have each shard run `whisper_publish.py` independently (5 concurrent
fetch→clobber publishes race and drop deltas). If a LOCAL run is ever needed on a
small/fanless Mac, use `--workers 1`, a `--max-minutes` budget, `ggml-base.en.bin`,
and wrap the process in `taskpolicy -b` (background QoS → efficiency cores, machine
stays responsive). Validate any runner-side change with a tiny dispatch
(`-f limit=3 -f shard_count=1`) before a big batch — the job summary prints whether
Metal initialized vs CPU fallback.

**Consequences**: whisper Phase 4 joins the other catalog-writer crons; its publish
job uses `concurrency: catalog-writers` so the release apply serializes with them.
The bundled per-platform players (Decision 039) consume the resulting `captions`/
`subtitleHLS` unchanged. If GitHub's macOS runners turn out to lack Metal, the same
job still runs on CPU (slower, still free, still zero-load on the Air) — the workflow
does not hard-require GPU.

---

## 040 — Collapse same-film re-uploads into one best card (title + single-imdb anchor + runtime), grafting metadata
*Date: 2026-06-20*

`build_sqlite.merge_film_duplicates()` collapses multiple archive.org uploads of
the SAME film into ONE card and grafts the film-level metadata onto the survivor,
running after `dedupe_by_imdb`. It acts ONLY on normalized-title clusters that
contain EXACTLY ONE imdb id (the imdb anchors the film's identity); a no-imdb copy
joins the anchor only when year-compatible (|Δ|≤2) AND runtime-compatible (within
15% / 2.5 min). The survivor is the best **video + captions** copy (`_video_quality`
= qualityScore + filename resolution, demoting 512kb/ipod derivatives; captions are
the top tiebreak so the CC copy wins); the anchor's imdb / tmdb / year / director /
rating and the cluster's best artwork are grafted onto it. Multi-imdb clusters
(distinct films — Cleopatra, Oliver Twist adaptations) and all-no-imdb clusters
(generic titles — "Public Domain Animation" ×31) are LEFT UNTOUCHED. Replaces
`drop_noimdb_dupes_of_captioned`.

**Why**: the catalog holds many duplicate uploads of one film, and the imdb-only
dedup couldn't see them as the same film because re-uploads usually carry NO imdb
id — so the user saw, e.g., FOUR "House on Haunted Hill" cards. Worse, the strengths
were split across copies: one copy had the imdb + 1959 + a TMDb poster but was a
low-res iPod derivative, while the good 720p video sat on a no-imdb card. Tapping
the nice-looking card gave bad video; tapping the good-video card gave a thumb-art
card with no metadata — "the app serves the wrong thing." The recent caption-wins
dedup (the subtitle fix) made it worse: the whisper batch captions EVERY uncaptioned
copy independently, so a film got captioned 4× and `drop_noimdb_dupes_of_captioned`
(which only dropped a no-imdb copy that had NO captions) stopped firing entirely.
Measured: 700 title-clusters with >1 film copy (~858 redundant cards); 179 are the
safe single-imdb-anchor case (~195 cards). Validated end-to-end: 208 re-uploads
merged into 189 best cards, **0 imdb ids lost, 0 duplicated, 0 captions lost**; House
collapses to one 720p card stamped with tt0051744 + 1959 + TMDb poster + William
Castle, and the 1999 remake (William Malone, +18 min runtime, no imdb) correctly
stays a separate card.

**How to apply**: precision over recall (Decision 035) — NEVER merge a multi-imdb
cluster (distinct films) or an all-no-imdb cluster (generic-title collisions). The
runtime guard is load-bearing: it is the only thing separating the 1959 House on
Haunted Hill from the 1999 remake that shares its exact title and has no imdb/year.
Grafting copies only film-level (copy-independent) fields — imdb/tmdb/year/director/
rating/artwork — NEVER video URL or captions (those are a matched pair on one exact
archiveID; the winner keeps its own). The fix is PURE DATA in the shared DB, so all
four platforms (tvOS/iOS/Android/web query the same `catalog.sqlite`) get it with no
app build; republish via `publish-db`. The still-open, riskier class is all-no-imdb
duplicate clusters that ARE one film (e.g. "Werewolf of Washington" ×4) — needs
stronger corroboration (same year + runtime + a non-generic title guard) before it
can be merged safely; deferred.

**Consequences**: the served DB shrinks by the merged count (~200 now; grows as the
whisper batch captions more copies — re-running publish-db re-derives the merge each
build, so it self-maintains). `dedupe_by_imdb` still runs first. The Swift in-memory
`AppStore.dedupedByIMDb` mirror is now a subset of the DB-level policy; browse/search/
detail read the DB so they get the full merge, but the mirror could be aligned later.

---

## 040a — Extend the dup-merge to multi-imdb attach + no-imdb runtime-corroborated sets
*Date: 2026-06-20*

`merge_film_duplicates` (Decision 040) was generalized from "single-imdb anchor
only" to a per-title-cluster **union-find** over a `_same_film` edge test, with a
`_consistent` gate before any component merges. `_same_film` requires positive
corroboration (shared imdb, matching year, or tight runtime agreement) AND no
contradiction (different imdb, year apart >2, runtime apart beyond tol); a bare
no-imdb copy (no year, no runtime) attaches ONLY to an imdb-bearing copy, never to
another bare copy. This now also (a) attaches a no-imdb copy to the RIGHT film in a
multi-imdb cluster (by runtime/year), and (b) merges no-imdb-only duplicate sets when
runtimes corroborate (Werewolf of Washington ×4, Messiah of Evil ×4, Moon of the Wolf
×3). The survivor additionally grafts the cleanest title (`_title_quality` demotes
uploader/filename strings like `y2mate.is-…`).

**Why**: the owner pushed — "there have to be hundreds or thousands of these." The
single-imdb-only pass left the no-imdb duplicate sets (the largest visible-clutter
class) untouched. Measured: of 170 no-imdb clusters, 82+ are confidently one film by
runtime agreement; total confident merges rose from 208 → **360 re-uploads into 315
cards**, still with 0 imdb lost / 0 duplicated / 0 captions lost.

**How to apply**: the `_consistent` gate is the safety net for union-find's
transitivity — if a component ends up naming two imdb ids or spanning >2 years /
mismatched runtimes, it is NOT merged (left fully separate). Keep the bare-copy rule
(attach only to an imdb anchor) — it is what stops generic-title collisions ("Public
Domain Animation" ×31 distinct cartoons) from chain-merging. STILL deferred: no-imdb
clusters with NO runtime on the copies (can't corroborate) — these need enrichment to
add imdb/runtime first, then they merge automatically on the next build.

---

## 041 — archive.org community signals: harvested, used for sort/best-copy, surfaced as vote-floored shelves + pipeline-filtered reviews
*Date: 2026-06-22*

Archive Watch consumes archive.org's built-in usage/community data — views (all-
time / 30-day), favorites (`num_favorites`), ratings (`avg_rating`), and reviews —
harvested onto every catalog item by `tools/harvest_community_signals.py` (batched
advancedsearch + the be-api views bulk endpoint) and used four ways: (1) a
recency+quality **popularity sort** (`build_sqlite._pop_score`: 30-day views +
recent/all-time downloads + vote-floored rating + favorites); (2) **best-UPLOAD
selection** (`_community_copy_score` feeds the Decision-040 dedup winner — a film's
trailer can out-download the film, so weight rated+reviewed+favorited copies and
penalise trailers); (3) **community Home shelves** (Watching Now / Community
Favorites / Most Discussed) on all four platforms; (4) **reviews on Detail**, but
ONLY genuine reviews of the title. Reviews are filtered in the PIPELINE
(`tools/comment_fit.py`, run by `tools/harvest_reviews.py`) and the surviving ones
BAKED into the catalog `reviews` field; every client just displays them.

**Why**: (a) the signals make popularity reflect what people actually watch now and
make best-copy reflect what a real audience vetted — far better than the legacy
all-time-downloads proxy. (b) The community shelves are **vote-floored to
imdbVotes≥1000** because raw community counts are dominated by obscure un-IMDb'd
foreign edge cases (softcore, "The Child Molester") that the metadata adult filter
CANNOT catch — but those have no IMDb votes, so the same floor as Top Rated keeps
the curated shelves clean. (c) Reviews are filtered in the pipeline, not at runtime:
archive.org "reviews" are a comment box mixing genuine reviews with file/upload
talk ("what format is the audio?", "request a re-rip", even 5★ "I downloaded the
DVD-5 version, the picture is cleaner") and inappropriate/spam. Owner rule: Detail
shows genuine reviews of the FILM only — never about the video file, never
inappropriate. A pipeline scorer is deterministic, reviewable, needs no runtime LLM,
and means one implementation instead of four. Validated 12/12 on real reviews + 0
false-keeps on fresh data; of 10,531 items scanned, ~5,500 had ALL reviews dropped.

**How to apply**: new community surfaces read the harvested fields
(numFavorites/numReviews/avgRating/views30d are DB COLUMNS; full `reviews` ride in
item_json / detail-shard `rec[8]`). NEVER judge review fit at runtime — extend
`comment_fit.py` (the file/inappropriate lexicons) and re-harvest. Keep the
imdbVotes floor on any community-ranked shelf. The harvest is weekly
(`community-signals.yml`, catalog-writers concurrency) + resumable; the metadata
review API is slow/flaky, so harvest_reviews retries and is best run with a long
budget. Reviews are baked (not live-fetched) — fast, offline, already filtered.

**Consequences**: additive catalog fields + 4 new DB columns + 3 computed web-index
shelves + a detail-shard element. The better popularity sort EXPOSED pre-existing
curation gaps (educational courseware, mega-compilations, un-flagged foreign adult)
that the old compressed sort buried — addressed by `build_sqlite` exclusions
(`mit_ocw`, `_is_compilation`) + a tightened adult-title marker; subtle foreign
softcore remains a fuzzy residual handled by the shelf vote-floor.

---

## 039b — Whisper auto-captioning ABANDONED; subtitles come from archive.org ASR + OpenSubtitles only
*Date: 2026-06-22*

Reverses Decision 039 Phase 4 and Decision 039a. Whisper.cpp transcription of films'
own audio is REMOVED entirely: the workflow (`whisper-subtitles.yml`), the tools
(`whisper_subtitles.py`, `whisper_publish.py`), the runbook + accuracy checklist are
deleted, and all 44 whisper-generated `captions`/`subtitleHLS` were un-wired from the
catalog. Subtitles now come ONLY from (1) archive.org's own ASR/uploader captions
(`enrich_subtitles.py`, the backbone, ~4,800 films) and (2) OpenSubtitles by imdb/tmdb
id (human-made, `opensubtitles_subtitles.py`, gated on the owner's API key).

**Why**: owner tested the whisper output on-device and it was unusable — on old films
with poor or music-heavy audio whisper HALLUCINATES coherent-sounding but wrong text
(White Zombie's track bore no resemblance to the dialogue; silent films like Steamboat
Willie got fabricated cues). Quality is too variable to ship, and a wrong subtitle is
worse than none. Human-made OpenSubtitles is the quality path on the same side-load
plumbing. Detecting good-vs-hallucinated whisper output at scale proved unreliable
(period-density/short-cue heuristics caught the worst but not the borderline).

**How to apply**: do NOT reintroduce on-device/auto speech-to-text for subtitles. New
subtitle coverage goes through OpenSubtitles (human) or archive.org's own files. The
`captions[]` side-load schema + the per-platform readers (Android SubtitleConfiguration,
web `<track>`, Apple HLS) are unchanged and stay — only the whisper SOURCE is gone.

**Note (separate, unresolved)**: the Apple HLS-subtitle path is single-segment, which
breaks scrubbing + non-faststart start on captioned films — this affects ALL captioned
films on iOS/tvOS (archive-ASR + future OpenSubtitles), not just whisper, and is a
distinct problem from this decision.

---

## 042 — macOS "Creation Studio": a Mac-exclusive multi-clip editor, not the iOS app resized
*Date: 2026-06-22*

Archive Watch gets a native **macOS** app that is two things at once: a parity
browse/play/library face on the shared Swift Core, AND a **Mac-EXCLUSIVE "Creation
Studio"** — a multi-clip timeline editor that composes clips across different archive.org
titles into one exported film. The binding spec is `docs/macOS-DESIGN.md`; the API/UX
research is `docs/research/creation-studio-README.md` + seven briefs. The architecture is
fixed on four load-bearing decisions: (1) **one Timeline model compiles to one
`(AVMutableComposition, AVVideoComposition.Configuration, AVMutableAudioMix)` triple that
serves BOTH preview and export** (`AVComposition` is an `AVAsset`); (2) clips are
**non-destructive proxy references** to remote archive.org ranges (OTIO-shaped Codable, we
own the annotation layer / archive.org owns the bytes), and export is **cache-then-export**
— pre-fetch only each clip's moov-snapped in/out byte range via `ResilientStreamLoader` to
a local faststart MP4, NEVER stream remote into `AVAssetExportSession` (which fails on
remote URLs); (3) **no backend, three data planes** — shared read-only SQLite on a
Release/Pages (catalog + a new stock `clips.sqlite` and `subtitle.sqlite`, query-on-disk +
WASM-Range on web), a user annotation layer (proxy-clip library + `.archiveproj` projects
in SwiftData + iCloud, references only), and disposable device-local caches; (4) the
flagship **text→supercut (#9)** gets word-level timing from macOS-26 SpeechTranscriber
**validated against the held caption text** (token-diff: the caption is ground truth for
*what was said*, the recognizer supplies *when*) — the Decision-039b hallucination fix
applied to timing, with MFA for the rough-audio tail.

**Why**: phones create ONE clip (iOS Clip Studio, Decision 033); the Mac assembles a film.
The owner's brief is explicit — make a first-class Mac app that ENABLES new capabilities,
"not just a retread of old iOS/iPadOS/tvOS ways of doing things." Creation Studio belongs
ONLY on macOS because its features structurally require four things the touch/TV/web
platforms cannot host: a full filesystem + document model, subprocess CLI tools
(ffmpeg/PySceneDetect/MFA), heavy/long-running/background compute, and a
pointer+keyboard+menu+multi-window editor. The shared Swift Core (already extracted for
iOS — `CatalogDB`, `ResilientStreamLoader`, models, `CloudKitSyncService`) means the
parity face is ~free and the Mac joins the same CloudKit container; the genuinely new work
is the editor, the stock-archive miner, and the supercut.

**How to apply**: quote `docs/macOS-DESIGN.md` before adding any window/scene/view/engine
path/index/feature. The non-negotiables: **Library ≠ Project** (proxy library is app-
global SwiftData+iCloud; project is the `.archiveproj` document); **cache-then-export,
never stream-into-export**; the **two-pass grade→overlay render** (CI filter + CALayer tool
can't share one `AVVideoComposition` — inherited Decision-033 constraint); **the
no-auto-edit learning gate** — #9 (supercut) and #6 (auto-tagged stock) MUST yield an
EDITABLE timeline of candidates, never a one-tap finished cut (automate the mechanical,
preserve the meaningful); **provenance burned + sources embedded on every export**;
**rights-gated `isClippable` only**. Reuse the Core verbatim; rebuild only the Mac-native
shell (SwiftUI scenes + AppKit for the timeline `NSView`+`CALayer` and the browser
`NSCollectionView`). `sqlite-vec` (a SQLite extension that links into the SQLite the app
already uses) + **MobileCLIP** (a Core ML model) are permitted as "Apple frameworks + an
extension + a model," NOT third-party Swift packages; heavy tools stay subprocess/CI.
De-risk with three spikes before Phase 1 ships: the `NSDocument`/security-scoped-bookmark
seam, the AppKit timeline scroll/zoom/hit-test, and one real cache-then-export round trip.

**Consequences**: two new CI-built shared indices (`clips.sqlite` stock = PySceneDetect →
Vision classify → MobileCLIP embeddings; `subtitle.sqlite` = FTS5 cues + a word-timing
table) join the publish pipeline, additive and popularity-first like the cover/subtitle
pipelines. Two new project skills (`macos-creation-studio-engine`,
`macos-native-app-shell`) and the binding `docs/macOS-DESIGN.md` are the authoring
backlog. Phasing: 0 shell+parity → 1 editor spine (proxy library + timeline +
cache-export) → 2 text/audio layers + multi-format export → 3 stock archive (#6) → 4
search + supercut (#8,#9) → 5 publish (#7, archive.org IAS3 first, YouTube
Private/Unlisted until Google verification). YouTube uploads from an unverified OAuth app
are forced Private + 100-user-capped, so public sharing leads with archive.org.

---

## 043 — Drop archive.org auto-ASR captions; broaden title artifact cleaning
*Date: 2026-06-24*

Two data-quality fixes in `remediate_catalog.py` (the per-build self-healing pass,
so they reach every platform via the shared catalog DB / web index / detail shards).
(a) **Subtitles:** archive.org auto-ASR captions (`source == "archive-asr"`, label
"English (auto)") are DROPPED from every item's `captions`, and `enrich_subtitles.py`
no longer ingests `.asr.*` files. Only human/uploader captions (uploader `.srt`,
SubDL, SubSource) remain. (b) **Titles:** `sanitize_title` gains strips for the
trailing parenthesised year `(1962)`, the leading `YYYY - ` scene-rip prefix, foreign
sub/dub tails (`- VOSE` / `- Legendado`), a trailing ` - Director` that matches the
item's own director field, bracketed/full `H:MM:SS` runtime stamps, file-size/fps
parens, rip/scan words (`DVD Rip`, `DVD ISO`), more scene groups (RARBG/YIFY/…), and
`_The` / `_<uploader note>` underscore suffixes. Measured on the live 40k catalog:
7,976 titles cleaned, 2,859 ASR captions dropped, 0 empty/junk results.

**Why**: (a) reverses Decision 039b's "subtitles come from archive.org ASR +
OpenSubtitles" — the owner found *Child Bride*'s subtitles were nonsense that synced to
nothing. Investigation: archive.org's own ASR hallucinates into word-salad on the
catalog's poor old-film audio exactly like the whisper output 039b retired — *Child
Bride* mid-film reads "all the world war one will run all the world all. Black" and
"ALRIGHT ALRIGHT ALRIGHT"; sampled auto captions were ~uniformly garbage (compression
ratio ~2.5, the 3-gram "why why why" ×19), while human ("English") captions were
coherent. A wrong subtitle is worse than none (039b's own principle), and the reliable
signal is the SOURCE (auto vs human), not a content score (which over-flagged real
dialogue). (b) the owner found "MANY titles" carrying years and file artifacts; an
audit showed 6,439 trailing `(year)`, 886 leading-`YYYY -`, plus DVD-rip/runtime/
site-tag/underscore cruft slipping past the older, narrower rules. The year belongs in
the title's OWN field (shown on Detail + lists), so it's redundant noise in the title.

**How to apply**: never re-ingest auto speech-to-text for subtitles (039b + this) —
new coverage is human only (uploader files, SubDL/SubSource). When broadening title
strips, keep the precision discipline: every strip must keep letters in the result
(never empty a title), only fire when it changed something, and be dry-run-checked for
false positives against the live catalog (the runtime-stamp strip was tightened to
brackets-or-`H:MM:SS` after it wrongly hit "At 3:25"; one/two-letter real titles like
"It"/"M"/"Go" and year-titles like "1917"/"Blade Runner 2049" must survive). Both are
self-healing (re-run every build) and reversible (re-running enrich refills human subs;
titles re-derive from the source each build).

**Consequences**: ~2,859 items lose their (garbage) caption and show no subtitle until a
human source covers them — correct, per 039b. The published subtitle-assets `.vtt` files
for dropped ASR captions become orphaned (harmless). Title cleaning is visible on every
surface at once (shared data plane). The Phase-3 free-subtitle harvest (SubSource/SubDL)
remains the path to real coverage.


---

## 044 — Enforce the QC gates EVERY build: auto-apply rights, footprint-gate bogus CC, validate poster liveness, clear orphan auto-subtitle HLS
*Date: 2026-06-24*

The three catalog quality gates (copyright, posters, subtitles) are now ENFORCED on
every published build instead of being report-only or one-shot, after the owner found
all three leaking on the Apple TV homepage (copyrighted "Throw Momma From The Train"
visible, a few missing posters, auto-generated subtitles still playing). Four changes:

1. **Rights apply runs every `publish-db`** (`audit_rights.py --apply` after dedupe).
   `rights-audit.yml` deliberately only ran `--confirm` (annotate) and left the
   `excluded=true` apply "for later review" — so confirmed-copyright items drifted back
   onto every surface (373 un-excluded confirmed-copyright items found live, incl.
   famous studio films). The apply is pure-data + idempotent + reconciling, so it is
   safe every build; its reconcile now SKIPS foreign exclusions
   (`livenessReason`/`livenessDead`/`episodeDuplicate`/`duplicateOf`/`duplicateMergedInto`)
   so it can never un-hide a dead/duplicate item another tool owns. `rights-audit.yml`
   (network confirm) is now also nightly-scheduled so new ingests get confirmed before
   the apply.

2. **Bogus-CC footprint gate** (`license_rescues`). The licenseurl is uploader-controlled,
   and uploaders routinely re-upload copyrighted STUDIO films with a bogus CC0/CC tag
   (Throw Momma 1987 CC-BY-NC-ND; Nayakan 1987 CC0 27k votes; Virus 1980 CC0 3173 votes;
   Black Cobra 1987 CC-BY 686 votes; Kagemusha 1980 CC-BY-NC-ND). For MODERN works (>=1978)
   a license now rescues ONLY if it is a FREE-CULTURE variant (CC0, CC-BY, CC-BY-SA — never
   the NonCommercial/NoDerivatives variants, which are both non-free AND the studio-piracy
   tell) AND the item has NO commercial footprint (`imdbVotes < COMMERCIAL_VOTES=100`). A real
   theatrical release with thousands of IMDb votes is never a creator CC dedication. The
   bogus `rightsStatus=="creative_commons"` LABEL is likewise trusted only pre-1978. Genuine
   modern free-culture works with no footprint (Sita Sings the Blues, CC0, 0 votes) are KEPT.

3. **Poster liveness gate** (`validate_posters.py` + `validate-posters.yml`, new). The
   pipeline had NO poster liveness check (`scrub_poster_urls.py`/`enrich_artwork.py` are
   orphaned tools on the retired SQLite plane). Measured ~62% of `omdb` posters
   (m.media-amazon.com — IMDb rotates the image hash) now 404, surfacing as missing posters
   on Home. The nightly workflow ranged-GETs decay-prone posters (omdb/commons/wikidata/
   external/fanart/aapb/tvdb/tvmaze) and demotes a DEAD (404/410) one to the always-available
   `archive.org/services/img/{id}` thumbnail with `hasRealArtwork=False` + `posterDead=True`
   — so a broken image never LEADS Home (build_sqlite's designed-art gate drops it) yet every
   surface still shows a real frame. A TRANSIENT 403/429/5xx (e.g. Commons throttle) is left
   unmarked and retried — never demoted (the "never wrongly hide" discipline).

4. **Orphan auto-subtitle HLS cleared** (`remediate_catalog.drop_asr_captions`). Decision 043
   dropped the hallucinated archive-ASR `captions[]` but left the `subtitleHLS` rendition
   (the Apple HLS subtitle track) behind on 2,465 items, which the Apple apps still played.
   `drop_asr_captions` now also drops `subtitleHLS` when no HUMAN caption survives. Runs every
   build (it is part of remediate), so it self-heals.

**Why**: report-only / one-shot gates DRIFT — new ingests and license/host decay re-introduce
copyrighted titles, dead posters, and stale auto-subtitles between manual passes, and the owner
hit all three at once. The cost asymmetry favors enforcing every build: a wrongly-hidden item is
reversible (the `excluded` flag) and a demoted poster still renders a frame, whereas a
copyrighted studio film on the homepage is a legal/trust failure and a broken poster is a visible
quality failure. Enforcing in `publish-db` (the single chokepoint that builds the app DB + web
index) means every platform — tvOS, iOS, macOS, Android, web — gets the clean gate from one place.

**How to apply**: keep the apply in `publish-db` (do NOT revert to confirm-only "for review" —
that is the drift that caused this). The `--confirm`/`--apply` split stays: confirm is the network
phase (annotate `archiveLicense`/`rightsConfirmed`), apply is the pure-data hide of CONFIRMED
buckets only (an unconfirmed modern item is never hidden). Never raise `COMMERCIAL_VOTES` to
"rescue" a popular title — a high vote count is the signal the CC tag is bogus. For posters, only
404/410 demotes; never demote on a throttle. The residual class (unmatched foreign studio films
with 0 votes carrying a bogus CC0 — Lady Vengeance, Haider) has no footprint to gate on and is
left to the curated `is_renewed_classic` denylist; they have 0 votes so they never reach a
vote-floored shelf. Complements Decision 027 (rights buckets), 026 (match correctness), 043
(subtitle source), 023 (generated covers).

**Consequences**: nightly order is rights-audit confirm (01:10) → validate-posters (02:15) →
publish-db apply+build (04:30). `posterDead`/`posterDeadURL`/`posterChecked` are additive JSON keys
the clients ignore; `posterDead=True` is a durable wants-marker for a future fresh-poster /
cover-generation pass (the demoted items currently show the Archive thumbnail). `catalog.json` on
the source release carries the annotations but not the build-time apply/remediate mutations (those
are re-derived every build, idempotently) — consistent with Decisions 027/043.

---

## 045 — Playable TV episodes are first-class catalog items (materialized in the DB)
*Date: 2026-06-25*

Every playable episode in a series spine is materialized as a first-class catalog
item with `contentType: "tv-episode"` — so episodes get the SAME machinery as
films for favoriting, playlists, sharing (`/item/{id}`), Clip Studio, Detail, and
search, with NO episode-specific interactions to learn. The items are DERIVED at
DB-build time in `build_sqlite.populate_series` from `series/*.json` (catalog.json +
the spines stay the canonical sources per Decisions 016/018 — the DB is the
materialized view); they carry `seriesID` + `seasonNumber`/`episodeNumber` +
`seriesTitle` for the byline and the "Part of <series>" Detail link. They are
materialized ONLY in the full DB, never the lean bundled seed (favorites resolve
once the full DB loads, seconds after first paint). The standalone-duplicate of an
episode (a tv-special/feature-film upload of the same archive item) is DROPPED so
the canonical episode is the single card (`populate_items` skips an archiveID that
the spines own — Decision 036's "organize into season/episode, never haphazardly").
The redundant `episodes_fts` index (and the `EpisodeHit`/`searchEpisodes` machinery
that fronted it) is removed — episodes are in `items_fts` now.

**Why**: favorites/playlists/watch-progress are already keyed by `archiveID`, and an
episode already HAS an `archiveID`, so the ONLY thing blocking "favorite/share/clip
an episode" was RESOLUTION — turning a saved id back into a card needs it in the
`items` table. Owner ask 2026-06-25: "share individual episodes and favorite them
and add them to playlists … use all the same mechanics … instead of creating new
interactions users have to learn." Making episodes items closes every gap at once
through the existing item machinery; the alternative (an "episode resolver" special-
casing each consumer) is exactly the per-feature divergence the owner rejected.
Passes the learning-orientation gate — more navigable/actionable, no new interaction
to learn.

**How to apply**: episodes are excluded from FILM surfaces — Home shelves, Browse/
Movies, Random Film, director/quality rows — via the `notStandaloneTV` clause (now
`NOT IN ('tv-special','tv-episode')`) and the browse/count/random `NOT IN` lists;
but they ARE in SEARCH (a separate `searchExclude` drops only tv-special). Tapping an
episode opens its OWN Detail (play/favorite/share/clip), which carries a "Part of
<series>" link back to the spine. Episode items are PD (the visible catalog is PD/CC
only) so `isClippable` is true — Clip Studio works on them with no extra wiring. Keep
the seed episode-free (`materialize_episodes=False`). New ingests are covered by the
nightly publish-db (the materialization re-derives from the spines every build —
self-maintaining, no persisted Release mutation). Web is the divergent plane
(catalog-index.json, no FTS): it loads a small `episodes-index.json` into its id map
so episodes resolve there too.

**Consequences**: the full DB gains ~4,600 tv-episode items (+ drops ~900 standalone
duplicates). `seasonNumber`/`episodeNumber`/`seriesTitle` are additive JSON keys the
older clients ignore. The published DB schema drops `episodes_fts` (no client queries
it after this). Complements Decision 016 (canonical spine), 033/042 (Clip/Creation
Studio), 035/036 (duplicate exclusion + TV taxonomy).

---

## 046 — Backfill rich API metadata into the DB, tiered by use (blob / FTS / join table)
*Date: 2026-06-27*

Pull the metadata our APIs already expose — TMDb keywords, alternative/original titles, full crew
(writer/composer/cinematographer), cast person IDs, production studios, franchise, awards (OMDb),
tagline, full release date, and Wikidata extras — INTO `catalog.sqlite` so users can search, filter,
and learn more WITHOUT a runtime API call. Each field is routed to the cheapest storage layer that
serves its use: **detail-only fields → the `item_json` blob** (decoded only on Detail open, ~0 query
cost), **searched text (keywords/AKA/writer) → the FTS5 index**, **filtered values (keyword/studio)
→ small normalized join tables** like the existing genre/collection tables. NO new hot-path/sort
columns on `items`. Full plan: `docs/METADATA-EXPANSION.md`.

**Why**: today this data is one API call away, so search/filter/discovery can't use it (you can't
FTS-search a TMDb keyword you don't store, or filter by a studio that lives in an API). The
constraint is the shipped DB: it's downloaded (~24 MB `.zz`) and queried on-disk on a 3 GB Apple TV
(Decision 017), so naively adding columns would bloat the download and slow the hot queries. The
tiering avoids both — the blob compresses well and isn't read except on Detail, FTS is an inverted
index built for search, and join tables are only hit by their filter. One TMDb
`/movie/{id}?append_to_response=keywords,alternative_titles,credits` call feeds most of it, so the
backfill is cheap (same call enrichment already makes).

**How to apply**: a new metadata field goes in the LOWEST layer that supports its use — the blob
unless it is actually searched or filtered; never an `items` column for a detail-only field. Batch
fields through one `append_to_response` call, never a per-field API pass. The download budget is
binding: keep `catalog.sqlite.zz` ≤ ~35 MB and MEASURE (Phase 0) before shipping — demote a
budget-busting field to web-only or drop it. Additive per Decision 020 (new JSON keys / FTS terms /
tables are backward-safe; older clients ignore them).

**Consequences**: a `backfill_metadata.py` enrichment pass + `metadata-enrich.yml` (daily,
catalog-writers concurrency) join the pipeline alongside `backfill_language.py` (Decision 045-era).
`build_sqlite` gains keyword/studio join tables + FTS terms; `CATALOG-CONTRACT.md` and each
platform's DESIGN doc are updated as the per-platform search/filter/Detail surfaces land
(tvOS/iOS/macOS `CatalogDB`, Android Room, web index). Complements Decision 007 (TMDb primary) and
the cast/person gap noted in Decision 038.

---

## 047 — Expand to smart TVs via TWO builds, not six; Cast/AirPlay for the closed platforms; Roku deferred
*Date: 2026-08-03*

Archive Watch expands to the non-Apple living room through exactly **two reuse
vehicles plus two zero-app routes**, not a per-platform app: (1) the existing
**Kotlin/Compose/Media3 Android app gains a TV form factor** — the SAME
`applicationId` and AAB, with `leanback`/`touchscreen` declared `required="false"` —
which ships to **both Google TV/Android TV and Amazon Fire TV**; (2) the existing
**vanilla no-build web PWA gains a TV input/focus layer**, which ships to **both LG
webOS and Samsung Tizen** (and technically VIDAA / Titan OS / Zeasn, whose doors are
partnership-gated); (3) **Google Cast** (one $5 registration + one hosted HTML
receiver) reaches Chromecast, Google TV, and Chromecast-built-in TVs — **the only
realistic Vizio path**; (4) **AirPlay** already works via `AVPlayer` at zero cost.
**Roku is explicitly deferred** to its own funded decision. The binding UI rules are
`docs/TV-DESIGN.md`; the ordered work is `docs/TV-PLATFORM-BACKLOG.md`; the viability
research is `docs/TV-PLATFORM-EXPANSION.md`.

**Why**: the brand names (Roku, Tizen, webOS, Fire, Google TV, SmartCast) hide the
fact that there are only **four runtime families**, and Archive Watch already owns a
codebase for two of them. Treating each brand as a separate app would mean six ports
of a data plane that Decision 028 deliberately made platform-agnostic; treating them
as two runtime families means the engine (downloaded SQLite catalog, HTTPS
progressive H.264 MP4, captions side-load) carries over at ~100% on Android and
~70–80% on web, and the genuine work is a 10-foot D-pad UI in each — which is a
UI/navigation pass, not an engine port. Two facts measured on 2026-08-03 make this
concrete: our Android dependency set has **zero Google Play Services** (so Fire TV
needs no GMS removal at all), and progressive H.264 MP4 over HTTPS plays natively on
every one of these platforms with no DRM and no transcode. Roku is the sole exception
and is deferred precisely because it breaks the thesis: BrightScript/SceneGraph is a
proprietary stack with 0% reuse (~2–4 months), and its `Video` node owns networking,
so Decisions 021/031/034's byte-range resume and node failover **cannot be
reproduced** — a real quality regression that must be priced and accepted, not
absorbed silently. Vizio is not deferred but *closed*: no self-serve program exists,
and post-Walmart it is an ad-monetization vehicle with no interest in a free no-ads
app — so Cast is the answer, not a partnership chase.

**How to apply**: **never fork the Android app or the web app for TV.** TV is a
runtime branch (`UiModeManager` type on Android; a CSS breakpoint + focus layer on
web), sharing the data layer, player engine, and routes verbatim — a fork
re-introduces exactly the divergence Decision 028 forbids. **Never add a framework to
the web-TV build** (it is vanilla, no build step — which is why React-based focus
libraries like Norigin are out and the ~200-line spatial-navigation engine is ours).
**Cast is GMS-dependent and must be excluded from the Fire TV variant** — this is the
one cross-cutting constraint between the two Android targets. Every new TV surface
traces to a rule in `docs/TV-DESIGN.md` and inherits its information architecture
from `docs/tvOS-DESIGN.md §2` — a TV build never invents a top-level surface. Three
platform rules bind and are easy to miss: **TV-G6** (64-bit + **16 KB page sizes**,
live since 2026-08-01) must be verified against every bundled native library, not
assumed; **TV-NP** forbids a *video* app from surfacing background/Now-Playing media
controls, so the phone build's `media3-session` `MediaSession` **must be gated off on
TV**; and `TvLazyRow`/`tv-foundation` no longer exist (depend on `androidx.tv:tv-material`
only and use standard `LazyRow`/`LazyColumn`).

**Consequences**: total cash outlay to reach five new stores is **$5** (Cast) plus
test hardware — Play TV is a form factor of the existing $25 account, and Amazon, LG
and Samsung charge nothing to register or submit. Two owner-gated business decisions
remain: Samsung's default **Public Seller tier is US-only** (global needs a signed
offline contract with Samsung HQ, i.e. a business entity), and Roku needs a budget.
`PARITY.md` gains **Android TV** and **Web-TV** columns, and two project skills
(`androidtv-compose-focus`, `smarttv-web-app`) are authored since no existing skill
covers Compose-for-TV focus or Tizen/webOS packaging. The rights-audit exclusions
(Decisions 027/044) become load-bearing on five more storefronts — a copyrighted
title on the home screen is a rejection and takedown risk on every one of them.

## 048 — A run that never started is not a failure to read; it is a failure to retry
*Date: 2026-08-06*

When a scheduled run fails and **not one of our steps ever executed**, that is
GitHub's hosted-runner fleet declining to start the job, not our code breaking.
`.github/workflows/retry-infra-failures.yml` sweeps for exactly those runs every 30
minutes and re-runs their failed jobs. Every other failure is left alone, loudly.

**Why**: on 2026-08-06 an Actions **major outage** (githubstatus incident opened
15:22 UTC) took out three scheduled runs — `Color / B&W classification`, `Re-source
posters (secondary)`, and four shards of `Stock shot index`. Each sat ~15 minutes and
died with a single annotation:

    The job was not acquired by Runner of type hosted even after multiple attempts

The API shape is unambiguous: the job carries `"steps": []` and an empty
`runner_name`, or a lone failed `Set up job`. Nothing of ours ran, so nothing of ours
was at fault. That fact is also what makes the retry safe **for a catalog writer**:
a job that never started never ran `catalog_release.py fetch`, so there is no stale
snapshot in flight and no publish to repeat — the re-run fetches the catalog fresh at
re-run time and takes `catalog-writers` in the normal way. The cost of not retrying
scales with the cron period, which is the whole argument here: these are 8-hourly and
daily jobs, so one dropped run is 8–24 hours of backlog on a pipeline whose entire
design is "chip away at the backlog every tick" (Decision 018).

**How to apply**: the gate is "did any step of ours reach a conclusion", never a
match on the annotation text — GitHub rewords those. Keep the four conditions in
`tools/retry_infra_failures.py` conservative, and in particular keep these two:
**never retry a `cancelled` run** — this repo cancels long jobs routinely and several
workflows share the `catalog-writers` concurrency group, so retrying would fight
whoever cancelled it — and **never retry when a later run of the same workflow already
succeeded**. Use `rerun-failed-jobs`, never a whole-run re-run: the sharded workflows
(`stock-index`, `verify-playback-strict`) must re-run only the shards that never
started. Verify changes with `DRY_RUN=1` against real history before pushing — swept
across six weeks it flags only the genuine never-started runs and ignores every real
code failure. A sweeper cron is itself dropped during an outage, so the lookback is 12
hours, not one tick: it must heal a backlog after the incident ends, not only while it
is happening.

That lookback is only half the mechanism, and the other half is the non-obvious part:
the sweeper **checks githubstatus and sits out a declared Actions outage entirely**.
Retrying INTO an outage is how the retry budget gets destroyed — at a 30-minute
cadence, three attempts are spent in 90 minutes, every one failing for the same
reason, and the run is then abandoned permanently. Today's outage was already 3.5
hours old when this shipped, so a sweeper without the gate would have exhausted every
retry and healed nothing. Degraded performance still gets retried; only a declared
outage is worth waiting out, and an unreachable status API means proceed — a status
page we cannot read must never block healing.

**Consequences**: failures that survive the sweep are now signal — if a run failed and
was not re-run, our code failed. The `MAX_RERUNS` cap (10 per sweep) exists because
this repo has 35 workflows and a long outage could otherwise queue a re-run storm into
a single `catalog-writers` group.

## 049 — The Top Shelf rotates over published pools; personal and editorial rows MERGE
*Date: 2026-08-07*

The tvOS Top Shelf publishes **pools, not a playlist**: `topshelf.json` (schema 2)
carries ~15 named rows of ~30 rights-gated, playable, designed-art candidates each,
and the extension picks which rows and which titles to show from a **6-hour time
bucket** — the row start advances one per window and the picks stride across the
priority list, while each row's own offset walks its pool. The extension now MERGES
the App Group snapshot's personal rows (Continue Watching, leading, with
`playbackProgress`) with the live feed's editorial rows instead of returning early
on either. The snapshot is rebuilt on a **position signature** and on backgrounding,
not on the count of watched titles. `archivewatch://play/{id}` is routed for the
first time, to Detail with autoplay armed, so the Play button resumes.

**Why**: the owner reported the Top Shelf "serves the exact same videos every single
time" and "doesn't work to resume movies you haven't finished." Four independent
causes, each verified: (1) the feed was `ORDER BY imdbRating DESC LIMIT 12` — byte
identical across three weeks of publishes; (2) the extension short-circuited on the
snapshot (`if !local.isEmpty { return }`), and since the app always wrote editorial
rows into it, the network feed was dead code for anyone who had launched the app;
(3) `TopShelfUpdater` keyed on `progress.count`, which does not change when you watch
more of a film you already started or when you finish one — so resume positions went
stale and completed films never left; (4) the extension emitted
`archivewatch://play/{id}` as its `playAction` but `IntentInbox.request(for:)` had no
`play` case, so Press-Play launched the app and did nothing. Only #1 is a content
problem; the other three are the surface being wired to sources it could never read.

**How to apply**: publish MORE than is shown and rotate client-side — a feed of
exactly what to display, ordered deterministically, is static by construction no
matter how often the pipeline runs. Rotation must be **arithmetic on a time bucket**,
never `String.hashValue` (Swift seeds string hashing per process, so a hashValue-derived
offset reshuffles on every query instead of holding still) and never `Math.random`
(a shelf that reshuffles under the viewer is its own bug). Pick rows by **striding**
across the priority-ordered list, not by taking a contiguous slice: rows are published
strongest-first, so a sliding window of 4 eventually lands wholly in the tail and
renders a shelf with no recognizable cinema on it — every assertion passed while that
happened, which is why `tools/test_topshelf_rotation.swift` now asserts that each
window contains a marquee row. Any URL either Top Shelf action can emit must have an
`IntentInbox` case; an unrouted deep link is indistinguishable from a broken app.

**Consequences**: the feed grew 15 rows / 394 items / 66 KB (from 15 items), still
trivial for a ~16 MB extension that only handles URLs. `topshelf.json` keeps a v1-shaped
`sections` digest so already-shipped builds keep working. The pure selection logic lives
in `ArchiveWatchTopShelf/TopShelfRotation.swift` — Foundation-only precisely so the
harness can compile and exercise the SHIPPED file, since the Top Shelf is invisible to a
simulator screenshot and its provider runs out-of-process. Binding rules: tvOS-DESIGN
§15. Related: Decision 015 (the original surface), 023/044 (the art + playability gates
a tile must pass), 027 (rights).

## 050 — Shelf membership that depends on an internal score is COMPUTED in the pipeline, never restated in a client
*Date: 2026-08-07*

"Hidden Gems" membership is a `hiddenGem` column computed by
`tools/build_sqlite.py::_mark_hidden_gems` and queried as a boolean by every
platform (tvOS/iOS/macOS `CatalogDB`, Android `CatalogDatabase`, and the web via
a `hidden-gems` shelf in `catalog-index.json`). The rule: external, semantic
signals stay literal (`imdbRating >= 7.0`, `imdbVotes` in `[100, 5000]` — IMDb's
scale means the same thing next year); our internal `popularityScore` is
thresholded by **percentile of the live distribution, recomputed every build**
(published as `meta.hiddenGemPopCut`). The build prints the count and warns below
`GEM_MIN_EXPECTED`.

**Why**: the shelf shipped 2026-06-01 as the client predicate `qualityScore >= 60
AND popularityScore <= 40`, correct against the popularityScore of that day, a
0-89 band. On 2026-06-29 Decision-041 work rescaled `_pop_score` to a single
scale where every scored item is `100 + s*1000` (~100-4500), so `<= 40` could
thereafter match only un-harvested items — which carry no craft signal either.
Intersection: **zero rows, on tvOS, iOS, macOS and Android simultaneously, for
five weeks.** Nothing failed: the SQL was valid, the columns existed, the query
returned an empty set and each Home just omitted the row. A constant in a client
that is only meaningful relative to a scale the PIPELINE owns is a
silently-breaking coupling; the pipeline is the only place that can see the
distribution, so it is the only place the threshold can live. (The web had the
opposite failure — a *different* homegrown definition, shuffling the bottom 60%
of the popularity list, which is "random obscure", not "high craft".)

**How to apply**: a shelf whose membership depends on an internal score gets a
computed column, not a client predicate — clients query the flag. Clients keep
only per-USER filters (the adult toggle, hidden content types), which the
pipeline cannot know. Keep a scale-free fallback for a DB predating the column
(a client updated before its catalog refresh lands): express it as a percentile
subquery, never as a fresh constant. Items with no IMDb rating cannot qualify —
a "gem" is a claim about craft, and without a rating we would be guessing.
`qualityScore` is deliberately NOT used: a legacy registry field on ~53% of the
catalog with a murky definition.

**Consequences**: 170 gems on the full DB, 66 in the bundled seed (so first paint
has the row before the full DB downloads). Two data findings surfaced by the fix
and acted on — archive.org's OWN `deemphasize` / `loggedin` collection markers
were never read anywhere in the pipeline (442 visible items carry one; the
`deemphasize` set is heavily adult/exploitation content the metadata filter
misses), now honored for this curated shelf as demote-not-delete; and
`remediate_catalog` gained a narrow `^video\d+:` title strip for g4tv scrape ids
(15 hits, dry-run-verified to leave "2001: A Space Odyssey" and "1896: Director
Unknown" alone). STILL OPEN, reported not fixed: honoring `deemphasize` /
`loggedin` catalog-wide is an owner curation call (`geo_restricted` must NOT be
swept in — it includes real Chaplin), and a wrong external match can still put a
non-film on a film shelf (Decision 026's domain).

## 051 — AirPlay hands the RECEIVER a published URL; the resilient loader is a local-only path
*Date: 2026-08-08*

When an AirPlay route engages, the Apple players replace the current item with a
**published, receiver-fetchable URL** (`AirPlayRouting.receiverURL` — the HLS
first so WebVTT captions survive the handoff, else the progressive MP4), and
restore the loader-backed local item when the route disengages. `AirPlayRouting`
is Foundation-only and owns the custom-scheme vocabulary (`aw-stream`,
`aw-hls`), which the loaders now read from, so a new loader cannot be added
without the AirPlay check learning about it.

**Why**: Apple's position, confirmed via TSI on the developer forums, is that
**"Video AirPlay is not supported when using a custom resource loader."** Every
playback path in this app is loader-backed — `aw-stream://` for the resilient
MP4 stream (Decisions 021/031/034) and `aw-hls://` for the captioned HLS layer
(Decision 039 Config C) — because the delegate that serves those schemes lives
on the SENDING device, so a receiver has no way to fetch the media. Selecting a
route showed an error on the Apple TV instead of playing, on *every title*. iOS
got a swap on 2026-08-05; **macOS never did**, while its `.floating` HUD
advertised an AirPlay button the whole time.

**How to apply**: never hand a receiver a URL straight from the player's current
asset — route it through `AirPlayRouting`, which CHECKS the scheme rather than
assuming. `directHLSURL ?? directVideoURL` was the old iOS expression and would
pass a custom-scheme URL through unexamined if either ever came from a loader
path. When nothing fetchable exists, leave playback alone rather than replacing
it with something that cannot play. Accept that Decision 021/031/034 resilience
(resume-on-reset, node failover) is **structurally unavailable over AirPlay** —
the receiver owns the connection, the same trade Decision 047 records for Roku;
an archive.org 5xx mid-stream is unrecoverable there in a way it never is
locally. tvOS is deliberately untouched: an Apple TV is a receiver, not a sender.

**Consequences**: two harnesses, because AirPlay itself cannot be exercised on a
simulator (no routes exist) — `tools/test_airplay_routing.swift` compiles the
SHIPPED `AirPlayRouting` and asserts the decisions (21/21, including "a
custom-scheme URL is never handed to a receiver"), and
`tools/verify_airplay_receiver_path.py` walks master.m3u8 → rendition → media
segment exactly as a receiver would. The latter taught its own lesson: it first
reported two failures that were an SSL timeout and an archive.org 5xx, both of
which answered 200/302 on retry — so transient and 5xx (rotating storage nodes)
are retried and reported, never counted as unfetchable, the same
never-condemn-on-a-throttle rule as the poster validator (Decision 044). The
handoff on real hardware remains owner-verified: iPhone/Mac → Apple TV.

## 052 — Trailers are removed as DATA, judged on runtime evidence the catalog already holds
*Date: 2026-08-09*

Trailers and clips posing as the feature are reversibly `excluded` by a
no-network rule in `remediate_catalog.flag_trailers`, which runs on every build.
The test is evidence the catalog already stores: `trueRuntimeSeconds` /
`fileRuntimeSeconds` (what the file actually is) against `runtimeWasSeconds` /
`runtimeSeconds` (the matched title's canonical length). A sound-era item that
runs ≤ 300 s against a ≥ 40-minute canonical runtime, at under a quarter of it,
is a trailer. 74 removed on the live catalog — Serpico, Star Wars, Taxi Driver,
The Sting, Close Encounters, Doctor Zhivago, Bicycle Thieves.

**Why**: the owner found the **Serpico trailer** in the app carrying the full
film's synopsis, so it read as the feature — and Serpico (1973) is still under
copyright. A `detect_trailers.py` and a weekly workflow already existed and
could never have caught it, for two independent reasons: its `FILM_TYPES` was
`{feature-film, tv-special, feature}`, and a trailer for a feature is classified
**`short-film` precisely because it is short**, so the detector skipped exactly
the class it was built to find; and it gates on `runtimeSeconds >= 1800`, but by
then the runtime had been corrected to the file's 237 s, erasing the very
discrepancy it looks for. Worse, its only action was `contentType="trailer"` —
and **no client filters that type** (the app surfaces use deny-lists), so 19
already-detected trailers, including a 70-second *Star Wars*, were still
shipping. Removing them as DATA reaches tvOS, iOS, macOS, Android and web on the
next publish with no app release.

**How to apply**: judge on runtime evidence, never on the label. Three bounds
each prevent a MEASURED false positive and must not be loosened casually:
`actual <= 300 s` (a real 736 s Popeye cartoon wrongly matched to Altman's 1980
feature is a WRONG MATCH, not a trailer); **sound era only** (a 4-minute silent
is far likelier a surviving FRAGMENT of a lost film — *The Case of Lena Smith*
(1929) and Lubitsch's *So This Is Paris* (1926) survive only as fragments, and
those are archival treasures); and a feature-length canonical runtime (a short
matched to a short is just a short). Do NOT trust an existing
`contentType="trailer"`: the old detector mislabelled Ozu's *Tokkan kozô* (the
surviving 13-minute fragment), a 13-minute *King of the Rocket Men* SERIAL
CHAPTER measured against the whole 12-chapter serial, and *Häxan* — blanket-
excluding that bucket would have hidden all three. They run the same measured
test as everything else and stay visible. Do NOT add a client-side
`contentType='trailer'` filter for the same reason: it would hide those films.

**Consequences**: `detect_trailers.py`'s two blind spots are fixed (FILM_TYPES
widened; the runtime gate now reads whichever field holds the canonical length),
and it now excludes rather than merely relabels. ~29 real films still carry a
wrong `contentType="trailer"` from the old detector — visible and playable, but
mistyped; restoring them from `contentTypeWas` is a follow-up. Complements
Decision 027 (the reversible `excluded` mechanism) and 026 (match correctness,
which owns the wrong-match half of this population).

## 053 — First paint comes from the CACHED catalog; the bundled seed is for first launch only
*Date: 2026-08-09*

Both Apple stores (`AppStore` for tvOS, `AppStore_iOS` for iOS + macOS) now open
the **cached full catalog** at launch and fall back to the bundled `seed.sqlite`
only when no cache exists. The launch refresh uses
`downloadDatabase(onlyIfChanged: true)`, and `swapDB`/`swap` take the file path
and no-op when asked to swap in the file already open.

**Why**: the owner reported that "the initial loading of the hero row movies and
continue watching all load a certain set of movies first and then after about 5
seconds, a new set of movies load, including the movies I was just most recently
watching." That was three DB swaps on a normal launch, each bumping
`dbGeneration`/`dbVersion` and re-querying every view: the bundled seed (~2.6k
items) → the cached full DB (~27k) → and then the SAME cached file again,
because `downloadDatabase()` without `onlyIfChanged` returns the cached path on a
**304**. Recently-watched titles are usually absent from the seed's 2.6k items,
which is exactly why Continue Watching looked wrong until the second pass.

The seed-first ordering was written for "instant first paint", but that premise
does not hold: opening either file is `sqlite3_open_v2` plus one `itemCount`
query, and SQLite pages the 165 MB in on demand rather than reading it — so the
cached DB is no slower to open than the 25 MB seed. Measured on the iPhone 17 Pro
simulator: a relaunch with the cache present now logs exactly ONE paint,
`first paint from cached full DB: 27051 items`, where it previously painted 2,619
seed items first.

**How to apply**: the seed is a cold-start fallback, not the first-paint path —
do not reorder it back. Any new swap site must pass its `path` so the identical-
file guard can work; a `dbGeneration` bump is a full re-query of every shelf, so
bumping it for unchanged content is a visible reshuffle that shows the user
nothing. Use `onlyIfChanged: true` for any refresh whose result you have already
opened. First launch still paints the seed then swaps once — that is unavoidable
and correct, and it is the only launch that should ever swap twice.

## 054 — On-device subtitles are served by a resource loader; a `file://` HLS master never plays
*Date: 2026-08-09*

Subtitles obtained on the device — pulled from the viewer's own OpenSubtitles
account, or transcribed locally — are played by `LocalSubtitleHLSLoader`, an
`AVAssetResourceLoaderDelegate` that serves the master, video and subtitle
playlists AND the WebVTT itself from `Caches` through the `aw-hls://` scheme,
while the media segment stays a direct https URL. `SubtitleStore` still writes
those files; what changed is that the player is handed the DIRECTORY and a
loader, never the local master file. The action that produces them lives on
Detail (`GetSubtitlesView` + `SubtitleFinder`), on all three Apple platforms.

**Why**: the original design handed `AVPlayer` the `file://` master directly and
was never executed. It does not work.
`tools/test_local_master_playback.swift` runs both shapes against the same film:
the already-published REMOTE master reaches `.readyToPlay` with a legible group
of `["English"]` and advances, while the LOCAL master sits at `.unknown`
indefinitely with an **empty error log and zero access-log events** —
AVFoundation does not reject it, it never attempts the load at all. It will not
follow a remote reference out of a local playlist, and a local subtitle
rendition referenced from a custom-scheme playlist hits the same wall, which is
why the VTT must be served too. The shape that works was already in the tree:
Config C (`CaptionedHLSLoader`, Decision 039), playlists through a loader and
the segment left to AVFoundation.

Two other constraints were measured rather than assumed, and they shape the UI:
`AVAssetReader` refuses a remote asset outright ("Cannot initialize an instance
of AVAssetReader with an asset at non-local URL") and `AVAssetExportSession`
fails -11838. There is no way to read a film's audio without downloading the
film. So transcription is a SEPARATE, explicitly-confirmed action that states
the real size — measured with a HEAD request, not estimated — while searching
OpenSubtitles stays one tap.

**How to apply**: never hand AVPlayer a `file://` HLS playlist that references
anything remote; route it through a loader. Anything the playlists reference and
we hold locally must be served by that loader too, WebVTT included. Keep the
segment a direct https URL — a custom-scheme segment fails CoreMediaError
-12881 (harness-proven), so there is no mid-stream failover on this path. Never
add a "transcribe" affordance that starts without stating its cost: it spends a
viewer's data plan, and the whole film is the unavoidable unit. Verify changes
with `tools/test_local_subtitle_loader.swift`, which compiles the SHIPPED files
and asserts the path end to end including seek.

**Consequences**: `SubtitleStore.cachedDir` is what the three players consult
when the catalog has no `subtitleHLS`, so a fetched or transcribed track appears
in the native CC menu with no further wiring. Partially reverses Decision 039b
for the on-device case only, under `CaptionQuality` and an opt-in toggle;
central auto-captioning stays retired. Complements 039 (the seam) and 021/031
(the segment stays AVFoundation-owned).

## 055 — "Already attempted" markers are per-source, or a second source can never run
*Date: 2026-08-09*

`free_subtitles.py` records which PROVIDER has attempted a film
(`freeSubsTried: [...]`) instead of a single `freeSubsChecked` boolean, and a
scheduled run sweeps every configured provider. A film carrying only the legacy
boolean is credited to SubSource alone, since it was the only provider ever
scheduled.

**Why**: subtitle coverage sat at 16.6% while the daily harvest reported
"Backlog drained" and finished in 94 seconds. It was correct about the wrong
thing: the marker recorded THAT a film had been attempted, not BY WHOM, so once
SubSource had swept the catalog every film looked attempted to every provider.
SubDL — configured, keyed, and selectable via a workflow input — had never had a
single target and never would have. The plateau was a flag, not a ceiling on
what is findable. This is the same shape as Decision 050: a value whose meaning
depends on context the flag does not record, failing silently and looking like
completion.

**How to apply**: any "we already tried this" marker on a multi-source pipeline
records the SOURCE. A bare boolean is only safe when there will never be a
second source, which is a bet that keeps losing here. Distinguish attempted from
FAILED-TRANSIENTLY as well: an exception must not mark the film (it already does
not), because a 429 is not evidence that a subtitle does not exist — the same
never-condemn-on-a-throttle rule as the poster validator (Decision 044). When a
drain reports "drained", check the wall-clock: a sweep that finishes in seconds
has found nothing to do, and that is a claim worth verifying rather than
trusting.

**Consequences**: SubDL gets a fresh pass over the ~83% SubSource has nothing
for. The same audit that found this measured the live set properly for the first
time (`tools/audit_published_subtitles.py`): 95.1% of published tracks work, not
the ~70% on record — the earlier figure came from a classifier that required
`HH:MM:SS` timestamps when WebVTT also permits `MM:SS`, so it reported healthy
files as empty. Integrity was not the problem; sourcing is.

## 056 — Verification freshness is tiered by visibility; a stale "verified" is invisible
*Date: 2026-08-09*

`check_liveness.py` re-probes items eligible to be RECOMMENDED (designed artwork
— the Home/browse gate) every **14 days**, while the long tail keeps the 90-day
TTL (`--hot-reprobe-days`, default 14). The clients close the matching hole:
`verifiedAnd` (`i.playable = 1`) now applies to `shelf()` and the Home director
rows on tvOS/iOS/macOS and Android, and the web applies a `Data.plays()` gate to
its Home shelves — all three previously gated only their hero and discovery rows,
so a CURATED shelf bypassed playability entirely.

**Why**: the owner reported two recommended titles — *City That Never Sleeps* and
*The Missing Juror* — that never play. Nothing was wrong with any gate: every copy
carried `playbackVerified: true`. They were probed on 2026-07-18/19, PASSED, and
their archive.org items were removed afterwards (two now return `files: []` with
no server and 503; a third 404s because its file was renamed). `playbackVerified`
records that a title played ONCE; the app cannot distinguish a check made
yesterday from one made three months ago, so a flat 90-day TTL means a dead title
can headline the front page for a quarter. The daily run was meanwhile using
**314 of its 8,000-item budget** — the constraint was never throughput, it was
that the staleness gate had nothing to offer it.

**How to apply**: any "we verified this" marker on data that can rot needs a TTL
proportional to how visible the claim is, and the budget should be spent where
the claim is loudest. Measure the tier before choosing it: 18,408 designed-art
items at 14 days is ~1,300/day against an 8,000/day budget, which is affordable;
7 days would not have been meaningfully better and 30 barely helps. Do NOT rely
on a client-side gate alone — `playable = 1` was already correct here and still
shipped a dead link, because the DATA was stale, not the query. And keep the
client backstop regardless: a source can always die between the last probe and
the next launch.

**Consequences**: iOS and macOS gained the load watchdog they never had — both
armed a status observer and timeout ONLY on the captioned-HLS path, so a plain
MP4 that could never load had no error surface at all and simply span forever
(tvOS has had a 60s backstop since Decision 021's era). A dead title now says so
in 60s instead of never. Applying `verifiedAnd` to curated shelves was measured
first: 1,453 curated-shelf items, 100% already verified, so it hides nothing
today and cannot regress tomorrow. Complements Decision 044 (enforce the gates
every build) and 034 (node failover, which cannot help when the item is gone).

## 057 — A run destroyed in the concurrency queue is retried; a long job may not hold the lock for hours
*Date: 2026-08-09*

`tools/retry_infra_failures.py` gains a second pass that re-runs workflow runs
**cancelled before any job was created** — the signature of being displaced in a
concurrency queue — and only when that run's group is idle, one per group per
sweep. Separately, `resource_posters_secondary.py` gains `--max-minutes`
(default 75): it stops starting new items at the budget, publishes what it has,
and reports how many it left.

**Why**: 27 workflows share the `catalog-writers` group, several with 5.5-hour
budgets, and GitHub keeps only ONE pending run per group — a newer arrival
CANCELS the older pending one. So while a long job holds the lock, scheduled
catalog work is not queued behind it, it is **destroyed**, and nothing retried
it: Decision 048's sweeper explicitly refused to touch `cancelled` on the
reasoning that a cancel is usually a human or a concurrency group. Measured over
one 12-hour window on 2026-08-09: **seven runs lost** — liveness ×2, colour ×2,
free-subtitles ×2, community signals — including both attempts at that day's
dead-link remediation, while a poster job held the lock for over four hours. The
workflows' own comments already recorded 25–75% cancellation rates; what was
missing was recovery.

The distinction Decision 048 wanted is available and exact: a superseded run has
**zero jobs**, because it never left the pending queue and GitHub never created
one. A human (or a timeout) cancels a run that is RUNNING, which always has jobs
with steps. Zero jobs therefore carries the same no-side-effect guarantee as
"not one step of ours ran" — nothing was interrupted, nothing partially applied,
so a re-run cannot repeat anything.

**How to apply**: keep the zero-jobs test as the gate — never widen it to
`cancelled` generally, which would fight whoever cancelled a running job (this
repo cancels long jobs deliberately, including once in this very session). Only
re-run into an IDLE group: re-running into a busy one is immediately superseded
again and burns an attempt against `MAX_ATTEMPTS`, and the group is read from
the workflow files on disk rather than guessed. One re-run per group per sweep,
so seven recovered runs cannot re-enact the pile-up that lost them. Verify with
`DRY_RUN=1` against real history before changing the gate. For the lock itself:
any catalog writer that can run long needs a time budget that PUBLISHES rather
than a `timeout-minutes` that kills — a killed job never publishes, so its work
is lost outright, and a bounded one that says what it skipped keeps a backlog
from reading as coverage.

**Consequences**: dropped scheduled work now heals within ~30 minutes of the
lock clearing instead of waiting for the next cron tick, or forever. The deeper
fix — computing without the lock and taking it only to fetch→apply→publish, the
shape `--deltas-out` already enables in several tools — remains open, and would
make the group contention largely moot rather than merely survivable.

## 058 — Live captions are transcribed AHEAD of playback by a muted scout, never tapped from playback
*Date: 2026-08-10*

A film with no subtitle track is captioned on device by `LiveCaptions`: a SECOND,
MUTED `AVPlayer` plays the same URL at 2x with an `MTAudioProcessingTap` on its
audio mix, feeding `SpeechAnalyzer`. Because that scout runs ahead of the viewer,
complete cues exist before they are needed and the display is **pop-on** — a whole
caption appears when its line begins and is replaced by the next. Wired on iOS,
macOS and tvOS; styled from the viewer's own `MediaAccessibility` preferences.

**Why**: two claims I made were wrong and both cost days. First, that
transcription requires downloading the film — `AVAssetReader` refuses a remote
URL and `AVAssetExportSession` fails -11838, but those only rule out reading the
asset AS A FILE; a player decodes remote audio continuously and a processing tap
hands those buffers back (measured: 9.1s of PCM in 8.8s of wall clock from a
remote asset). Second, that tapping the PLAYING item was good enough — it is not,
because playback yields audio at 1x, so the transcript can only ever TRAIL the
speech. Roll-up, rolling word windows and every other presentation are just
different ways of showing text arrive late; the owner's question — can we listen
ahead so complete lines appear like a professionally captioned film — is the only
thing that actually fixes it.

**How to apply**: never caption from the playing item's tap. Keep the scout MUTED
but NOT `isMuted` (muting can remove audio from the render pipeline, and then the
tap never fires). SCALE cue times by the scout rate: at 2x the audio is
time-compressed, so the same speech yields half the samples and every cue lands
at half its true time. Tap callbacks must NOT be declared inside a `@MainActor`
type — Swift infers the closure's isolation from its enclosing type and the
runtime traps from the audio thread. Pass NO explicit `bufferStartTime`: the
tap's time is sometimes invalid (a trap in `checkIsValidCMTime`) and every derived
clock was rejected as overlapping (`SFSpeechError 17`); the analyzer's own clock
is correct. Use `.timeIndexedProgressiveTranscription`, not the offline preset.
And reserve the locale (`AssetInventory.reserve`) — without it the error is "not
subscribed to transcription.en", or, on a machine with no model, the utterly
misleading "No common audio format among modules".

**Consequences**: `SubtitleFinder`'s download-and-transcribe path is removed —
it downloaded a whole film to do offline what now happens during playback for
free. Central macOS-runner generation keeps its value only for platforms with no
on-device recognizer. The Simulator CANNOT verify any of this (no speech model),
so `AW_START_ITEM`/`AW_AUTOPLAY` were added to macOS and the harnesses
(`test_live_audio_tap`, `test_live_captions_timing`, `test_caption_pacing`) drive
the SHIPPED code against a real film.

## 059 — A caption is never replaced before its words are spoken, or before it can be read
*Date: 2026-08-10*

Caption timing obeys two rules everywhere captions are produced or published:
cues may not OVERLAP (the later one is pushed back, never the earlier one cut
short), and every cue is held for at least its READING time (~2.5 words/second,
the usual subtitle guideline). In `LiveCaptions` a transcriber result's span is
divided among its lines by CHARACTER COUNT rather than evenly, and `line(at:)`
has no lead-in. In the pipeline, `build_subtitle_assets.pace_vtt` applies the
same two rules to every published WebVTT — clamping overlap and extending a
too-brief cue INTO EMPTY SPACE only, never shortening one and never pushing past
the next.

**Why**: the owner reported constantly racing the screen — the next sentence
appearing while the speaker was still finishing the last. Dividing a span evenly
by line count gave a short trailing sentence as much time as a long leading one,
so it surfaced early; and a 0.25s lead-in in the display is literally a licence
for the next caption to preempt the current one. A flat one-second floor was also
too crude: one 13-word line sat on screen for 1.7s, and a caption you cannot
finish reading is the same as no caption. The fault is not specific to machine
transcripts — human subtitles carry both, which is why the rules live in the
publisher as well and therefore reach web and Android.

**How to apply**: assert the PACING property, not merely that captions appear —
`tools/test_caption_pacing.swift` measures dwell against reading time and checks
for overlap and out-of-order display (median on screen 3.6s → 4.2s, too-fast
2/17 → 1/17). When adjusting, do not trade one complaint for the other: forcing
every line to full reading time drifts the captions behind the audio, and pauses
in speech are what absorb that drift.

## 060 — The Speech API shipping on a platform is not the model shipping; ask `AssetInventory.status`
*Date: 2026-08-10*

`CaptionCapability` probes once per launch whether THIS device can actually
transcribe — `AssetInventory.status(forModules:) != .unsupported` and a
non-empty `SpeechTranscriber.supportedLocales` — and every caption surface reads
it. When it is false the app does not start the scout player, does not claim a
film is being captioned, and says so once. `auto-captions.yml`'s nightly
schedule is disabled for the same reason.

**Why**: live captions worked on the owner's Mac and iPhone and produced nothing
on their Apple TV. Apple's documentation lists SpeechTranscriber on tvOS 26, the
tvOS SDK ships `Speech.tbd` and the full Swift interface, and every layer we
could measure on tvOS worked — the scout ran at 2x, the audio tap delivered
44.1kHz stereo PCM, the caption label drew over the picture. The recognizer was
the one link no simulator can exercise, so it stayed a hypothesis until the
GitHub macos-26 runner turned out to reproduce it EXACTLY: the same
"not subscribed to transcription.en", `passed=0 rejected=4`, on every nightly
run for weeks. `tools/probe_speech_assets.swift` (run 31433486714) then asked the
framework each question in order:

    supportedLocales: 0 · installedLocales: 0 · status(forModules): unsupported
    supportedLocale(en-US): en-US        <- answers with NO models present
    reserve(locale): granted=true        <- grants a locale it cannot serve
    assetInstallationRequest: THREW "… is not subscribed to transcription.en"
    bestAvailableAudioFormat: nil

There is nothing to download. Two APIs actively mislead — `supportedLocale(
equivalentTo:)` is locale equivalence and says nothing about availability, and
`reserve` grants a reservation for a locale the device cannot serve — so a
model-less machine looks like a misconfigured app right up until the fourth
call. The machines where this worked are the ones that already had the models;
the pipeline's own "66x realtime" benchmark was measured on one of them, which
is how a workflow that has never captioned a single film looked healthy.

**How to apply**: gate on `status(forModules:)` before doing any work — it is
the only honest signal, and it was the one call the code never made. Never infer
availability from documented platform support, from `supportedLocale(
equivalentTo:)`, or from a `reserve` that returns true. Do not "fix" a
`not subscribed` error by retrying the install; on a model-less device it is a
statement about the device. A feature that cannot run must not be advertised —
the Get Subtitles sheet told a living room its film was being captioned while
nothing appeared, and the player streamed a second muted copy of every film at
2x to feed a recognizer that did not exist. Benchmark a pipeline on a machine
that represents where it will RUN, not the one it was written on.

**Consequences**: automatic captions are an iOS/iPadOS/macOS/visionOS feature;
tvOS gets subtitles only from human sources (the OpenSubtitles/SubDL program,
Decisions 039/055), which is now what the tvOS UI says. Central generation is
still possible on a machine that has the models — a self-hosted Mac — so
`auto-captions.yml` stays dispatchable rather than deleted. Complements
Decision 039b (a wrong caption is worse than none) and 058 (the scout-ahead
engine, unchanged and still correct where models exist).

## 061 — From 27 the SYSTEM captions our films; the app's job is to get out of the way
*Date: 2026-08-10*

Apple generates subtitles on device for video that carries none, from iOS/tvOS/
macOS/visionOS 27, automatically, for any app using AVPlayerViewController or
AVPlayerView — which all three of ours do. So the implementation is subtractive:
`SystemCaptions.waitForLegibleOption` polls the player for a legible option, and
when one exists `LiveCaptions` never starts on any platform. Apple's own
captions win: they live in the native subtitle menu, obey the viewer's
Accessibility caption settings and style, survive scrubbing, and cost no second
stream.

**Why**: two things had to be true before the app could rely on it, and neither
was answerable from Apple's documentation — the WWDC26 session names HLS and
file-based content, and archive.org serves a PROGRESSIVE MP4 through a custom
`AVAssetResourceLoaderDelegate`, which is exactly the property that disqualifies
us from video AirPlay (Decision 051). Measured on macOS 27.0 (26A5388g) against
a live archive.org film, both answers are yes within one second, direct AND
through the shipped `ResilientStreamLoader`:

    plain https MP4:              1s — 1 option(s): English (US) Transcribed
    through ResilientStreamLoader: 1s — 1 option(s): English (US) Transcribed

Without the stand-down, upgrade day would have produced DOUBLE captions on every
uncaptioned film — the system's track and our differently-timed overlay on top of
each other — on iOS and macOS, where our engine works. That regression was
already live on this macOS 27 machine and is what the harness caught.

**How to apply**: never draw captions over a player without first asking whether
the system already offers a legible option — `AVPlayerItem.
selectableMediaSelectionOptions(in:)` (new in 27) is where a generated track
appears, since it is not in the file and the asset's own group cannot list it.
Do NOT auto-select the generated option on the viewer's behalf: whether captions
appear is their Accessibility preference, and our old always-on overlay was
quietly overriding it. Do not add an app setting for generated subtitles —
Apple's session is explicit that no opt-in exists, and a toggle that controls
nothing is the dead control Decision 056 already removed once. Keep
`tools/test_system_generated_subtitles.swift` green: it runs the shipped loader,
so it will notice if a change there ever costs us the system's captions the way
one cost us AirPlay.

**Consequences**: on 27, tvOS finally gets captions — the platform Decision 060
showed can never run our own engine, because an Apple TV has no speech models.
Nothing needs to ship for that: a device upgrading to tvOS 27 captions our films
whether or not the app is rebuilt. What this build adds is the stand-down, so
the platforms that DO run our engine hand over cleanly instead of doubling up.
Below 27 nothing changes: no legible option ever appears for a bare MP4, the
poll costs one wait, and `LiveCaptions` proceeds exactly as before.

## 062 — A published subtitle track is checked against what is being said, not trusted
*Date: 2026-08-10*

When a film ships with subtitles, the app now listens to the first ~3 minutes
with the `LiveCaptions` scout, compares the published cues against its own
transcript (`SubtitleAgreement`), and acts on one of three verdicts: keep the
file as published (and stop listening); SHIFT it, showing the same human words
at corrected times through our overlay; or abandon it and caption live, because
the file belongs to a different cut or a different film. Wired on iOS, macOS and
tvOS (`SubtitleReview`).

**Why**: owner report — "many times the automatic captions are far better than
the subtitles file". A published file goes wrong in two ways that are both
invisible until somebody watches: it belongs to a DIFFERENT CUT (the failure
Decision 026 exists for, on the subtitle plane), or it is RIGHT BUT OUT OF SYNC,
which is by far the commoner fault. Neither is judgeable from the file alone —
and both are obvious the moment there is an independent estimate of what is
being said, which the device now produces for free. Measured while building
this: **The Day the Earth Caught Fire ships with its subtitles 27 seconds
late.** That is not a subtle defect; it is unwatchable, and it looks like a
broken app rather than a broken file.

Keeping the two faults distinct is the point. A mismatched file should be
abandoned; a shifted one must be SHIFTED, because human words with corrected
timing beat a machine transcript on both text and timing, and discarding it
would throw away the better source.

**How to apply**: score word PRESENCE near the expected time, swept over
candidate offsets — never sequence alignment. A machine transcript mishears
individual words constantly, and demanding order scores a good match as a bad
one. Drop words under four characters: an unrelated file scores well on "the"
and "a" alone, which is the exact false match this exists to catch. Calibrate
thresholds against real files and re-measure when the recognizer changes — a
true match scores ~44% and a mismatch ~3%, so the separation is wide but the
absolute numbers are LOW, and the first thresholds (guessed at 0.55) rejected a
genuinely matching file. State the correction as "seconds to ADD", never "how
late it is": the second phrasing is what produced a sign error that moved a
27s-late file further out of sync. Returning NO VERDICT is a valid answer and
must stay distinct from disagreement — silence, an intertitle stretch or a
sparse transcript are not evidence against a file.

**Consequences**: a captioned film now costs a bounded second stream (~3 minutes
at the scout's 2x) to be checked, and nothing after that — the scout stops on a
verdict. `Catalog.Item.publishedVTTURL` exposes the cue text the check needs.
The same judge could run in the PIPELINE to find mistimed files catalogue-wide
rather than per-viewer, on a machine that has speech models (Decision 060 rules
out hosted runners) — the 27-second file above is unlikely to be alone, and
fixing them at the source would help web and Android too.

## 063 — Hand captioning to the system only when it actually captions THIS film
*Date: 2026-08-10*

Decision 061 stood our engine down whenever the player offered a legible option.
That is amended: it stands down only after the system's track has been observed
to EMIT TEXT (`SystemCaptions.emitsCaptions`, via `AVPlayerItemLegibleOutput`
attached observe-only). Offering a track and producing captions are different
claims, and on this catalogue they come apart.

**Why**: measured on macOS 27 across three films. The system offered "English
(US) Transcribed" on all three and produced cues on ONE — *The Incredible
Machine* (1975), a clear narration. On *The Day the Earth Caught Fire* (1961) and
*Meet John Doe* (1941) it emitted **nothing at all** across five minutes each,
including with nothing else running in the process, while our own engine
transcribed both — 57.4% and 55.3% word error against their aligned published
human tracks. It appears to decline rather than guess on poor archival optical
sound, which is most of what this app holds. Standing down on the mere presence
of a track would therefore have left viewers with NO captions on exactly the
films that need them most, while the app quietly held an engine that would have
produced something.

Which of the two is more ACCURATE remains unmeasured: no film yet tested both
produced system captions AND had a human reference to score against. The
comparison harness is `tools/compare_caption_sources.swift` and it aligns the
reference before scoring — the first version did not, and reported 67.7% for a
transcript that scores 57.4% once the reference's own 27-second sync error is
removed (Decision 062). A benchmark that measures the reference's sync error and
calls it the engine's word error is worse than no benchmark.

**How to apply**: never treat an available caption track as a working one — for
the system's generated track, for a published file (Decision 062), or for a
future source. Attach the legible output observe-only
(`suppressesPlayerRendering = false`); suppressing rendering to inspect a track
would blank the very captions being checked. Keep the wait bounded (~75s): the
system's cues arrive in late batches, measured ~75s behind the playhead, so a
short check would wrongly conclude silence. If a later OS starts captioning
these soundtracks, this needs no change — it observes rather than assumes.

**Consequences**: on a film the system declines, the viewer gets our captions
instead of nothing, at the cost of one bounded extra stream. ~55% word error on
1940s–60s optical sound is the honest number for what an on-device recognizer
achieves here; it is not good, and it is a great deal better than a blank
screen. The two engines' relative accuracy is still an open question and needs a
film where both produce output.

## 064 — Mistimed subtitle files are corrected at the SOURCE, which is the only way most platforms get them right
*Date: 2026-08-10*

`tools/subtitle_sync_main.swift` (transcribe + judge) and
`tools/fix_subtitle_sync.py` (work / apply / publish) sweep the published
subtitle set, measure each file against a transcript of its own film using the
SHIPPED `SubtitleAgreement`, and rewrite the cue times of the ones that are out
of sync. Corrections go into `subs.tar.gz` on the `subtitle-assets` release,
which `deploy-pages` restores into the site — so one fix reaches web, Android
and every Apple platform at once, with no app build.

**Why**: Decision 062 checks a published file per viewer, per playback, but only
where the device can transcribe. That excludes **web** and **Android**, which
have no on-device transcription available to them at all, and **tvOS 26**, which
has no speech models (Decision 060). Those three platforms cannot help
themselves, and they are most of the audience. A file corrected at the source is
the only route by which they ever show the right subtitles — and it also spares
the platforms that CAN self-correct from doing the same work on every playback.

First real sweep, popularity-first: *Impact* (1949) ran **22 seconds late**
(agreement 6% → 60% once corrected) and *The Vampire Bat* **31 seconds late**
(5% → 37%). Both are now correct on every platform; verified live on
archivewatch.org after deploy.

**How to apply**: this cannot run in CI — a hosted runner has no speech models
and cannot install them (Decision 060), which is exactly what killed the central
auto-caption pipeline. Run it on a machine that has them. It is resumable
(verdicts append to JSONL, decided films are never re-listened to) and ordered by
popularity, because a mistimed file on a film nobody opens matters less than one
on the front page.

`apply` rewrites SHIFTS by default and only REPORTS mismatches. Deleting a
subtitle set is destructive and irreversible from a local snapshot, and the
mismatch threshold is not validated at this scale — the same precision-over-
recall rule that governs hiding items (Decisions 027/035/044). The first batch
justified that caution immediately: *Carnival of Souls* was judged a mismatch at
12%, and its audio is the known-bad case already on record in
`CaptionQuality`'s calibration (49 wpm) — a poor transcript, not necessarily a
wrong file. `--drop-mismatched` exists for when the evidence is reviewed.
Silence is never evidence: `unheard` and `no-verdict` change nothing.

**Consequences**: `publish` refuses to upload a set smaller than 7,000 files,
because republishing a shrunken snapshot would delete subtitles wholesale — the
failure that once served `404.html` as VTT with HTTP 200 (Decision 043 era). The
sweep runs at roughly one film every 2–3 minutes, so 7,391 films is a long
background job rather than a session; it is built to chip away, and the
popularity ordering means the value lands first.

## 065 — Generated subtitles need a track SELECTED and an asset without our resource loader
*Date: 2026-08-11*

Amends Decision 061, which was wrong on the load-bearing point. Handing captions
to the system now runs a full sequence (`SystemCaptions.handOver`): wait for an
offered option, SELECT it, confirm text actually flows, and — if it does not —
replace the player item with the DIRECT https URL, select again, and confirm
again. Our own engine stands down only when that ends in real text.

**Why**: an Apple TV on tvOS 27 showed file-based captions perfectly and never
an automatic one. Two independent causes, both measured on macOS 27 against a
live film:

1. **Nothing selected the generated track.** A published track rides a master
   playlist we generate, which declares `AUTOSELECT=YES,DEFAULT=YES`, so
   AVPlayer switches it on. A generated track is merely offered; the system
   lists it in the subtitle menu and leaves it off. That difference is entirely
   ours, and it is exactly the asymmetry the owner saw.
2. **Generated subtitles do not work through a custom `AVAssetResourceLoader`.**
   Same film, same moment:

       plain URL      option offered · first text at 34s
       aw-stream://   option offered · NEVER any text

   The system advertises the track either way and silently produces nothing
   through the loader — the same disqualification that rules out video AirPlay
   (Decision 051).

Decision 061 recorded that this DID work through the loader. That test only
checked an option was OFFERED, never that text was produced — the precise
distinction Decision 063 was written about two decisions later, applied to
everything except the measurement that started it.

**How to apply**: never treat an offered caption track as a working one, in any
direction — this is the third time that mistake has cost something (the poster
liveness gate, the system-declines case, and now this). Select before judging:
an unselected track emits nothing, so an emission check run first measures the
selection, not the recognizer. Keep the resilient loader as the DEFAULT and swap
only after the system has been given a fair chance and failed — films the system
was never going to caption keep Decisions 021/031/034 intact, and only the films
that gain captions pay for them. Never override a selection the viewer has made.
On swap, carry `externalMetadata` across on iOS/tvOS and NOT on macOS, whose
`AVPlayerItem` has no such property at all.

**Consequences**: a film the system captions loses resume-on-reset and node
failover for the rest of that playback. That is a real cost, accepted knowingly
because the alternative on an Apple TV is no captions at all — tvOS has no
speech models of its own (Decision 060), so the system's generated track is the
only captioning that platform will ever do.
`tools/test_system_caption_selection.swift` drives the shipped sequence and
fails if it ends without text.

## 066 — Catalog writers compute without the lock and take it only to merge a delta
*Date: 2026-08-11*

A workflow that mutates the catalog now runs as TWO jobs: a compute job holding
no lock, which snapshots the catalog, does its work, and emits a field-level
delta; and a short `apply` job holding `catalog-writers`, which fetches a FRESH
catalog, merges the delta, and publishes. `tools/catalog_delta.py` provides
`snapshot` / `extract` / `apply` generically, so an existing tool needs no
changes — the delta is derived by observing what the tool did.

**Why**: measured 2026-08-11 — 27 workflows held the single `catalog-writers`
lock for their ENTIRE run, and their average demand summed to **24.2 hours per
cycle** against a lock with 24 hours a day to give. Oversubscribed, which is the
root of most of what the preceding decisions patched: runs destroyed in the
queue as a matter of course (057), budgets measured in hours, killed runs
discarding work, and the clobber risk that 020 and the publish shrink-guard
exist for. The compute never needed the lock; only the mutation does, and the
mutation takes about two minutes.

    color-classify   lock held 52m  ->  21 SECONDS   (measured, real run)
    check-liveness   compute 1m unlocked, apply 1m locked, delta 0.0 MB

The merge is the load-bearing part, not the speed. Republishing a whole catalog
read hours earlier silently REVERTS whatever another writer published meanwhile
— the lock was compensating for the data model rather than protecting a real
invariant. A field-level merge does not: two workflows touching different fields
of the same item both survive.

**How to apply**: the lock is declared at WORKFLOW level in this repo, so it
covers every job in the run — splitting into two jobs changes nothing unless the
top-level `concurrency:` is REMOVED and re-declared on the apply job alone. Gate
every step after the "nothing changed" check on it: an empty-delta run skips the
fetch, and an ungated remediate step then runs against a catalog that is not
there. Emit the delta with `if: always()` and upload it the same way, so a run
killed mid-compute still contributes what it finished. Do NOT convert a workflow
whose tool ingests or deletes ITEMS wholesale without checking the delta shape
first — `extract` carries a new item whole, but a tool that rewrites the entire
item list is better left alone.

**Consequences**: a converted workflow's compute can be given a generous budget
without starving anything, and can be sharded, because it competes for nothing.
Decision 057's sweeper returns to being a backstop rather than load-bearing.
Converted so far: color-classify, check-liveness, free-subtitles; ~24 catalog
writers remain, and each is a mechanical change of the same shape. Measured cost
on the real catalog (140.6 MB, 40,671 items): snapshot 2.9s at 737 MB RSS, and a
661-item change produced a 0.0 MB delta.

## 067 — A film with no subtitles plays on the PLAIN url, because the resilient loader is never offered a generated track
*Date: 2026-08-12*

From 27 the system generates subtitles on device for video that carries none, and
Apple's position is that no app implementation is required. For an app that hands
AVPlayer an ordinary URL that is true. This app hands it a custom
`AVAssetResourceLoaderDelegate` (Decisions 021/031/034), so the asset shape is now
chosen UP FRONT: a film with no published subtitle track plays on the plain
`https` URL (`SystemCaptions.prefersDirectPlayback`), on tvOS, iOS and macOS, with
`CaptionStallMonitor` rebuilding on the resilient loader if that path stutters
persistently. A film that HAS published subtitles is untouched — its captioned-HLS
path works, and its subtitles are human.

**Why**: measured on macOS 27.0 (26A5388g), one shape per process, against a film
the system is known to caption:

    plain direct MP4 (/download URL)   option offered · TEXT in 33s
    node-resolved direct node URL      option offered · TEXT in 30s
    HLS master wrapping the same MP4   option offered · NEVER any text
    aw-stream:// resilient loader      NO OPTION EVER OFFERED

Both halves of that overturn what was recorded here. Decision 065 said the loader
path was "offered but silent" and built a four-stage handover on it — wait for the
track, select it, listen, and only then swap to the direct URL. **The swap was
gated behind a track that never arrives**, so on an Apple TV it could never run,
which is precisely the reported symptom: file-based captions working, generated
ones never appearing, across three shipped builds. And wrapping the MP4 in HLS —
the obvious reading of Apple's "HLS and file-based content" — does NOT qualify us
either; a single-segment playlist pointing at a remote MP4 is offered a track that
stays silent forever, exactly like the loader.

That "offered" reading came from a harness that probed several shapes in ONE
process, where a track left over from the previous player was counted as the
current one's. A shape IDENTICAL to the passing one failed later in the same run,
which is what exposed it. **One shape per process, or a result cannot be
attributed to a shape at all.**

**How to apply**: never assert that a caption track works because one was
OFFERED — this is the fourth time that exact conflation has cost something here
(poster liveness, the system declining, Decision 065, and now the measurement
065 itself rested on). Assert emitted TEXT. Do not gate the direct path on the
viewer's caption preference: "Generated Subtitles" is its own Settings toggle,
separate from the captions display type, so a viewer can have generated subtitles
on while the display type is still `.automatic` — gating there would leave the
menu empty for exactly the person who went looking for it. Keep referencing no 27
symbol: the App Store archive builds with the RELEASED Xcode (26.6) to clear
ITMS-90111, and reaching for `selectableMediaSelectionOptions(in:)` is what broke
build 876; a plain `#available` version check compiles fine and the generated
track appears in the asset's own legible group anyway. A film the system DECLINES
is a statement about that film's audio, not a failure of this path — it declines
on much of this catalogue's optical sound (Decision 063).

**Consequences**: films without subtitles give up resume-on-reset and node
failover on 27, in exchange for being captioned at all — the same trade already
made for captioned films ("smooth-without-CC beats stutter-with-CC"), with the
same stall fallback. The cost is bounded: AVFoundation pays the `/download` 302
once for a progressive read, not per chunk, which is what made it expensive under
the loader. `SystemCaptions.stage` is surfaced on tvOS when neither the system nor
our engine can caption, because an Apple TV is the only device that can answer
this and its console cannot be read from a development machine — three fixes
shipped on evidence gathered entirely on a Mac. `tools/test_system_caption_selection.swift`
drives the SHIPPED code in both modes and asserts the negative control too, so a
future change that makes the loader captionable is visible rather than silent;
`test_system_generated_subtitles.swift` is deleted, having asserted the disproven
claim. `hls_manifests` gained optional CHARACTERISTICS so machine-made and
translated renditions can carry `public.machine-generated` / `public.translation`
and be labelled "English Generated" / "Spanish Translated" by AVKit itself
("What's new in HTTP Live Streaming", WWDC26) — nothing carries it today, because
every published track is human.

## 068 — On tvOS our caption engine LEADS; the system's generated track is opportunistic
*Date: 2026-08-12*

For a film with no subtitle track on tvOS 27, `LiveCaptions` (the SpeechAnalyzer
scout that captions iOS and macOS) starts IMMEDIATELY, and the watch for the
system's generated track runs CONCURRENTLY with 300s patience — standing our
engine down only if the system's track ever actually emits text. Both automatic
paths are gated on the viewer's caption preference (`viewerWantsCaptions`); a
forced-only viewer gets neither engine nor note.

**Why**: measured on the owner's own Apple TV 4K (tvOS 27.0, 24J5346a), driven
directly from the dev Mac — the device is PAIRED, and
`devicectl device process launch --console` with an `AW_CAPTION_DIAG=1` hook
made it a readable oracle for the first time. Two findings, opposite in sign:

    system generated track   offered + selected on EVERY shape
                             (local file, plain remote MP4, HLS wrapper)
                             — NO TEXT in 10+ minutes of playback
    our SpeechAnalyzer scout ENGINE CUE after 14s on the same clip

tvOS 27 ships working speech models — `supported 45`, and installs completed on
demand (0 → 9 locales during the probes). **Decision 060 ("tvOS has no speech
models and never will") was true of tvOS 26 and is obsolete on 27.** Meanwhile
the system's generated track on this beta is a menu entry that never speaks in
a third-party app: blocking playback captions for 300s behind it was the delay
the owner kept reporting as "no captions". A real film then captioned end to
end through the real player on the device (`AW_START_ITEM` + `AW_AUTOPLAY`),
resuming at the viewer's watch position with cues flowing on the console.

Also measured on the way here, each worth keeping: the offer itself can arrive
MINUTES in (cold engine: local file offered nothing in 180s; same file offered
at 0s once warm) — so `handOver` is now ONE loop that polls, selects and
listens across its whole patience, never an offer-first gate a silent opening
can defeat. And an "offered" reading contaminates across probes in one process,
but EMITTED TEXT through an item's own legible output cannot — which is what
makes a multi-shape on-device probe valid where the macOS harness needed one
shape per process.

**How to apply**: never gate captions on the system track EMITTING before our
engine may start on tvOS — lead with ours, stand down if the system speaks.
Keep the stand-down: if a later beta (or a device where "Generated Subtitles"
genuinely works) starts emitting, the system's track wins on every count
(native menu, viewer style, no second stream). Films WITH published tracks
still skip the watch entirely — the judge (062) owns that path. Test tvOS ON
tvOS: the paired-device loop (build Debug → `devicectl install` → `launch
--console` with `AW_CAPTION_DIAG=1`) costs minutes; every prior fix here
shipped through ASC on Mac-only evidence and three of them were wrong. Keep
`caption-probe.mp4` (60s narration, captions in 14s on macOS AND on the ATV)
as the reference clip — probing with a random film conflates "device cannot
caption" with "film was declined" (063).

**Consequences**: Apple TV viewers get live captions on the ~19,200 bare
sound-era films (audit `tools/audit_caption_tiers.py`) at iOS/macOS quality,
starting ~15-30s into playback. Decision 067's plain-URL path stays: it costs
nothing, keeps the film eligible for the system's track the moment Apple fixes
emission, and the system-watch needs it. The Caption Diagnostics screen stays
in Settings as the standing experiment kit. tvOS 26 remains published-files
only. If a future tvOS beta makes the generated track emit, nothing needs to
ship — the stand-down is already listening.

## 069 — The scout's two clocks are platform traps: pin the pitch algorithm, map by rate, guard replays, follow the current player
*Date: 2026-08-12*

Four rules now bind the live-caption scout, each the corpse of a bug found by
tracing real playback on the paired Apple TV and convicted against GROUND TRUTH
(a locally transcribed copy of the same film region — the only arbiter when two
mappings disagree; scout `currentTime()` is NOT one, since the tap runs ahead of
the position clock by the audio queue's depth):

1. **`audioTimePitchAlgorithm = .timeDomain`, explicitly.** Under the platform
   default an Apple TV at 2x raced its position clock while delivering tapped
   audio at ~1x — half the film's audio would never have been transcribed, the
   lookahead never grew, and what audio arrived was mangled enough to garble
   the transcript. It also re-delivered already-tapped audio around rate
   transitions, which is where the "same minute of narration three times over"
   came from.

2. **Map analyzer time to film time by `offset + t × scoutRate` — never by the
   tap's presentation timestamps.** The anchoring "improvement" was built and
   reverted the same afternoon: macOS stamps the tap callback in FILM time, so
   anchors agree with the rate formula there — but tvOS stamps it in the
   COMPRESSED timeline, identical to the analyzer's own clock, so anchoring
   silently halved every cue and captions ran minutes early. Ground truth:
   "Temple of the Soul" is spoken at 1108.0; `805 + 151.6 × 2 = 1108.0` exactly,
   on both platforms. The rate formula is the only mapping that never reads the
   stamps, which is why it is the only one that holds everywhere.

3. **Drop tap buffers whose presentation stamp rewinds** (`highWater` in
   `BufferSink.append`). The scout never seeks backward, so an older stamp is a
   re-delivery; feeding it to the analyzer both duplicates the words and
   advances the clock, shifting every later cue.

4. **The display loop follows `observedPlayer`, not the player it was started
   with, and runs until CANCELLED, not while the engine runs.** tvOS's stall
   fallback REBUILDS the AVPlayer for the same URL (iOS/macOS swap the item on
   one player, which is why only the living room froze): the loop that captured
   the original player read a torn-down clock forever, and the caption at the
   resume position stayed on screen for the rest of the film — the owner's
   exact report. A loop conditioned on `isRunning` was the second freeze: it
   exited when the engine stopped and left the last label text standing.

Also in this wave: the stand-down for the system's generated track is
REVERSIBLE (`draws=false`, engine keeps running; a 45s-quiet watchdog brings
ours back), because on this tvOS beta that track refused to emit through ten
minutes of probing and then emitted mid-film in real playback — flaky in both
directions. Verified end to end on the device: our engine leads with
ground-truth-exact sync ("From cave wall to billboard" shown at t=28.5, spoken
at 28.2–28.4), the system's track took over ~30s in, and 260 consecutive
watchdog windows confirmed it kept speaking.

**How to apply**: `AW_CAPTION_TRACE=1` prints the playhead, every displayed-line
change, throttle transitions, and per-cue raw→film mappings — with the paired-
device loop it turns caption sync into a console read. When two clocks disagree,
cut the disputed film region with ffmpeg and transcribe it locally
(`/tmp/awlive "file:///tmp/region.mp4"`); that transcript is the ground truth,
nothing else is. Cold start is inherent: the scout begins AT the playhead, so
the first ~1–2 minutes after (re)start have sparse captions while the lead
builds — do not "fix" that by showing late-finalized cues (trailing captions
are the failure Decision 058 exists to prevent).


## 070 — The captioned-HLS wrapper is retired on tvOS; the overlay renders the subtitle file
*Date: 2026-08-13*

On tvOS, films with a subtitle file — published in the catalog or fetched on
the device — now play through `ResilientStreamLoader` like everything else,
and the FILE is rendered by the caption overlay (`CaptionCoordinator` file-cues
mode): the VTT is fetched and parsed at start, displayed at the viewer's system
caption preference exactly as the old track's `AUTOSELECT/DEFAULT` did, and
`SubtitleReview` judges it as before — a shift verdict now moves OUR cue times
directly, and preferLive discards the file for the transcript. The
single-segment HLS wrapper (`CaptionedHLSLoader` / `LocalSubtitleHLSLoader`
paths, Decision 039 Config C / 054) is no longer used for playback on tvOS.

**Why**: the wrapper's single MP4 "segment" made AVFoundation treat the ENTIRE
film as its atomic buffering unit. Measured on the Bedroom Apple TV with all
caption machinery disabled: `loadedTimeRanges` climbed to 5,300 seconds — the
whole 575 MB of His Girl Friday — while `preferredForwardBufferDuration` asked
for 300, and the item then died with AVError **-11819 (media services reset)**
at t≈100–117s in three consecutive runs: mediaserverd does not survive
swallowing a feature film on a 3 GB Apple TV. The death was invisible for
weeks because (a) it never happens on a Mac, where every prior verification
ran — the Mac has the memory — and (b) `handleLoadFailure` silently rebuilt
the player, so the visible symptom was only a mid-film "refresh". Worse, the
rebuild left the old player UNDEAD (pause() without detaching the item left
its pipeline running — clock advancing, rate=NaN, for the rest of the
session), and two live pipelines a rebuild-gap apart is exactly the owner's
"stuttering and sometimes repeating lines". The stutter, the refresh, the
restart-from-zero, the double captions and the mistimed captions were all
downstream of this one path.

**How to apply**: never hand AVFoundation a single-segment HLS wrapper around
a feature-length MP4 on a memory-constrained device — a "segment" is the unit
of buffering, and no preference caps it. `teardownPlayer` must
`replaceCurrentItem(with: nil)`, not just pause — measured: pause alone left
the pipeline live. A mid-playback item failure resumes from the exact current
position (persist-then-teardown), not from the periodic writer's last save.
The judge's shift gate accepts a decisive peak-over-zero margin (>0.12) even
under `matchAbove` — His Girl Friday's true offset scored 27% on a sparse
transcript and a "match" verdict showed the file 16s out of sync; the
four-control harness (`tools/test_subtitle_agreement.swift`) still passes.
The freeze guard waits 15s for the FIRST frame (a resume seek legitimately
takes seconds; its 3.5s threshold was nudging — a decoder flush — twice at
every resume point).

**Consequences**: captioned films on tvOS regain Decisions 021/031/034
resilience (they had NONE — the one path with no loader was carrying 16% of
the catalog, including nearly every popular film), scrubbing works (the
single-segment wrapper never could), and memory stays bounded. The native CC
menu no longer lists the file's track on tvOS — the overlay is the renderer;
a transport-menu subtitles toggle is the parity follow-up for viewers whose
system caption preference is off. iOS/macOS keep the wrapper for now (more
RAM, AirPlay handoff uses the published HLS per Decision 051) — but the same
bomb plausibly exists on low-RAM iPhones and the published HLS handed to an
AirPlay RECEIVER (an Apple TV) is still the single-segment shape; both are
open questions this decision deliberately leaves scoped out.

## 071 — The caption scout is MUTED on tvOS; a volume-0 second player races the main audio render
*Date: 2026-08-13*

On tvOS the live-caption scout (`LiveCaptions`, Decision 058) sets `isMuted =
true` instead of `volume = 0`. The audio processing tap still fires under
`isMuted` on tvOS 27 — measured: 23 correctly-mapped transcript cues from a
fully muted scout — so Decision 058's rule ("volume 0, but NOT isMuted:
muting can take the audio out of the render pipeline and the tap never
fires") is a platform fact about iOS/macOS, not tvOS, and those platforms
keep volume-0.

**Why**: the owner reported, across two builds, that "the audio often gets
swallowed by the captioning process" — picture running, captions synced,
soundtrack gone. Every existing diagnostic watches the clock or the buffer,
so a dead audio render with healthy video was invisible from the dev Mac;
an RMS meter tap on the MAIN player (`AW_AUDIO_DIAG=1`, AWAUD lines) made
it measurable. Measured on the Bedroom Apple TV: the main player's audio
render died for 33-34 seconds — video advancing, buffer full at ~200s —
with the dropout bracketed exactly by a volume-0 scout's active life, in
roughly half of the runs. A muted player does not contend for the audio
output; a volume-0 player is a full participant whose start/resume can race
another player's render and silently win.

**How to apply**: never run a second audible-pipeline AVPlayer alongside
playback on tvOS — mute it outright, and verify the tap still feeds (the
AWAUD meter plus cue-mapping traces answer both in one run). Two red
herrings cost hours and are worth remembering. First, `.timeDomain` looked
causal — dropping it "fixed" the race — until a self-identifying print
showed TimeDomain is the tvOS 27 platform DEFAULT, so the bisect arm had
changed nothing and both arms were coin-flips of a ~50% race; a bisect of a
nondeterministic fault needs repeated trials per arm, not one run each.
Second, a verification run measured the OLD binary after an unchecked
install; the scout now prints its pitch algorithm and mute mode so a run
identifies its own configuration. `AVPlayerItemSampleBufferOutput` (the
27 API built for scan-ahead decode without a second render) was evaluated
and rejected: HLS items only, and the scout plays progressive MP4s —
revisit if that restriction lifts.

**Consequences**: the owner's last unexplained symptom on build 899 falls.
tvOS scout behavior is otherwise unchanged (2x, subordinate socket,
throttle/yield, silenceScout detach). Related: 058 (the scout), 069 (the
pitch pin, restored after the herring), 070 (the undead-player mechanism
that taught the detach), and the AWAUD meter joins the permanent
env-gated diagnostics.

## 072 — One tvOS pipeline: every title plays through the resilient loader; the engine is the captioner
*Date: 2026-08-14*

On tvOS, every playback — captioned or not, film or episode — goes through
`ResilientStreamLoader`, and live captioning for uncaptioned titles comes from
OUR engine alone (Decision 068). Retired together: the plain-URL branch
(Decision 067's trade, movie player and episode player both), its
`CaptionStallMonitor`→`forceResilientFallback` safety net, and the
system-caption watch (`SystemCaptions.handOver` + the 45s emission watchdog).
Captioned files render through the overlay (Decision 070) as before.

**Why**: the owner's report on Till the Clouds Roll By named the seams, not a
bug: "drops frames even though it continues to play… captions come in and out
and sometimes make the video pause for a while as it refreshes the stream…
can we stop fixing them one at a time and solve for them as a fully working
system." The film's file is blameless — probed h.264 Main 720p at 1.9 Mbps —
but as an uncaptioned title it took the plain-URL path, which has NONE of
Decisions 021/031/034's resilience: archive.org's idle resets flush
AVFoundation's buffer (the original Decision-021 disease, reintroduced by
067's trade), the stall monitor answers by tearing down and rebuilding the
player mid-film ("pauses while it refreshes"), and the system-caption
watchdog yielded our captions to a generated track that this beta flickers on
and off ("captions come in and out"). Each piece was a rational patch; the
matrix of paths was the disease. What the trade bought — the system's
generated track — was measured on the owner's own Apple TV to be offered and
almost never emitting (Decision 068), while our engine captions the same
films in ~15s.

**How to apply**: on tvOS, do not add a playback path that bypasses
`ResilientStreamLoader` — if a future OS makes the system's generated track
actually emit through a loader-backed asset, revisit 067's trade THEN, with
the emission measured on a device first (offered ≠ selected ≠ emitting — the
lesson is now four decisions old). iOS and macOS keep their current paths:
the system's generated captions genuinely work there (measured text in ~33s
on macOS; the owner rates iOS "extremely well"), so the plain-URL trade still
buys something real on those platforms.

**Consequences**: `forceResilientPlayback` and the plain-path stall wiring in
the tvOS players are inert; the coordinator's engine-vs-system arbitration
on tvOS reduces to "engine leads, nothing else draws". Uncaptioned titles on
tvOS regain resume-on-reset, node pinning, and node failover. The
capability note (a device with no speech models says so once) stays.

Two companions shipped with it, both found chasing the same film on-device:

*Scout depth-hysteresis.* The scout's yield keyed on a binary buffer-health
flag that fires only when the buffer is already gone, and a 5s cooldown
resumed it straight back into the starvation — yield/resync/restart churn.
`throttle` now takes the MAIN buffer's depth in seconds: the viewer banks
120s before the scout may draw bandwidth at all, and it stands down the
moment the bank dips under 60.

*Loader block cache.* A long, oddly-muxed upload (Till the Clouds Roll By's
2 GB card) makes AVFoundation fetch its interleaved sample chunks in TINY
random dataRequests — 669 reads of 64 KB in one soak, each paying 60-180 ms
of request latency: an effective ~3-4 Mbps ceiling on a node that sustains
~100, decoder starving, buffer pinned at 0-4s for minutes. Small bounded
reads are now served from aligned 2 MB cached blocks (24-block LRU = 48 MB —
an 8-block cap THRASHED, the playhead's working set is ~50 MB; the next
block prefetches so the pattern's misses stay off the decode path). The
sequential 8 MB streaming path and every 021/031/034 invariant are
untouched — measured after: buffer sustained 63-103s where it had pinned at
0-4, stalls 5 -> 0, block re-fetches 6-7x -> at most 2x.

## 073 — The judge may not condemn a human subtitle file on a sparse transcript, nor nudge one inside its own noise
*Date: 2026-08-14*

Two asymmetric-caution gates in `SubtitleAgreement.judge`, both paid for by
His Girl Friday's RETIMED (correct) track in build 905: a `preferLive`
condemnation now requires the transcript to have actually heard at least 100
usable words — a session that resumes into music or mumble zero-scores a
perfect file, and one such window discarded the human track mid-film and
replaced it with machine captions ("no longer synced correctly... a huge
step backward"). And a shift smaller than 2.5s is adopted only when
agreement is dense (>=0.45): the judge's own offset noise on a sparse
transcript is ~1.5s, so noise-sized "corrections" were un-syncing a file
that was already right. Big shifts and dense-evidence small shifts still
correct; the 4-control harness holds; on-device re-proof: verdict "match",
10/10 displayed cues byte-matching the published VTT at the playhead.

**How to apply**: every verdict that makes a viewer's captions WORSE if
wrong (condemn, replace, shift) must clear an evidence floor scaled to its
cost, and "no opinion" must remain reachable from every code path — the
absence of proof that a file matches is not proof that it doesn't. When a
verdict varies run-to-run on the same film (match 41% / match 24% / shift
1.3 / preferLive 12% were all observed), that variance IS the measurement of
the judge's noise, and thresholds must sit outside it.

## 074 — Captions are an ECONOMY: every layer yields to playback on measured evidence, and the glass is the test
*Date: 2026-08-14*

The external-observation suite (`tools/atv_scenario.py` + `tools/ScreenOCR` +
the on-device diag file) is now the shipping gate for tvOS caption/playback
work: a scenario launches a film on the paired Apple TV, screenshots the GLASS,
OCRs the caption region, pulls `Library/Caches/awdiag.log`, and grades eight
assertions (app alive to end, no stuck notice, playhead advances, no stalls,
audio continuity, captions on glass, glass-matches-file for published VTTs,
glass-matches-engine otherwise). Six scenario rounds against it produced five
coordinated fixes, each one a layer of the same principle — a second stream
must EARN its bytes, and every claim is measured, never assumed:

1. **Drift bound (lower envelope)**: a seeked scout session on a badly-muxed
   file receives a burst of pre-target audio (+39s of raw clock measured), so
   `film = offset + raw×rate` maps every cue late — and the judge, reading the
   same ruler, condemned His Girl Friday's CORRECT file at 7%. The mapping is
   re-anchored when the 25s lower envelope of (predicted − scoutPosition)
   exceeds 15s. NEVER correct on the instantaneous error: the tap delivers in
   decode-ahead bursts and an instant-threshold corrector flapped 15 times in
   one run, corrupting the ruler in both directions.

2. **Exoneration sweep**: before any preferLive verdict the judge scores the
   file at every offset to ±75s. Unrelated content scores ~3% at EVERY offset,
   so a strong far-out match is fingerprint evidence the file describes this
   film and the fault is OUR clock — keep as published, never shift by a far
   offset. A rulerSuspect session (any drift correction) may keep a file but
   never shift or condemn without a doubled word floor.

3. **Resync = seek, never rebuild**: every stop/start resync built a fresh
   player item whose moov + preload fetch collided with struggling playback —
   stalls clustered 10-32s after each rebuild. `LiveCaptions.resync(to:)`
   seeks the existing scout; one asset per playback. The throttle never
   resumes a scout >45s behind the viewer (2x cannot catch 1x from behind).

4. **Surrender**: a running scout that cannot sustain 1.4x over 25s is in a
   race it mathematically loses — it detaches its item entirely (a paused
   item still buffers), keeps the cues it made, says the true thing once, and
   nothing restarts it that playback. Three playback-trouble episodes are the
   backstop. Gate on OBSERVED harm; a depth threshold alone locked captions
   out of files whose healthy steady-state buffer is structurally low.

5. **Slow-node rotation**: both remaining stalls came with NO second stream —
   single glacial requests (8 MB at 3.6 Mbps for 18.7s) on the pinned node.
   The idle timeout never fires on a trickle and Decision 034 rotates only on
   hard errors, so a slow-chunk watchdog cancels a chunk 6s in with under
   half its bytes and DEMOTES the node (slowHosts, forgiven when all are
   slow) — not blacklisted; 034's timeout rule stands. Resume is byte-exact.

**Why**: ten builds of caption fixes had shipped on self-reported evidence
while the owner kept seeing failures at the glass. The suite inverted that:
every one of these five faults was found by a failing scenario, three of them
in causal chains no console reading would have ordered correctly (condemnation
← drift ← seek-burst; stalls ← restart churn ← a resume that ignored scout
position). His Girl Friday now passes 7/7 repeatedly (108/112 on-glass
captions matching the published cue at the playhead); TtCRB-4K retains
weather-bound stalls on degraded archive.org afternoons even with playback
alone — that residual is a node/derivative question, not a caption one.

**How to apply**: no tvOS caption or playback change ships without a passing
scenario report — the app's own logs are diagnosis, never verdict. When a
scenario fails, read the diag around the failure times before theorizing; every
wrong fix this session came from a plausible mechanism the timeline disproved.
The launch-window app death under 4K screenshot capture is a HARNESS artifact
(observer-induced memory pressure; no crash report, no app jetsam) — the
runner retries once; do not chase it as an app bug without a report naming the
app. Scenario cards resolve by TITLE from the live index, never hardcoded ids.

## 075 — Controlled experiments over correlation: the LAN remux control, and the instrument that manufactured its own disease
*Date: 2026-08-14*

The harness gained CONTROL-EXPERIMENT hooks — `AW_URL_OVERRIDE` (play the
AW_START_ITEM film from any server) and `AW_NO_RESUME` — and their first use
settled a day of contradictory correlations in one run: the same 4K film,
stream-copy remuxed with faststart and served from the dev Mac over LAN
(range-capable server; python's http.server ignores Range and serves
byte-zero garbage that AVFoundation reports as "media damaged"), still
showed 16 metronomic ~10.4s audio gaps. That exonerated the file, the mux,
archive.org, node weather, and the scout (surrendered at 67s) in a single
stroke — and left exactly one rhythmic actor: the audio-meter watchdog,
which revived its dead tap by REPLACING the playing item's audioMix, then
detected the ~10s outage its own replacement caused, forever. Single-attach
control: zero gaps. The meter now attaches once, logs "tap died — no audio
evidence past this point", and never touches a playing item again.

**Why**: three loader interventions (audio-region prefetch, trailing-request
cap at two geometries) were built on correlations — each reshaped the
numbers, none removed the rhythm, because the causal story was wrong twice
over. The "41% wasted re-download" that motivated the runaway cap conflated
BOTH loaders' AWSTREAM lines: the scout's second stream is legitimate reads,
not AVFoundation re-requests. And the "audio dropouts" being chased were
manufactured by the chasing. A controlled experiment that removes variables
wholesale beats a week of correlation on live traffic.

**How to apply**: when a symptom survives three targeted fixes, stop fixing
and build the control that splits the hypothesis space in half. The
harness's audio evidence is now honestly bounded: tvOS tears the audioMix
tap down on heavy-decode items (17s lifetime on the 4K film, six clean
minutes on His Girl Friday) and the assertion grades only the tap's
lifetime — an instrument must say when it is blind, and must never perturb
what it measures (the same observer-effect class as the 4K-screenshot
launch-window deaths in 074). Tag or segregate per-loader diagnostics
before summing them. Keep AWERR/drop counters: zero decode errors across
every run is what kept "corrupt bytes" honestly excluded.

Also this session, from the owner's sofa reports: build 915's slow-chunk
watchdog cancelled at a 5.6 Mbps floor — a normal living-room speed — and
was the real "no video at all" / static / smeared-picture regression (now
0.2 Mbps/10s, a dead trickle only); The Oregon Trail's only file is AV1 in
an MP4 labelled "MPEG4" (no Apple TV can decode it; the Mac-side verifier
can) and now fails with an honest terminal error instead of audio over a
black screen — the codec-aware pipeline audit is queued; and the caption
overlay strips WebVTT markup it was rendering literally.

## 076 — Ship gates run under ADVERSE conditions: Release builds, throttled bandwidth, and playback owes the caption engine nothing
*Date: 2026-08-15*

Three standing rules born from the owner's report that build 925 made every
title without a subtitle file unplayable — a regression that passed every
harness gate, because every gate ran under conditions the failure needed
absent:

1. **The caption engine is a passenger, never a driver.** For a film with
   no subtitle file the engine ARMS at play-start but IGNITES only after
   playback has proven the link can afford a second stream (60s banked or
   30s healthy). On a link that can never afford it, captions are simply
   absent — no spinner, no notice, playback identical to a captioned
   title. Measured why: at ~10 Mbps the scout's startup probe + the AV1
   check's moov fetch + the player's own startup collided and the item
   load TIMED OUT — "unable to play," on every uncaptioned title, while
   captioned titles worked. That asymmetry was the owner's exact report
   and the diagnosis in one line.

2. **Ship gates run under the conditions viewers actually have.** Every
   fix through 925 was validated on Debug builds at whatever bandwidth
   archive.org happened to offer — usually 40-240 Mbps. The failures all
   needed ~10 Mbps to appear. `tools/throttled_range_server.py` (token-
   bucket range server; python's stock http.server ignores Range and
   feeds AVFoundation garbage) + `AW_URL_OVERRIDE`/`AW_NO_RESUME` make a
   bad morning reproducible ON DEMAND. A tvOS playback/caption change now
   ships only after a RELEASE-configuration scenario AND a 10 Mbps
   throttled run. The gate earned its keep the first day: it caught the
   loader fetching every byte 2-3x (AVFoundation walks an interleaved
   file with separate audio and video cursors over the same bytes, each
   served a private copy), which no fast-network run ever showed.

3. **Streaming delivery for the leading request is load-bearing** (the
   Decision 031 invariant, re-proven from the other side). Routing ALL
   requests through the shared block cache fixed the 2x duplication but
   held startup bytes hostage in whole 2MB blocks — 29s first-block
   fetches under slow-TTFB contention, item timeout, "unable to play"
   again. The follow-up that gets both (share bytes across cursors AND
   stream them as they arrive) is streaming block fills; it ships only
   through the throttled gate.

Also in the record: the slow-chunk watchdog is DELETED (regressed twice —
a 5.6 Mbps floor killed normal wifi; a 0.2 Mbps floor killed legitimately
slow startup probes; the 12s idle timeout already covers dead
connections). Failure notices are honest and bounded: "no audio to
transcribe" only when the track load SUCCEEDS and finds none, and
"Preparing automatic captions" expires at 45s. Harness caveats: launches
under 4K screenshot capture get the app SUSPENDED (no crash report, the
capture daemon jetsams for its own limit) — verify app behavior with
console-attached launches, use capture scenarios for glass evidence;
reboot the device between long harness sessions.

## 077 — A film starts within 30 seconds, or falls back to a copy that can (amends 021's no-downgrade rule)
*Date: 2026-08-15*

Owner decision, verbatim intent: "Fallback is only appropriate when the full
version isn't feasible. Please implement that change. Films should start
within 30 seconds. Waiting longer than that will lose users almost every
time." The player's load budget is now 25 seconds, and a startup failure
with a vetted fallback in hand switches to it IMMEDIATELY — never a retry of
the URL that just proved unservable. The chain: catalog-baked
`fallbackVideoURL` → a smaller archive-generated derivative on the same item
(prefetched during the load attempt by `ArchiveFallback`) → one retry of the
primary → an honest error naming the Archive's servers. Mid-film failures
never switch copies; resume stays seamless on the copy the viewer started.

**Why**: Decision 021 rejected bitrate ceilings so quality would never be
silently degraded — but it never considered a source that cannot serve the
file's bitrate AT ALL. Measured 2026-08-15: archive.org's US datacenter
served Till the Clouds Roll By's 5.7 Mbps 4K file at 2 Mbps with 25-second
first bytes, and the film's 720p sibling upload at 1.7 Mbps from the same
datacenter — no player on earth streams that. The old behavior (60s timeout,
same-URL retry, generic "request timed out" after two minutes) was honest
about nothing and lost the viewer every time. A watchable 845 MB copy of the
same film existed in the catalog the whole time.

**How to apply**: identity vetting happens in the PIPELINE, never at runtime
(Decision 026): `tools/bake_fallbacks.py` pairs each heavy item (>1.5 GB,
1,685 of them) with a meaningfully-lighter same-imdbID sibling copy — the
duplicate uploads Decision 040's merge collapses at DB-build time remain in
catalog.json with their URLs — else a same-item archive-generated derivative
(those are h.264 by construction; an uploader original labeled "MPEG4" can
hide AV1, which no Apple TV decodes — The Oregon Trail). Every candidate is
liveness-probed before baking (Decision 056). The field rides `item_json`,
additive per Decision 020. Runs in publish-db daily (new ingests only —
idempotent). Never fall back for a mid-film failure, and never fall back to
a copy that is not the SAME film by pipeline-vetted identity. tvOS shipped
first (1.3.407/929); iOS/macOS/Android/web parity is open work, as is a
small on-screen note when a fallback is playing.

**Consequences**: the app's honest terminal error ("The Internet Archive's
servers are struggling with this title right now...") appears only when the
best copy AND its fallback both fail to start — roughly 50 seconds worst
case, inside the owner's tolerance for a genuine outage. The 4K copy remains
the default every time; the fallback costs nothing until the moment nothing
else would have played.

## 078 — Watch history is a durable, union-merged record; progress is merely its most recent line
*Date: 2026-08-15*

Every playback on every Apple platform records through ONE write path,
`WatchProgress.record(in:)`: resume position (as before), plus firstWatchedAt,
playCount (a new session = a >6h gap between writes), and everCompleted /
completedAt. everCompleted is durable — once a title has been finished it is
"watched" forever, because before it existed a REWATCH reset the position and
silently erased the title's watched status on every synced device. Channel /
lineup tune-ins (ephemeral) now enter the history after 60 seconds of viewing
— dates and session count only, never position — so the record is complete
while Continue Watching keeps its no-channel-pollution invariant. The tvOS
Library gains a History section: every title ever played, most recent first.
CloudKit's merge treats history as a UNION (earliest first-watch, highest
play count, completed-anywhere = completed-everywhere) while position stays
last-writer-wins by lastWatchedAt.

**Why**: owner, 2026-08-15 — "a full record of every movie/video you have
ever watched and the ability to resume them from wherever you last stopped...
easy to see... no matter where you are or which device... the same across all
Apple devices." The store already synced positions; what it lacked was
durability (rewatches erased history), completeness (channels recorded
nothing), and a surface (nothing listed the full record).

**How to apply**: never persist progress with hand-rolled fetch/update code —
call `WatchProgress.record`; three platforms had three divergent persist
bodies and any future semantic lives in the helper once. History fields merge
as a union, NEVER last-writer-wins — two devices each know something true and
the merge must lose neither. All fields are optional so old stores migrate
lightweight and old sync payloads decode unchanged (the additive rule,
Decision 020, applied to SwiftData + the AWSync blobs). Proven on-device on
the Release build: record → relaunch → resume at the exact position.

**Consequences**: iOS/macOS Library History surfaces, Android/web local
history, and PARITY rows are open work. Cross-ecosystem sync (Android/web
seeing the same record) rides Decision 028's Google Drive App Data plan and
remains blocked on the owner creating the Google OAuth client.

## 079 — The Quality Program: research-first rebuild of playback, captions, sync, and choice
*Date: 2026-08-17*

Four commissioned research reports (docs/research/*.md, sources cited,
verified-vs-inferred marked) and their synthesis
(docs/PLAYBACK-ARCHITECTURE-RESEARCH.md) become the binding plan, with the
owner's approvals and one binding condition:

1. **LocalMediaServer** (loopback NWListener HTTP server fronting the ported
   ResilientStreamLoader engine) is approved UNDER THE NATIVE-FIRST
   CONDITION, owner verbatim: "if it in any way replaces the native APIs or
   makes it harder to take advantage of the native tools that Apple
   provides for its video apps, please research better/native solutions."
   The research's answer, recorded as the design rule: the proxy EXISTS to
   restore native-tool compatibility (a localhost URL is a plain HTTP asset;
   the custom scheme is what disqualified AirPlay, generated captions, and
   AVAssetReader), and the design must prefer DIRECT native playback for
   files verified compliant and well-served — the proxy is the resilience
   layer, not a replacement for native playback. Cutover gates: on-device
   proof that generated captions emit through the proxy; byte-diff vs
   origin over a full film; scenario suite green at full speed AND through
   the 10 Mbps throttled gate.
2. **History UX approved**: ONE History list (chronological dated plays);
   Watched becomes a derived badge on posters + a Detail toggle, never a
   second content list. Continue Watching stays. (The Trakt model.)
3. **Repair-and-rehost approved**: `archivewatch-fix-<slug>` items under
   the owner's archive.org account, only for the popular tail with no
   playable copy, clearly labeled as repairs linking the source item.
4. **alass + ffsubsync approved** as the catalog-wide subtitle-timing
   fixers (VAD-based, CI-runnable, applied only on ≤0.5s agreement); the
   on-device SpeechAnalyzer judge remains the runtime safety net and the
   only tool that can condemn a wrong-film file.

Per-platform nativeness reaffirmed (owner): tvOS built for tvOS, iOS for
iPhone, Android for Android — Decision 028's doctrine governs every phase.

**How to apply**: no playback/caption/sync architecture change ships outside
this plan without a new research pass (memory: feedback_research_before_fixes).
The phase gates are Decision 076's Release-build + throttled-gate scenarios.

## 080 — A subtitle file that ends after its film is provably mistimed; that one fact carries the whole detector
*Date: 2026-08-17*

Subtitle timing gains a second, independent fault class alongside Decision
062/064's constant offset: **drift**. `tools/audit_subtitle_rate.py` flags a
published file when its last cue ENDS after the film does — physically
impossible, so mistimed regardless of cause — and `tools/fix_subtitle_rate.py`
repairs the telecine subset by rescaling every cue by 23.976/25, gated on the
result landing inside the runtime, monotonic, cue-count unchanged. 44 files
repaired and published this pass; the corrections reach web, Android and every
Apple platform through the existing `subs.tar.gz` path with no app build.

**Why**: the owner reported Earth vs. the Flying Saucers' subtitles as
"incredibly poor". Measured — the file's last cue ends at 4994.8s on a
4818.7s film, 176 seconds past the end. Against speech transcribed locally at
two points 50 minutes apart it ran +51s late at the quarter mark and +184s
late near the end. It has no offset; it DRIFTS, because it was authored at
25fps and laid over a 23.976fps transfer. Decisions 062/064 search for one
constant offset and are structurally blind to that — no constant is right for
a file that is 0s off at the start and 200s off at the end, which is exactly
why every prior sweep left this film broken.

The repair is arithmetic, and that is measured rather than assumed: rescaling
by 23.976/25 matched the answer ffsubsync derived from the real audio to
within 0.4s at four points spanning the film. So this class needs no
download, no audio and no speech models, and runs in CI — lifting the
local-only constraint that has throttled Decision 064's sweep.

**How to apply**: detect on PHYSICS, never on pattern. The inference "ends
early at a telecine ratio" was built, measured, and DELETED: across 3,726
published files the distribution of (last cue end / runtime) is smooth and
rises monotonically toward 1.0 with NO spike at 0.9590, so a film with ~2:45
of end credits lands on that ratio by coincidence — the inference would have
rewritten 95 files with no evidence they were wrong (reefer_madness1938 is
one). Precision over recall, as in Decisions 035/064: leaving a bad file
alone costs captions on one film; rewriting a good one breaks a film that
worked. Read the cue END, not its start — reading the start mis-flags a
correct file whose final cue ends right at the runtime. Choose the tool by
fault class: alass models drift as splice shifts and pushed this same film's
last cue to 5176s, 344s WORSE than doing nothing; ffsubsync detects a
framerate scale and is the right tool when audio is available.

**Consequences**: the ratio gate is deliberately conservative and MISSES
films with end credits — Earth vs. the Flying Saucers itself reads 1.0366
rather than 1.0427 and had to be repaired from its audio-verified ffsubsync
output. 379 files are proven mistimed, 44 arithmetically repairable; the
remaining ~335 need the audio sweep (ffsubsync is VAD-based, so unlike
Decision 064 it needs no speech models and CAN run in CI — the cost is the
film download, popularity-first and resumable like every other sweep here).
A separate finding, not addressed: ~3% of popular captioned films advertise a
subtitle track whose VTT 404s — a dead promise the app currently makes.
`subtitleRateAudit` is an additive key older clients ignore.

## 081 — A drift correction may not rewind the captions past the viewer
*Date: 2026-08-17*

`LiveCaptions.driftCheck` clamps its re-anchor so the earliest not-yet-shown
cue still lands at or after the furthest playhead the display has reached, and
skips a correction that clamps to nothing. `line(at:)` tracks that playhead.

**Why**: the owner reported The Incredible Machine's generated captions as
undependable — a film with no subtitle file, so this is our engine's own
output. Traced on the Apple TV (`AW_CAPTION_TRACE=1`), the engine looked
healthy: lead built to 121s, no surrender, coherent text. But it corrected
drift THREE times in four minutes, and correction #3 re-anchored by -12.4s,
after which LATER audio mapped EARLIER than what had already been shown:

    cue raw 190.8-191.9 -> film 349.5-351.8   "Basically visual creatures."
    drift correction #3: re-anchored by -12.4s
    cue raw 192.0-194.3 -> film 339.5-344.2   "of all our information through our"

Ten seconds backwards. The schedule then re-crossed ground the playhead had
left, so fragments displayed out of order and lines went missing — which is
exactly what "undependable" looks like from the sofa, on an engine whose text
was fine.

Decision 074 added the correction for a real fault (a seeked scout receives a
burst of pre-target audio and every cue maps late) and was right to. What it
did not bound is the direction: subtracting from `contentOffset` shifts EVERY
cue, including ones already on screen, and nothing stopped the result landing
behind the viewer.

**How to apply**: the mapping running ahead is worth fixing; dragging cues
behind the playhead to fix it is not — a caption that arrives late can still
be read, one that arrives for a moment already passed cannot. Measure the
property, not the symptom: the assertion is "no mapped cue time regresses",
computed from the trace, which is what separated this from the blank ticks
that sit beside it (~32% of ticks, unchanged before and after, and inherent —
silence and music produce no cues). Never judge a correction by whether it
fired; judge it by whether the schedule stayed monotonic.

**Consequences**: measured on the same film, same conditions — 2 backwards
jumps (worst -15.0s) before, 0 after, with 5 clamps firing. Corrections still
happen (4 in the after-run); they are simply bounded now.

## 082 — The LocalMediaServer passes every Mac gate and FAILS on the device; Phase 1 does not cut over
*Date: 2026-08-17*

Decision 079's Phase-1 keystone — a loopback HTTP server fronting the
resilience engine, so AVPlayer sees a plain `http://127.0.0.1` asset and every
native media feature becomes eligible again — is **not** promoted to the
default path. It stays behind `AW_PROXY_EXP=1`. The Mac gates all pass; the
Apple TV does not.

**Why**: measured. Mac-side, against a local range server so archive.org is
never storrmed, the proxy is byte-identical to origin across a FULL
472,697,906-byte film (0 mismatches), across 72 concurrent interleaved reads
in the two-cursor pattern AVFoundation issues on a badly muxed file, and
through the Decision-076 10 Mbps throttled gate — where the player still
advances 5.9s in 6s. On the device, three runs of the same film gave three
different outcomes:

    run 1   played 5 minutes, 0 stalls, buffer 200s+, system caption
            track OFFERED and SELECTED through the proxy
    run 2   itemFailed x2 at t=0, NSURLError -1008 "resource unavailable"
            (OSStatus -16848); the film never started
    run 3   proxy listening, item created, then NOTHING for 3.5 minutes —
            no ready, no failure, no buffer telemetry

**How to apply**: the harness validates the SERVER, in-process, where the same
process both serves and plays. On tvOS the consumer is `mediaserverd`, a
SEPARATE process reaching the app's loopback listener, and that hop is what
the Mac never exercises — a byte-perfect server proves nothing about it. Do
not read a green harness as readiness for a path whose defining hop it cannot
test. If this is picked up again, the first question is not the server's
correctness (settled) but whether a third-party tvOS app's loopback listener
is reliably reachable by mediaserverd at all, measured over many runs — one
success proves nothing when the failure is intermittent.

**Consequences**: tvOS keeps Decision 072's single pipeline —
`ResilientStreamLoader` for every title, our own engine captioning the
uncaptioned. That path is what the owner is running and what the last several
verified fixes were measured against. What the proxy would have bought (native
generated-caption eligibility) is worth little here anyway: Decision 068
measured the system's generated track as offered but never emitting on this
beta, and run 1 above reproduced exactly that through the proxy. The stress
harness earned its keep regardless — it is what exonerated the delivery path
for the owner's audio-static report.

## 083 — `excluded` is shared state: a tool that hides items must register its marker, and the reconcile must say when one hasn't
*Date: 2026-08-18*

`audit_rights.py`'s FOREIGN list now includes the playback verifiers'
markers — `playbackDead` (check_liveness: the video is gone) and
`playbackReason` / `strictFail` / `needsReSource` (verify_playback_strict: no
moov atom, mdat past EOF) — plus `codecUnsupported` (audit_codecs: AV1/VP9 no
Apple device decodes). The reconcile also PRINTS any unregistered
exclusion-looking marker it un-hides.

**Why**: `excluded` is written by six tools and reconciled by one. On every
publish `audit_rights --apply` restores anything that is no longer a rights
hide, skipping markers other tools own — and three tools had never been added
to that list. Measured on a normal build:

    un-hid items carrying UNREGISTERED exclusion markers:
      playbackDead x253  playbackReason x636  strictReason x384  posterDead x3
    [apply] excluded=7369 un-hidden=676

So films MEASURED unplayable — dead video, truncated files, codecs no Apple
device can decode — were being restored to every surface on every build, for
as long as those verifiers have existed. Both workflows reported success
throughout. This is the owner's oldest complaint ("all titles visible in the
app should play") with a mechanism behind it, and it was invisible from the
playback code because nothing in the app was wrong.

After registering: un-hidden 676 -> 40, served DB 31,652 -> 31,138 items, and
zero visible films carry any of the four markers.

**How to apply**: a new tool that sets `excluded` MUST add its marker to
FOREIGN in the same change, or its work lasts exactly until the next publish.
Judge a candidate by its VALUE DISTRIBUTION, never its name: `strictReason`
looks like a failure marker and was in the first draft of this fix, but 20,629
of the 26,163 items carrying it say `decoded` — it records the verifier's
outcome, and registering it would have frozen most of the catalog against
legitimate rights un-hides, a worse bug than the one being fixed. `posterDead`
is excluded for the same reason: it demotes a poster, it never hides a film.
The printed warning finds candidates by name because that is cheap and catches
the omission; deciding which are real is a judgement the warning cannot make.

**Consequences**: the warning is the durable part — the next tool to forget
gets named on the next build instead of silently losing its work. Two markers
remain unregistered ON PURPOSE and will keep appearing in that line; that is
correct, not a leak.

## 084 — Record the EVIDENCE, not just the verdict; a colour reading vetoes a merge only when it is confident
*Date: 2026-08-18*

`classify_color.py` now stores `colorSat` — the measured saturation — beside
`colorMode`, and the two consumers that act on a B&W reading require it to be
CONFIDENT before they do anything destructive: `build_sqlite._color_compatible`
(Decision 040's guard, which refuses to merge two same-titled copies whose
colour disagrees) and `verify_external_match.py`'s Tier 3 (Decision 026, which
CLEARS a match's artwork and year when a B&W film is matched to a modern
release). Confident means outside 4.0–14.0; a missing `colorSat` counts as
confident, so every item measured before today behaves exactly as it did.
An upload that says "colorized" in its title or id still blocks a merge
whatever its chroma reads — a stated version difference beats a statistic.

**Why**: the owner has reported duplicate cards twice. Auditing the shelves
found 36 films split into two cards purely by a colour disagreement, and the
merge rule was behaving correctly on incorrect data. Decision 025 called the
saturation split "decisive" on a calibration set where it is — a clean B&W scan
reads 0.0 and a healthy colour print 15–25. It is not decisive everywhere.
Measured against films whose real colour is a matter of record:

    Lonely Wives (1931)        B&W     SATAVG 0.00   <- the clean case
    Not of This Earth (1957)   B&W     SATAVG 9.00   -> read as COLOR
    Scared to Death (1947)     COLOR   SATAVG 7.10   -> read as BW (Cinecolor)
    Eagle in a Cage (1972)     COLOR   SATAVG 7.65   -> read as BW
    Death Rides a Horse (1967) COLOR   SATAVG 8.49   (frames spanned 2.1-15.8)

A B&W film reading HIGHER than a colour one is not a threshold wanting a nudge;
it is two populations that overlap in this statistic, and no amount of extra
frames separates them — one film's frames alone spanned 2.1 to 15.8. Chroma
percentiles were tried and overlap too (SATHIGH: colour 11.0–23.3, B&W 0.0–10.0).
So the fix is not a better threshold, it is admitting when the measurement does
not know: a guard should abstain on weak evidence rather than veto on it.

The reason this was invisible is the part worth generalising. `colorMode` stored
the verdict and discarded the number, so a coin-flip at 8.1 was indistinguishable
downstream from a certainty at 0.0. The same shape sits next to it: `matchVerified`
stores `True` and not which tier fired, so the blast radius of Tier 3 cannot be
counted from the catalog at all — 781 items are `bw` with a year ≥1970 and
therefore eligible to have had their artwork and year cleared on a reading that
may have been a coin-flip, and there is no way to tell which. Decision 056 was
the same lesson in a different field: `playbackVerified` recorded THAT a title
played and not WHEN, so a check three months stale looked identical to one made
yesterday.

**How to apply**: when a pipeline step makes a judgement from a measurement,
persist the measurement. A downstream consumer cannot weigh a verdict it cannot
see the evidence for, and a threshold that is right for most of a population is
a coin-flip for the part of it that lands near the line — which is exactly the
part that surfaces as a user-visible defect, because that is what a disputed
case IS. Do not widen the confidence band to "fix" more duplicates: the guard's
real job (keeping a B&W original apart from a colour remake) is asserted by
`tools/test_color_guard.py`, whose first row is the negative control — a clean
B&W reading against a clean colour one must STILL block. Re-measure a disputed
set with `classify_color.py --ids-file` (ids from `audit_color_disputes.py`),
never a full re-sweep: probing 30,000 items to settle 70 is the kind of local
archive.org sweep that has stalled the owner's Apple TV.

**Consequences**: nothing changes until the disputed readings are re-measured —
the relaxation is keyed on evidence that does not exist yet for any item, which
is what makes it additive (Decision 020). `color-classify.yml` gained a
`recheck_disputed` input that measures exactly the disputed ids. `colorSat` is
an additive JSON key the clients ignore. The other consumers of `colorMode` —
Cartoon Mode's colour preference and Party Play's B&W exclusion — are unchanged
and want no confidence gate: preferring colour on a weak reading costs a viewer
nothing, where clearing a film's artwork on one is destructive.

**Amendment (same day, found by relaxing the above)**: two further faults, both
of which the colour flag had been hiding.

*The guard is TWO gates, not one.* `_color_compatible` tests an edge between two
copies; `_consistent` tests the component they form, and it rejected any mixed
colour group outright. Relaxing only the edge changed nothing — the pair passed
and the component was thrown away. Both gates now abstain on the same evidence.
Whenever a rule exists at two levels, a change to one is a no-op until the other
agrees, and a no-op that looks like a fix is worse than no fix at all.

*An item a series spine owns must NEVER merge as a film.* `merge_film_duplicates`
clustered on `contentType in _FILM_TYPES`, and an episode is still typed as film
in `catalog.json` until the DB materializes it (Decision 045) — so spine-owned
episodes were in scope the whole time. Three seasons of "It Takes a Worried Man"
share a title, share a 1,800s runtime, and sit inside the year span every film
test allows, so every test says one work: `tools/test_color_guard.py` measures
that unguarded they collapse to ONE card, deleting two seasons. The only thing
that had ever kept them apart was an accident — their colour readings happened
to disagree. `_playable_episode_aids()` is now resolved BEFORE the merge and
passed in as an exclusion set.

**How to apply**: never let a film-level rule run over items the TV spines own —
cluster on ownership, not on the contentType the catalog happens to carry at
that moment. And when relaxing a guard, look for what else that guard was
accidentally protecting: it had two jobs and only one of them was written down.

## 085 — A merged-away id forwards to its survivor; a favorite must not vanish because a duplicate was collapsed
*Date: 2026-08-18*

`build_sqlite` now emits an `item_aliases(oldID, newID)` table recording where
every copy collapsed by Decision 040's duplicate merge went, and `CatalogDB`
consults it whenever a saved id fails to resolve — in `item(_:)` (Detail, deep
links, Top Shelf resume) and `itemsByIDs(_:)` (Favorites, Continue Watching,
playlists, history). Aliases are chased transitively, so a copy merged into a
copy that was itself merged still forwards to the final survivor.

**Why**: Decision 040 collapses re-uploads of one film into a single best card
and DROPS the losers from the item list. Nothing recorded where they went —
`duplicateMergedInto` appears in `audit_rights.py`'s FOREIGN list but is never
written by anything. Both library surfaces resolve strictly by id
(`dbItemsByIDs`, `dbItem`), and an unresolvable id is silently filtered out. So
a viewer who favorited or was part-way through a losing copy loses it: the
favorite disappears and the watch position is gone, while the film is still in
the app, one row away, under the survivor's id. Nineteen ids were merged in the
2026-08-18 colour pass alone, on top of ~208 (Decision 040) and ~360 (040a)
earlier — every one a potential silent deletion from somebody's library.

Nothing about this is visible from the playback or library code, because
nothing is broken there: the query is correct, the row is genuinely absent, and
the disappearance looks like the viewer never saved it.

**How to apply**: any pipeline step that DROPS an item a viewer could have
saved must leave a forwarding address — favorites, playlists, watch progress
and Top Shelf resume are all keyed by `archiveID`, and dropping one is a
deletion from the user's data, not just the catalog. Filter aliases to
survivors that actually exist in the built DB before inserting, so a forwarding
row can never point at another hole. Keep the un-aliased lookup
(`itemsByIDsDirect`) for resolving the survivor itself, or resolution recurses.
This does NOT apply to `excluded` items (Decisions 027/044/083): those are
hidden deliberately — a rights or playability judgement — and forwarding a
viewer to a different film would be worse than the item being gone.

**Amendment 2026-08-20 — the OTHER dedup path had no forwarding at all.**
`item_aliases` was populated only by `merge_film_duplicates`. `dedupe_by_imdb`
runs BEFORE it, drops every non-winning copy that shares an IMDb id, and
recorded nothing — **6,158 ids on the live catalog against the 551 the alias
table covered**, an order of magnitude more silent deletions than the path this
decision was written for. Found by asserting that a restored film was reachable
by its own archiveID and getting a FAIL: the film was visible, under a better
id, and the id I asked about had been dropped with no forwarding address.

Both maps are now unioned and chased as ONE, because the paths compose — an id
dropped by the imdb dedup forwards to a winner a later film merge may itself
drop, and chasing each map separately dead-ends on exactly that hop. Measured:
551 -> 5,395 alias rows, 0 pointing at a dead id, 0 self-referential, and every
one of the 1,325 ids still without a forwarding address is an `excluded` item
whose whole IMDb group is hidden — nowhere to forward, and forwarding a hidden
item to a different film is what this decision already forbids. Zero VISIBLE
items are stranded.

Forwarding now exists on EVERY platform, which it did not before: the Apple
`CatalogDB` had it, **Android downloaded the same SQLite and never queried the
table**, and web could not — its data plane is `catalog-index.json` plus detail
shards, so `build_sqlite --aliases-out` emits `aliases.json` beside the index
and `watch.js` fetches it LAZILY, only when a saved id actually misses (~300 KB
against a 6.2 MB index; a miss is rare, so paying it on every page load would be
the wrong trade). Web's detail route REDIRECTS to the survivor rather than
patching the row, so Details, playback and the favourite toggle all land on the
canonical id. Two traps worth keeping: Android's alias query is wrapped in
`runCatching` because a device holding a cached DB from before the table existed
has no aliases — an older catalog, not an error (the Apple twin gets this free,
since `pairRows` returns `[]` on a failed prepare) — and its queries run
SEQUENTIALLY, never nested, because the `Mutex` in `dbCall` is not reentrant.

**Consequences**: `item_aliases` is a new table older clients simply never
query, so it is additive per Decision 020. It is small (hundreds of rows) and
rebuilt from scratch every publish, so it stays consistent with whatever the
current merge decided. Cross-device sync is unaffected — the saved id is still
the old one, and each device forwards it locally at read time.

## 086 — A shelf that declares itself television may contain television
*Date: 2026-08-18*

`CatalogDB.shelf()` takes `allowStandaloneTV`, set by any shelf whose
featured.json declaration says `"category": "tv-series"`, and for those shelves
it drops `tv-special` from the exclusion list. `tv-episode` stays excluded
everywhere on Home — a loose episode belongs to a series and should be reached
through it (Decision 045). Film shelves are untouched.

**Why**: four Classic TV shelves have never rendered a single tile. `1950s
Television`, `1960s Television`, `1970s Television` and `Classic Television` are
declared in featured.json, filled by the pipeline every day — 463, 279 and 253
members, all playable, all carrying designed artwork — and `notStandaloneTV`
excluded `tv-special` from EVERY shelf, which is their entire membership. The
queries returned zero, the shelves fell under `minPerShelf = 9`, and Home simply
omitted them. Measured after the change: 381, 246, 227 and 950 eligible tiles.

Nothing failed. The SQL was valid, the rows were really excluded, and a hidden
shelf looks exactly like a shelf that was never configured. This is the third
appearance of one shape — a WHERE clause that contradicts the surface's own
purpose. The Classic TV browse tile returned zero for weeks the same way
(2026-06-11), and Decision 050's Hidden Gems was empty on four platforms for
five weeks. `browseSQL` already carries the fix for its half: "when the caller
EXPLICITLY asks for tv-series, they ARE the result set." `shelf()` never got it.

**How to apply**: an exclusion written to keep a content type OUT of the wrong
surface must not apply to a surface that exists FOR that type — check whether
the caller asked for it before filtering it away. The declaration is the signal
here and it was already in the data: featured.json states each shelf's category,
so the shelf itself says what belongs in it. Do not extend this to `tv-episode`
to make a shelf look fuller. When a shelf is hidden by `minPerShelf`, ask
whether it is genuinely thin or whether something upstream is emptying it —
hiding is a presentation rule, not a diagnosis.

**VERIFIED ON THE DEVICE** (2026-08-18, Bedroom Apple TV, Debug build of
1.3.433): an OCR sweep of Home found "1950s Television", "1960s Television",
"1970s Television" and "Classic Television" on the glass, each with a full row
of tiles carrying designed artwork — Captain Video and His Video Rangers, Date
with the Angels, The Eve Arden Show, Stingray, T.H.E. Cat, Ozzie and Harriet.
Screenshot evidence, not the app's own report (the standing rule for tvOS).

**Consequences**: four shelves appear on Home for the first time, on tvOS, iOS
and macOS (all three share `CatalogDB`). Android and web query the same DB and
need the same conditional to match — a parity follow-up. `editors-picks` remains
hidden with 5 eligible items against the 9-tile minimum: that one really is thin,
and the fix is editorial — more curated picks in featured.json — not code.

## 087 — A TV match whose era contradicts the item's OWN collection is cleared
*Date: 2026-08-19*

`verify_external_match.py` gains Tier 0b: for a standalone TV item (no series
spine) whose archive.org collection states a decade — `classic_tv_1950s` and
friends — ask TMDb what the matched work actually is, and if its first-air year
falls more than 15 years outside that decade, clear the artwork and the external
ids. `--era-only` targets exactly the judgeable set; `TMDB_BEARER_TOKEN` is wired
into `verify-matches.yml`, and without it the tier abstains and says so.

**Why**: a 1950s game show was on the owner's Apple TV wearing the poster of the
2012 anime *Another*. The item's year had already been cleared for being
impossible, but the poster came from the same match and stayed. Every existing
tier abstained on it correctly — no Archive imdb id, no Archive date, no year for
the colour gate — so the tool held no evidence at all. The evidence it was never
asked for is what the match POINTS AT.

The signal has to come from the item, not the match: the collection dates it,
independently, and 194 of the 211 suspicious items carry one. Measured over the
full set before shipping — 29 of 203 contradicted, and reading the list settled
it: "Howdy Doody's Christmas" matched to a 2026 title, the Nixon–Khrushchev
Moscow debate to "Nixone" (2018), "The Big Lift" to *Dash Kappei* (1981), "Secret
Mission" to a 1990 Arabic series. One pattern throughout — a short or generic
title fragment matched to a modern series with a similar name.

**How to apply**: query **/tv only**. A first draft tried `/movie` then `/tv` and
produced five false positives out of twelve, because a TMDb id is namespaced by
type — movie 3002 and tv 3002 are unrelated works, so The Benny Hill Show
"contradicted" its 1950s collection with 1999. Asked of `/tv` it answers 1969 and
agrees. Never widen the endpoint for coverage: an id that 404s on `/tv` is one we
cannot interpret, and abstaining is the answer. Clear artwork and ids only, never
guess a replacement — a bad match must degrade to the item's own Archive frame,
not to a different wrong poster. And note the marker trap: `is_candidate` skips
anything already `matchVerified`, so a NEW tier judges nothing until the marker
is bypassed (the first run reported zero for exactly this reason). `--era-only`
narrows the target SET, not the tiers — those items are re-judged by all of them.

**VERIFIED ON THE DEVICE** (Bedroom Apple TV): the 1950s Television row now reads
I Love Lucy 1953, Morey Amsterdam Show 1950, Robert Montgomery Presents 1956,
Captain Video, The Eve Arden Show 1957, The Roy Rogers Show — every item
era-appropriate, every poster its own show, no anime.

**Amendment 2026-08-20 — the imdb half, and two ways it did nothing first.**
The tier now also resolves an `imdbID` through OMDb, which needs no new secret
because this tool already holds an OMDb key. Verified in the served DB: Siskel &
Ebert's *Man Trouble* episode (matched to a 1930 film), *The Long Trail* from
Schlitz Playhouse (a 1917 short), a Paul Revere segment (a 1930 German feature)
and the 1975 sitcom *Two's Company* (a 1936 film) all lost their artwork and
ids, while The Johnny Carson Show (1953), The Sound of Jazz (1957), The Benny
Hill Show (1969) and Newhart (1982) kept theirs. Every one of the cleared five
was OMDb `Type=movie` — a television programme matched to a FILM.

Unlike the tmdb path there is no cross-type collision to guard against: an imdb
id names one work, where a tmdb id is namespaced per type.

It reported almost nothing TWICE before it worked, both times because a
selection step upstream never handed it the population — `is_candidate` skipping
anything already `matchVerified`, then `--era-only` still requiring a `tmdbID`
after the lookup had been widened. Neither failed; both returned a small number
that looked like a finding. When a new rule reports a suspiciously low count,
check what was actually offered to it before believing the count.

**Consequences**: 46 cleared of 447 on the first run, alongside 22 `cleared_year`
and 6 `cleared_bw` from the pre-existing tiers finally reaching items the marker
had hidden. Two judgement calls sit at the 15-year line and are the rows to
revisit if it is ever tuned: Doctor Who matched to the 2005 revival rather than
the 1963 original, and Betty White Show, where 1954 and 1977 series share a name.

## 088 — A liveness check expires; `posterChecked` gets a visibility-tiered TTL
*Date: 2026-08-20*

`validate_posters.py` records `posterCheckedAt` and re-checks an item once its
check goes stale: 14 days for anything eligible to lead Home (designed art,
playable), 90 days for the tail. Targets sort oldest-check-first within
popularity, so the catch-up drains the least-recently-verified rather than
re-walking the same head nightly, and the existing `--limit` bounds it.

**Why**: `posterChecked` was a permanent boolean, so the nightly guard reported
**"0 posters to verify"** against a 40,715-item catalog — it had verified
everything once and could never look again. Meanwhile a probe of 60 Home-eligible
posters found 2 already 404, both `m.media-amazon.com`, which rotates its image
hashes continuously (Decision 044 measured ~62% of omdb posters dead). A poster
alive in June is not evidence about today, and the guard built to catch that had
quietly switched itself off.

This is Decision 056 one field over — there `playbackVerified` recorded THAT a
title played and not WHEN, so a three-month-old check looked identical to
yesterday's. Fourth instance of the same class in two days, alongside `colorMode`
without its saturation (084) and `matchVerified` without its tier (087's
amendment).

**How to apply**: any check against data that can rot needs a timestamp and a TTL
proportional to how visible the claim is — a boolean "checked" is a claim about
the past pretending to be a claim about now. Keep the transient/dead split: a
429 or 5xx must leave the item UNMARKED for retry, never demote it (679 of this
run's failures were transient, and marking them dead would have stripped good
artwork from hundreds of items).

**VERIFIED end to end**: the first run checked 5,820 posters and demoted 137 to
the Archive thumbnail with `hasRealArtwork=False`. Re-probing the same 60-poster
sample after publishing: **0 dead, down from 2**, with the Home-eligible pool
falling 19,058 -> 18,944.

**Consequences**: 727 items now carry `posterDead`, and 472 of them are flagged
`hasRealArtwork=1` again — which is correct, not a contradiction. Those were
re-sourced after demotion: 447 generated frame covers (Decision 023), 17 Commons,
8 TVDb/TMDb. `posterDead` is a durable wants-marker and the re-covering pass
consumed it exactly as intended, so the whole chain — die, demote, mark,
re-source, re-flag — is observably working.

## 089 — A shared index publishes only what it can prove it did not shrink; a missing asset is an emergency, not a first run
*Date: 2026-08-20*

`subtitle.sqlite` is appended to by two workflows — `subtitle-index.yml` (cues)
and `word-index.yml` (word timings) — through one release asset. Both now
snapshot the index's row counts immediately after restoring it
(`tools/sqlite_publish_guard.py snapshot`) and refuse to upload if any table
came out smaller (`check`). Their restore treats only a NON-EXISTENT release as
a first run: a release whose asset has vanished fails the step. And publish is
no longer plain `always()` — it still runs when the COMPUTE step is killed,
which is why `always()` is there, but never when the RESTORE failed.

**Why**: measured in the published artifact — `words=90,084`, `aligned=7`, one
run's output. Two days earlier it held **702,148**. The chain contains its own
control:

    08-18 03:42  subtitle-index uploaded the raw 1.17 GB subtitle.sqlite beside
                 the .zz. `--clobber` DELETES before replacing; the raw upload
                 422'd; BOTH assets were left deleted.
    08-18/19     word-index restore hit "no assets to download" and FAILED,
                 twice, publishing nothing. It has no `|| true`.
    08-19 22:36  subtitle-index hit the IDENTICAL condition, its
                 `|| echo "first run — no existing index"` swallowed it, and it
                 rebuilt 4,000 films from zero and republished over the index.

The workflow without the swallow refused to proceed; the one with it destroyed
the data. Nothing failed — the destroying run is green. This is the same
clobber pattern fixed in `subtitles.yml` on 2026-08-09 and missed here, which
is the argument for a guard rather than a third careful reading: the pattern
has now been found three times by noticing the damage.

**How to apply**: `--clobber` is a DELETE followed by an upload, so any upload
that can fail leaves the asset gone — never pass it a file that might be
rejected (the raw 1.17 GB member is what 422'd), and never let a workflow
publish a rebuilt artifact without comparing it to what it restored. An
`|| true` / `|| echo` on a restore is only ever correct when the *absence
itself* is proven benign; "the asset is missing" is not that, and the way to
tell a genuine first run is that the RELEASE does not exist. The guard passes
on growth, equality, a missing baseline and an empty baseline, and fails naming
the table and both numbers — verified against the real index, including a
faithful replay of the 08-19 rebuild.

**Consequences**: the cue index rebuilt itself, but the `aligned` resume markers
are gone, so ~700k word timings must be re-derived at the 7-9 films/day the
alignment job sustains against archive.org's refusal of ubuntu runners. That
rate — not a budget — is the real constraint on this index, and it is why
losing the history costs months rather than a night. Complements Decision 057
(a budget that PUBLISHES, never a timeout that kills) and 083 (shared state
needs a registered guard, not a careful author).

## 090 — An auditor judges each workflow against its OWN cadence, never a fixed window
*Date: 2026-08-20*

`audit_workflow_health.py` sizes its lookback per workflow from that workflow's
own cron (`cron_period_hours`, ~2.5 periods) instead of a flat
`LOOKBACK_HOURS=36`, and reports **STALE** when a schedule has not produced a
completed run in over two of its own periods. Dispatch-only workflows keep the
fixed window, since they have no cadence to measure against.

**Why**: the daily report said "Nothing needs attention: every recent run
produced something" while **Canonical TV rebuild sat FAILED for four days**.
Nothing was wrong with `judge()` — the run never reached it. The loop skipped
any workflow whose newest completed run started before the cutoff
(`if started < cutoff: continue`), and a weekly job's newest run is ALWAYS
older than 36 hours. Measured across the fleet: 35 scheduled workflows, of
which **7 are weekly or monthly and were therefore structurally unauditable** —
faststart-derivatives (monthly), tvdb-movies, tv-canonical, community-signals,
rebuild-catalog, backfill-language, match-unmatched. The auditor built to catch
BROKEN/KILLED/DROPPED/SILENT could not see the slowest seven, which are exactly
the ones a human is least likely to notice unaided. Re-run after the change, it
named the tv-canonical failure immediately.

**How to apply**: an auditor's window is a property of the SUBJECT, not of the
auditor's own schedule — whenever the things being checked have different
periods, a single window is wrong for all but one of them. Judging an older run
is safe here because `judge()` returns None for a healthy run, so a monthly
workflow that succeeded produces no finding; only real faults are re-reported
each day, which is what an auditor is for. Do NOT respond to a stale finding by
widening the flat lookback — that reintroduces the same class of blindness one
cadence further out. STALE is deliberately distinct from FAILED: a schedule
that stopped firing produces no failing run to notice, so absence has to be its
own verdict.

**Consequences**: the fleet's slowest seven workflows become auditable for the
first time. Related: Decision 088 (a check against data that can rot needs a TTL
proportional to how visible the claim is — the same reasoning applied to
freshness rather than to coverage), and 089 (a green run that did nothing).

## 091 — A time budget measures the whole tool, not the phase that happens to carry it
*Date: 2026-08-20*

`build_canonical_tv.py --max-minutes` is now measured from process start, not
from the start of the rebuild loop, and the tool says so loudly when resolution
alone consumes the whole budget.

**Why**: the weekly TV rebuild died on its 180-minute step timeout on
2026-08-16, and the budget meant to prevent exactly that was real and working.
It was simply counting the wrong interval. Measured on run 32373160578:

    13:15:11  4124 raw targets; resolving + pooling…
    14:09:33  758 unique canonical shows, 2839 unmatched     <- 54m22s, UNBOUNDED
    14:14:52  build complete                                  <- 5m19s, budget honoured exactly

`resolve_and_pool` is network bound (every raw target against TVmaze at a 0.3s
throttle) and runs BEFORE the deadline was computed, so the production default
gave 54m + 150m = **204 minutes against a 180-minute timeout**. The arithmetic
was the whole bug.

**How to apply**: when a tool has two expensive phases, a deadline computed
between them bounds only the second — start the clock at process start. Do NOT
"fix" this by bounding `resolve_and_pool` naively: it returns `(shows,
unmatched)`, and `unmatched` feeds reconcile, which RECLASSIFIES those items OUT
of tv-series. A deadline there must distinguish "tried and did not match" from
"never tried", or it strips TV classification from shows it never looked at.
Deferring shows is safe and needs no such care — verified on the same run:
757 shows deferred, series files 485 -> 485, reconcile deleted 0 superseded and
0 orphan files.

**Consequences**: a run whose resolution outlasts the budget now rebuilds
nothing and says so, instead of timing out and losing the step. That is the
right trade — Decision 057's rule that a budget must PUBLISH rather than be
killed, applied one level up. The per-episode half of this (the deadline
reaching inside `rebuild_show`, degrading to --no-repick rather than dropping
episodes) is proven in the same run: "budget reached mid-show: 218 episode(s)
kept their existing video URL".
