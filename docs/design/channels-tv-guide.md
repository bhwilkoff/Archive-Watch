# Channels → a real TV guide (design + buildout plan)

Status: design doc / research. Drafted 2026-06-05. Implementation is phased
(see Roadmap). This is the binding spec for the Channels rework — quote a rule
here before adding any channel-related view, model, or scheduling behavior
(per `binding-design-doc-discipline`). Companion to `docs/tvos-playbook.md`.

---

## Why

Today's Channels tab is, functionally, a second Surprise page: pick a channel,
get a *shuffled* pool of matching titles, and autoplay through them. There's no
sense of *time*, no schedule, no "what's on now / next," and nothing that looks
like a channel. The product promise — "a repertory cinema you can wander" —
wants the opposite of a shuffle: a **programmed broadcast** you tune into, with
the texture of 1990s television, including the commercials between shows.

Two reference points the owner provided define the target:

1. **Retro (the feel):** the Prevue/TV-Guide channel — a scrolling grid of
   channels down the left, time slots across the top, program titles with year
   and rating filling each slot, a "now" playback pane up top.
2. **Modern (the structure):** a contemporary EPG grid (e.g. the screenshot of
   "All Channels" with `a1…a12` rows, half-hour columns, programs as
   proportional-width blocks that span their runtime, "Extras" filler between).

We want the **modern structure** (a correct, time-accurate EPG) wearing a
**retro-tinged skin**, and — the part that makes it Archive Watch and not just
an EPG — **vintage public-domain commercials between the programs**, the way
television actually felt.

This also earns the commercials we're ingesting (~2,400 PD/CC0 vintage ads,
contentType `commercial`): they are interstitial content by nature and have no
good home as standalone browse items. The channel is their reason to exist.

---

## What exists today (baseline)

- `ChannelsView.swift` — 11 preset `Channel`s (7 genre-based, 4
  contentType-based) + user-created `UserChannel`s (genre × contentType ×
  decade). Selecting one builds a lineup via `CatalogDB.browse(...)` (top ~200
  by popularity), **shuffles**, drops non-playable / no-artwork items, and hands
  the array to `PlayerScreen(lineup:)`.
- `PlayerScreen` plays the array start-to-finish with autoplay
  (`sessionMode = .sameCategory`). That continuous-play engine is the one piece
  we keep and build on.
- **No** time model, schedule, grid, now/next, persistence, or breaks.

## The gap (what a real guide needs)

1. A **deterministic schedule** — given a channel and a wall-clock time, everyone
   tuned to that channel sees the same program at the same moment ("broadcast,"
   not "shuffle"). Tuning in mid-program joins it in progress.
2. An **EPG grid** — channels × time, program blocks sized to runtime, now-line,
   focusable cells that show title/year/rating and tune or preview.
3. **Commercial breaks** — short PD ads inserted between programs, and
   (optionally) at ~15-minute intervals *within* a program, 1990s-style.
4. **Filler** — when a program ends before the next slot boundary, fill with a
   commercial pod or a short, so the grid has no dead air (the modern reference
   calls this "Extras").

---

## Design

### 1. Deterministic scheduling (no backend)

The schedule must be reproducible on-device from a seed — we have no server
(Decision 009/010). Model a channel's program day as a function of
**(channelID, date)**:

```
seed = hash(channelID + yyyy-mm-dd)
pool = CatalogDB.browse(channel filters, sort: popular, limit: ~300)   // candidates
order = deterministicShuffle(pool, seed)                                // same all day
schedule = packTimeline(order, dayStart: local 6:00am, breaks: commercials)
```

`packTimeline` walks the ordered pool, laying each program at the running clock,
inserting a **commercial pod** (1–3 ads) between programs, and looping the pool
when the day is exhausted. Because the seed is date-stamped, the grid is stable
for the day and refreshes tomorrow — and any two Apple TVs compute the same grid
(no sync needed). "What's on now" = the slot whose `[start,end)` contains
`Date()`; tuning in seeks the player to `now - slot.start`.

Key properties:
- **Deterministic:** `SplitMix(seed:)` (already in the codebase, used by the
  Home hero) gives reproducible ordering.
- **Stateless:** the schedule is recomputed, never stored. A `WatchProgress`-style
  per-channel resume is optional polish, not required.
- **Honest runtimes:** programs use `runtimeSeconds`; items missing a runtime get
  a default (e.g. 90 min for features, 25 for shorts) so packing never stalls.

### 2. Commercial breaks (the Archive Watch differentiator)

A **break pod** is `CatalogDB.randomCommercials(limit:)` (already added) seeded by
the slot index so it's deterministic too. Two modes, user-selectable per the
existing autoplay settings:

- **Between programs (default):** after each program, play a 1–3 ad pod
  (~60–120s) before the next program. Clean, low-friction.
