# Archive Watch — Architecture & Technology Decisions

Entries are ordered by date. This file is **append-only** — never edit or
remove past decisions. Platform noted where specific; unlabeled = both.

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
