# Design Reference — UHF, Channels, Apple TV

Three touchstone apps, studied for what to borrow, what to adapt, and
what to leave behind. The goal is a tvOS interface that feels native,
respects the Archive's character (public-domain ephemera is not Netflix
content), and uses proven patterns instead of inventing new ones.

---

## 1. Apple TV app (the native benchmark)

**What it is:** Apple's first-party aggregator. The design reference every
tvOS viewer is measured against.

### Patterns to borrow

**Hero carousel at the top.** 16:9 cinematic stills, auto-advancing every
~8s, focus pauses and surfaces context. In tvOS 18.4+ the carousel gained a
large **+** button (Watchlist) and **i** button (info) as permanent
affordances on every featured card. **We adopt this.** Our Archive Watch
equivalents: **+** = "Save for Later" (Favorites), **i** = Detail page.

**Poster-centric shelves.** tvOS 26 moved hard toward "cinematic poster
art" — 2:3 tall posters instead of 16:9 stills. This is the format
audiences read as "a film." **We adopt this for film shelves, keep 16:9
for TV episodes and footage.** No mixing of aspect ratios within a single
row — it looks amateur.

**Up Next is persistent.** A single shelf, always second from top, lives
across sessions. **We adopt this as "Continue Watching"** — SwiftData-backed,
shows playback progress as a thin bar at the bottom of the card.

**Detail page split layout.** Hero still on top (auto-plays silent
preview loop after 2s focus), metadata below in a two-column grid. Cast,
crew, related content live below the fold as horizontal shelves. **We
adopt the split but drop the silent-preview loop** — it requires generating
preview clips we don't have and would be gimmicky for archival content.

**Focus effects.** Parallax on cards, subtle lift + shadow, title
appearing on hover. Standard tvOS. **We use the defaults exactly** —
deviation here feels wrong immediately.

### Patterns to leave behind
- **Channels/Apps surface.** Apple TV app's top-level "Store Channels"
  mental model is specific to their aggregator business. Irrelevant.
- **Paid-tier gating UI.** We have no tiers.
- **Top shelf branded noise.** The Apple TV app's Top Shelf carousel is
  busy. Ours will be restrained: three items max, editorial picks only.

---

## 2. UHF (the modern IPTV player)

**What it is:** A well-crafted IPTV player with a reputation for taste.
635 ratings at 4.3/5, TMDb integration, catch-up support, 4K HDR.

### Patterns to borrow

**EPG rethought for remote navigation.** UHF explicitly states they
"reinvented the EPG experience from the ground up." Their layout prioritizes
the **focused channel expanding inline** rather than dragging users into a
separate detail view. **We adopt this for the Collection Browse screen** —
hovering a collection card expands it inline to show a preview of 6
items, no drill-down required for a quick scan.

**TMDb-sourced hero art and metadata on every title.** UHF's detail pages
show TMDB-sourced backdrops, cast, ratings — exactly the enrichment
pipeline we planned in `metadata-sources.md`. Seeing it in production
validates the architecture. **We match this pattern**: every Archive
item, after enrichment, looks like a "real" streaming title.

**Sidebar primary navigation.** UHF uses a left-rail menu on iPad / Mac
(Live TV / Series / Movies). On tvOS specifically, the primary nav is a
top tab bar — platform convention. **We use top tabs on tvOS, match the
categorical split**: Home / Browse / Search / Favorites.

**Generous free tier / low friction.** No sign-in to browse. **We
match: no account ever.** All user state is local-only SwiftData. This
aligns with the learning-orientation values in CLAUDE.md — no funnel,
no upsell.

### Patterns to leave behind
- **Live TV EPG grid.** We have no live channels. Not applicable.
- **XMLTV / M3U import UI.** We have no user-provided playlists.
- **"Catch-up" replay of live broadcasts.** Not applicable.

---

## 3. Channels (the DVR craftsman's app)

**What it is:** Channels started as an HDHomeRun companion and grew into
a whole-home DVR. Deeply thoughtful about long content libraries.

### Patterns to borrow

**List layouts for expanded content.** Recent Channels updates leaned
into "list layouts when expanding into content" rather than grids-only. A
grid is for scanning; a list is for deciding. **We adopt a toggle on
the Browse screen** — grid-view for visual scanning, list-view (with
longer synopsis, runtime, year visible) for readers. Focus remembers
the choice.

**Personal Sections.** Channels lets users create their own shelves
(custom smart-filters) that persist alongside the app's default shelves.
**We adopt a lightweight version in v2** — let users favorite a
collection and have it appear as a shelf on Home. Keeps the app
personal without adding account machinery.

