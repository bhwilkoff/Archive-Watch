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
