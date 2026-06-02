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