- **In-program (retro, opt-in):** insert a pod at ~15-minute marks inside long
  programs — the literal 1990s-broadcast feel the owner described. Implemented as
  scheduled interruptions in the continuous-play engine (pause feature → play pod
  → resume feature at the saved offset, reusing the resume machinery from
  Decision 021's loader).

Commercials are sourced ONLY from contentType `commercial` (kept off every other
surface by `CatalogDB.notCommercial`). Era-matching is a nice-to-have: prefer ads
whose decade is within ±10y of the program (a 1955 feature gets 1950s ads).

### 3. The EPG grid (new view: `ChannelGuideView`)

A horizontally + vertically scrolling grid. **This is a new top-level surface —
the rule it must obey (tvOS playbook §focus): every cell reachable by arrows in
every direction that has content; focus does the chrome.**

```
            8:00      8:30      9:00      9:30     10:00
 ┌──────┬─────────────────────┬───────────────────┬──────
 │ a1   │ Trolls (2016)            │ A Goofy Movie (1995)
 │ Drama│ ◀ Arthur Christmas  │ Shelter (2007)    │ Away We Go
 │ a3   │ Friday Night Lights │ ▶  break  ▶ Archer │ Extras
 └──────┴─────────────────────┴───────────────────┴──────
   ▲ channel rail (icon + name + number)   ▲ program blocks sized to runtime
```

- **Left rail:** channel icon, name, number — `focusSection()`; entering it
  expands to show all channels; selecting tunes.
- **Time axis:** half-hour columns; a subtle **now-line**; the grid auto-scrolls
  so "now" is near the left edge on open.
- **Program blocks:** width ∝ runtime; show title + year + (if known) a rating
  chip — exactly the retro reference. Focus a block to preview (top pane plays
  the live channel) ; select to tune full-screen and join in-progress.
- **Break/filler cells:** rendered as thin "Commercials" / "Extras" blocks so the
  grid reads as continuous, never empty.
- **Density rule (mobile-first-density-design):** the block earns its space with
  title + year + rating and nothing else; no synopsis at 10 ft. Six type levels
  max. Accent = the channel's color (Decision 013).

### 4. Data model (new)

```swift
struct ScheduledProgram {            // computed, never persisted
    let item: Catalog.Item           // a program OR a commercial pod marker
    let start: Date
    let end: Date
    let kind: Kind                    // .program | .breakPod | .filler
}
struct ChannelSchedule {
    let channel: Channel
    let day: Date
    let slots: [ScheduledProgram]
    func nowPlaying(at: Date) -> (ScheduledProgram, offset: TimeInterval)?
}
```

A `ChannelScheduler` (pure, testable) produces `ChannelSchedule` from
`(Channel, Date, CatalogDB)`. No I/O — the diagnostics harness (#P0-F3) can unit
-test packing/determinism directly.

---

## Roadmap (phased — ship value each step)

- **Phase 0 — foundation (DONE this round):** `commercial` contentType ingested
  + kept off Home; `CatalogDB.randomCommercials` + `AppStore.dbRandomCommercials`
  exist; Commercials collection + Random Commercial action live.
- **Phase 1 — breaks in the current player:** keep today's shuffle-lineup
  Channels UX, but interleave commercial pods between programs (between-programs
  mode) using `randomCommercials`. Lowest-risk; immediately makes channels feel
  like TV. (No grid yet.)
- **Phase 2 — deterministic schedule:** add `ChannelScheduler` + `ChannelSchedule`;
  replace the shuffle with a date-seeded packed timeline; "join in progress" on
  tune. Add a simple **Now / Next** strip per channel (reuses #1b "now/next
  guide" groundwork).
- **Phase 3 — the EPG grid (`ChannelGuideView`):** the full channels × time grid
  with now-line, preview pane, retro skin. This is the big UI lift; gate it
  behind a binding-doc review of focus + density.
- **Phase 4 — retro polish:** in-program breaks at 15-min marks (opt-in), era
  -matched ads, rating chips, channel "bumpers," optional per-channel resume.

## Open questions

- **Posters for commercials:** the ~2,400 ads have no real artwork → they render
  the procedural typographic card today. For *breaks* this is irrelevant (they
  play, they aren't browsed). For the Commercials *collection* it's acceptable
  v1. A real cover would come from frame extraction (#86 / `docs/research/
  frame-extraction-plan.md`, macOS+ffmpeg runner) — deferred, not blocking.
- **Rating chips** (the "PG (1995)" in the retro reference): we don't store MPAA
  ratings for most PD titles. Source from OMDb `content_rating` where present;
  omit otherwise (don't fabricate).
- **Channel count / identity:** keep the 11 presets + user channels, or curate a
  fixed dial (e.g. "Channel 3 — Drama", "Channel 7 — Cartoons") for the retro
  feel? Leaning curated dial + user channels above it.
- **Default break mode:** between-programs ON by default; in-program OFF (opt-in)
  — confirm with owner before Phase 4.

## Learning-orientation check (per `learning-orientation-design`)

A programmed guide invites *wandering with intention* (you scan what's on, you
discover a 1953 film noir you'd never have searched for) rather than passive feed
-scrolling — it deepens curiosity and supports agency (you can still tune away,
search, or favorite). The commercials are framed as cultural artifacts of their
era, not ads to act on. This passes the four-question test.