**Recordings show timecode, not minutes.** Channels DVR displays "0:12:34
/ 1:42:10" rather than "12 min watched / 102 total." This respects the
viewer's position in the work itself. **We adopt this for Continue
Watching** — show actual timecode on the progress tooltip.

**Fix Incorrect Match affordance.** Channels surfaces "this match is
wrong — here are alternatives" directly in the UI. For an archive
where TMDb matching will sometimes fail, **we adopt this** as a
user-facing escape hatch: long-press (or hold Select) on a detail
page → "This isn't right" → fuzzy-search TMDb for alternatives →
re-link. The new link goes to local SwiftData; it doesn't round-trip
to Archive.org.

**Theater Mode / dimming.** Channels has a "Theater Mode" that dims
ambient UI during playback focus. **We adopt a subtle version** — the
shelf background gradient dims 15% when a video card is focused for
> 2s, drawing the eye to the chosen work.

**Video Groups.** Channels groups related recordings. **We adopt for
multi-part films and TV series** — episodes surface as a nested shelf
inside the parent item's detail page.

### Patterns to leave behind
- **PIP.** Not relevant to a tvOS catalog browser.
- **Recording scheduling UI.** We have no broadcast source.
- **Commercial skip.** No commercials in archival content.

---

## Synthesized design language for Archive Watch

### Structural decisions

| Decision | Source | Rationale |
|---|---|---|
| Top-tab primary nav (Home / Browse / Search / Favorites) | Apple TV + tvOS HIG | Platform convention; users know it |
| Hero carousel at top of Home | Apple TV | Featured editorial moment |
| 2:3 posters for films, 16:9 for TV/footage | Apple TV (tvOS 26) | Correct aspect for each medium |
| Continue Watching shelf, second from top | Apple TV | Expected position |
| Inline-expanding collection cards | UHF | Avoids unnecessary drill-downs |
| Grid/list toggle on Browse | Channels | Respects different user modes |
| TMDb-sourced artwork + metadata on every title | UHF + Channels | Production-grade feel |
| Timecode (not percent) in progress indicators | Channels | Respectful of the work |
| "Wrong match? Re-link." escape hatch | Channels | Archive matching will fail sometimes |
| No account, no sign-in | UHF + values | Removes friction, aligns with CLAUDE.md |
| AVPlayerViewController for playback | tvOS default | Native controls, free gains |
| Ambient dim during focus-hold | Channels | Subtle cinematic cue |

### Visual decisions

**Type**
- SF Pro Display for titles (57pt hero, 34pt shelf title)
- New York (serif) for synopsis paragraphs on detail pages —
  archival content earns a serif. Deviation from tvOS default,
  justified.
- SF Pro Text for metadata and body (29pt minimum)

**Color**
- Background: `#0A0A0A` (near-black from CLAUDE.md tokens)
- Accent: `#FF5C35` for Play and active focus rings
- Link blue: `#0047FF` for linkable metadata (cast, subject tags)
- Vignette toward screen edges so focused cards float

**Motion**
- Hero auto-advance: 8s, gated on `Reduce Motion`
- Focus lift: tvOS default (no custom scaling)
- Ambient dim on focus-hold: 15% over 400ms, eased
- Modal transitions: cross-dissolve, 250ms

**Shelf rhythm**
- 4–5 visible cards per shelf, with 2 cards peeking on the right
- 48px gutters between cards
- 96px gutters between shelves
- Generous density — this is an archive, not a warehouse

---

## What each reference app taught us about our own

- **From Apple TV:** The poster is the product. Spend enrichment budget
  on artwork quality before anything else.
- **From UHF:** Reduce the number of screens a viewer passes through.
  Expand in place. Trust the focused element to carry context.
- **From Channels:** Honor long content. Give users tools to correct
  wrong matches. Show real time, not percentages. Personal curation
  matters.

Collectively: a **cinematheque**, not a **catalog**. Measured, serifed,
unhurried — but snappy to operate.

---

## Open design questions

1. **Should the hero carousel play silent muted previews** once a card
   is focused for 2s, the way Apple TV does? We have no preview clips.
   Could we generate 10-second compressed previews server-side via
   GitHub Actions and host on Pages? Decide after M2.
2. **Serif body type on tvOS** — New York ships with the system, but
   is rarely used in tvOS apps. Does it feel distinctive-correct or
   distracting? Prototype and evaluate on a real screen before
   committing.
3. **Per-collection visual identity.** Should the Prelinger shelf feel
   different from the Classic TV shelf? Arguments both ways —
   consistency vs. editorial character. Lean toward subtle differences:
   same layout, different accent color per collection.
4. **"Shuffle this collection"** action as a first-class button next
   to Play? Cinematheque-appropriate, invites serendipity. Probably
   yes, but not in M1.
