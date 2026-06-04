# Archive Watch — tvOS Design (BINDING)

**Binding.** Every new view, tab, shelf, sheet, overlay, mode, filter, or
toolbar item on the Apple TV app must trace to a rule in this document. When
something feels overwhelming or inconsistent, **fix this document first, then
fix the feature.** Proposals (and commits) cite the rule they implement,
e.g. "per tvOS-DESIGN §2.3."

Division of labor with the other docs:
- **This doc** = the *binding contract*: information architecture, surface
  taxonomy, the design system, and the per-feature IA decisions.
- **`docs/tvos-playbook.md`** = the *implementation recipes* (focus APIs, card
  sizes, image pipeline, animation values). Non-binding how-to; cite it for
  mechanics.
- **`DECISIONS.md`** = the *why* behind non-obvious rules. Each binding rule that
  isn't self-evident has a DECISIONS entry.

---

## §1 — Principles (the why)

1.1 **Lean-back, then lean-in.** The default mode is wandering a repertory
cinema at 10 feet. Every surface must work as pure browse, but should offer at
least one door to curiosity (a connection, a "what is this?", a fact). A surface
that only enables passive consumption violates CLAUDE.md "Why we build" — give it
one lean-in affordance. (Applies hardest to the ambient modes, §9.)

1.2 **Focus does the work.** The focused element is the chrome. Surrounding
elements stay quiet. Density comes from removing chrome, not adding decoration.

1.3 **One verb per top-level surface.** Each tab owns a distinct user verb
(browse / tune in / search / save). Two surfaces competing for the same verb is a
structural bug — resolve before shipping (the verb test, §12.2).

1.4 **Depth ≤ 2 from any tab root.** Tab → list/grid → detail. A would-be third
push must instead be a scope, a sheet/overlay, or a different tab (§12.3).

1.5 **Back is sacred.** Never intercept Back outside the player or a modal
(playbook §8.2 — App Store rejection risk). Every full-screen mode (§9) has a
visible exit and honors Back.

1.6 **Highest quality, faithfully presented.** Archival content gets the same
visual dignity as modern streaming. Never degrade source quality for convenience
(Decision 021); never show a placeholder where real art can be earned (§7).

1.7 **No new state without a home.** Any persisted user state (favorites,
playlists, progress, watched, preferences) maps to the data model in §10 and, for
synced state, the account store (Decision 022).

---

## §2 — Information architecture

2.1 **Tab budget = 9, hard ceiling.** The sidebar (`TabView(.sidebarAdaptable)`)
currently holds 8. A new surface earns a tab ONLY if it owns a distinct top-level
verb (§1.3) AND would be buried if nested. Default to nesting. Adding a 10th tab
requires removing or merging one first.

2.2 **The canonical tab set** (v1 target):
Home · Movies · TV Shows · **Channels** · Collections · Search · **Library** ·
Surprise · Settings. Changes from today: **Channels** is added (§9.1 earns a tab
— a distinct verb, "tune in," and the flagship differentiator); **Library**
replaces the standalone Favorites tab and absorbs Favorites + Playlists + Watched
(§10). That is 9 — the ceiling. Anything else nests.

2.3 **What nests, and where** (binding placement for the backlog):
- **People / cast / crew / characters (#4)** → reached from Detail; a
  detail-class destination in the active tab's `NavigationStack`. NOT a tab.
- **Documentary (#7)** → a category: a Movies facet + a Home shelf. NOT a tab.
- **Public Domain Day (#15)** → a Home seasonal section + a "by year" scope
  inside Browse. NOT a permanent tab.
- **Cartoon mode (#2), Party/background play (#3)** → **modes** (§9), launched
  from Home and Settings, NOT tabs.
- **Cover-art screensaver (#14)** → system idle surface (§9.4), not navigable.
- **Sharing (#16)** → an action on Detail/player (§8), not a surface.

2.4 **Home is the front page, not a junk drawer.** Home composes hero + a bounded
set of shelves (curated, dynamic, Continue Watching, category, decade, director,
hidden gems, seasonal). New Home shelves must declare a removal/empty rule
(universal-feature-states) and respect the post-1977 rights gate
(home_filters memory / CatalogDB `homeAnd`).

2.5 **Every list/grid/shelf/sheet declares all states.** loading · loaded ·
empty · error — each user-visible (CLAUDE.md). Empty states must contain a
focusable element or focus traps (playbook §2.5; the Favorites empty-state bug).

---

## §3 — Surface taxonomy (the only allowed shapes)

Every UI maps to exactly one. A new shape needs a new rule here first.

3.1 **Tab** — a top-level verb (§2.1). Sidebar entry + `NavigationStack`.
3.2 **Shelf row** — horizontal, lazy, focus-reveals title (playbook §3.3, §9.3).
3.3 **Grid** — paged/lazy browse with facets (Movies, Collections, search results).
3.4 **Detail** — hero backdrop + metadata + actions + "more like this"; Play
auto-focused (playbook §9.4). People pages are a detail variant.
3.5 **Sheet / overlay** — transient, dismissible, focus-restoring (player info,
settings, share, skip). Never a nav push (§1.4).
3.6 **Mode** — a full-screen lean-back takeover that replaces the shell while
active, with a visible exit + Back (§9). Channels, Cartoon, Party, Screensaver.
3.7 **Player** — `AVPlayerViewController` baseline + the resilient loader
(Decision 021). Custom chrome only as overlays (§8).

---

## §4 — Typography (binding; mechanics in playbook §4)

4.1 **Six levels, period.** Three weights × two sizes, on the tvOS ramp
(76/57/38/29/23). Body floor 29pt; never below 23pt. A seventh level is refused —
refactor (CLAUDE.md density rule). Use the playbook's tokens, never hardcode.

4.2 **No synopsis at 10 ft on transient surfaces** (hero, shelf, channel banner).
Synopsis lives on Detail and the player info overlay only.

---

## §5 — Color & materials (binding)

5.1 **Brand vs semantic split is absolute** (Decision 013). Brand chrome:
marquee orange `#FF5C35` (primary/CTA), accent blue `#0047FF`. Per-category
semantic accents (Feature Film/Classic TV/Silent/Animation/Newsreel/Documentary/
Ephemeral/Short) carry *content meaning only* — never use a brand color for
meaning, never a semantic color for chrome.

5.2 **Dark-first.** Reserve brightness for the focused element. Liquid Glass
(`.glassEffect`, tvOS 26) is the material; no `.ultraThinMaterial` holdouts
(prior native pass). Per swiftui-liquid-glass: glass on key interactive surfaces
only, never decorate everything.

---

## §6 — Focus contract (binding; APIs in playbook §2)

6.1 The five unbreakable rules hold everywhere: dark-first/29pt/90×60 safe area ·
Back sacred · full reachability · **never `.buttonStyle(.plain)`** · preserve
focus by stable id, not index.

6.2 Initial-focus surfaces (hero, first landing, mode entry, player) claim focus
imperatively on appear (playbook §2.4). Every new mode/overlay declares its
default focus and its focus-restoration target on dismiss.

---

## §7 — Artwork (binding)

7.1 **Real art first.** Posters resolve through the enrichment cascade
(Decision 008). Where none exists, generate a cover from frames + faces (#13,
Phase 4) before falling back to the procedural poster. Never ship a modern poster
on a vintage title — image, synopsis, and title must agree (the #20 rule; metadata
quality program).

7.2 Decode to displayed size via the custom `ImageLoader` (playbook §7), never
raw `AsyncImage` in grids.

---

## §8 — Player surfaces (binding; governs #5, #8, #9, #10, #16)

8.1 **The native player owns transport.** We add only overlays/sheets, never a
parallel transport. All remote video flows through `ResilientStreamLoader`
(Decision 021); buffering per `tunePlaybackBuffering`.

8.2 **In-player settings are one sheet (§3.5), not nav.** Subtitles, audio track,
playback speed, and the per-video autoplay override live in a single transport
sheet. Surface a control only when it has ≥2 real options (hide a single audio
track / single quality) — honest affordances (§1.2).

8.3 **Info overlay** shows title/synopsis/cast + next/prev episode; dismissible;
does not pause unless the user does (#9).

8.4 **Skip intro/credits (#8)** is a transient, focusable, auto-appearing/-fading
affordance anchored to per-title timestamps; pairs with autoplay-next (§9.5).

8.5 **Autoplay (#10)** has a global default (Settings) and a per-video override
(8.2 sheet): same show / same category / same year / off. Runs on the §9.5 engine.

8.6 **Sharing (#16)** is an action surfaced on Detail and in the player sheet.
tvOS has no share sheet → hand-off via QR + deep link (`archivewatch://item/{id}`)
and archive.org URL; AirPlay is native.

8.7 Suppress the asset's bogus embedded year and publish Now Playing artwork via
`commonIdentifierArtwork` (prior work, playbook §8.6).

---

## §9 — Modes: lean-back takeovers (binding; governs #1, #2, #3, #14)

9.0 **Definition.** A mode replaces the navigation shell with a full-screen
experience driven by the **continuous-playback engine** (one shared service:
queue → autoplay-next → transition; roadmap F4). Every mode: (a) has a visible
exit + honors Back (§1.5); (b) declares default focus (§6.2); (c) includes one
lean-in affordance (§1.1) — a press reveals "now playing / what is this / more
like this"; (d) never degrades quality (§1.6).

9.1 **Channels (#1)** — a tab (§2.2). A channel = a saved query (era / genre /
collection / user-built from full-DB filters) realized as a continuous now/next
lineup with a guide. The lean-in affordance is the guide + "jump to this title's
detail."

9.2 **Cartoon mode (#2)** — a mode scoping the catalog to animation with a
simplified, large-target, kid-safe shell (adult filter forced on) and autoplay.
Launched from Home/Settings. Lean-in: big "what's this?" reveal.

9.3 **Party / background play (#3)** — a mode: video-only, **muted by default**
with an audio toggle, autoplaying a curated high-contrast / visually-interesting
queue. Lean-in: a press reveals title + "play with sound / open."

9.4 **Cover-art screensaver (#14)** — the system idle surface; an iTunes-style
animated cover wall over catalog art. Adapt BOBA-Playbook's **Showcase**
(`BOBAPlaybook/Views/Collection/CollectionShowcaseView.swift` — an
AlbumArtwork-style tile grid with flip/drop/roll/spin animation variants + a
`ShowcaseSession` orchestrator). Not navigable; any remote press exits to where
the user was.

9.5 **The engine is shared.** Channels, Party, Cartoon autoplay, and in-player
autoplay (#10) all use the F4 engine. Do not write a second queue/transition
system — extend F4 (the "fix the document, then the feature" reflex).

---

## §10 — Personalization & data (binding; governs #11, #12, #17)

10.1 **Library** (tab, §2.2) is the home for all saved state: Favorites,
Playlists/custom collections (#12), and Watched. One tab, sections — not three
tabs (§1.4).

10.2 **Account & sync (#11, Decision 022 pending Phase 3).** Sign in with Apple
(`AuthenticationServices`) for identity + CloudKit private DB for cross-Apple-TV
sync of favorites, progress, and playlists. No external auth. Sign-in is optional
for browsing/playback — it gates only sync (no funnel; §1.1, Decision 009 spirit).

10.3 **Watched state (#17).** Completed titles (`WatchProgress.isComplete`) are
hidden from Home shelves by default (Settings toggle to show), but remain in
Search/Browse and a Library → Watched section. Hiding ≠ deleting.

10.4 Continue Watching uses timecode, not percent (playbook); it is exempt from
the §10.3 hide (it shows in-progress, not completed).

---

## §11 — Anti-patterns (never)

11.1 A new tab to avoid nesting (§2.1). 11.2 A third nav push (§1.4) — make it a
scope/sheet/mode. 11.3 `.buttonStyle(.plain)` (kills focus). 11.4 A parallel
transport or second autoplay/queue engine (§8.1, §9.5). 11.5 A control shown with
only one real option (§8.2). 11.6 A mode/overlay with no exit or no default focus
(§9.0). 11.7 Degrading video quality for convenience (§1.6). 11.8 A modern poster
on a vintage title (§7.1). 11.9 A seventh type level (§4.1). 11.10 An empty state
with no focusable element (§2.5).

---

## §12 — The three tests (run before any surface ships)

12.1 **Competent-designer test** — could a peer rebuild this screen from a
one-paragraph description? If no, you added decoration; strip.
12.2 **Verb test** — what verb does this own? Colliding with a sibling? Structural
bug; resolve first.
12.3 **Depth test** — count pushes from the tab root. >2 → scope/sheet/tab, not
another push.

---

## §13 — Out of scope (intentional gaps for v1)

On-device upscaling (#6 dropped, Decision D-B; Apple TV 4K upscales natively).
Third-party/external auth (Apple-native only, §10.2). Multiple user profiles per
device. A consumer web/iOS client (the web stays the editorial dashboard,
Decision 006). Live/linear broadcast beyond the §9.1 channel simulation.

---

## §14 — Per-feature IA decision table (the backlog, bound)

| # | Feature | Surface (§3) | Placement | Key rule |
|---|---|---|---|---|
| 1 | 24-hr channels | Mode + Tab | Channels tab | §9.1, §2.2 |
| 2 | Cartoon mode | Mode | launched Home/Settings | §9.2 |
| 3 | Party play | Mode | launched Home/Settings | §9.3 |
| 4 | Cast/crew/characters | Detail variant | in-stack from Detail | §2.3 |
| 5 | Subs/audio/quality/speed | Sheet | player transport sheet | §8.2 |
| 7 | Documentary | Grid + Shelf | Movies facet + Home shelf | §2.3 |
| 8 | Skip intro/credits | Overlay | player affordance | §8.4 |
| 9 | Info overlay + ep nav | Overlay | player | §8.3 |
| 10 | Autoplay options | Sheet + Settings | per-video + global | §8.5 |
| 11 | Accounts + sync | (data) | Library + Settings | §10.2 |
| 12 | Playlists | Grid/Detail | Library sections | §10.1 |
| 13 | Cover generation | (pipeline) | build-time → artwork | §7.1 |
| 14 | Screensaver | Mode | system idle | §9.4 |
| 15 | Public Domain Day | Shelf + Grid | Home section + Browse-by-year | §2.3 |
| 16 | Share | Action | Detail + player sheet | §8.6 |
| 17 | Hide watched | (data) | Home filter + Library/Watched | §10.3 |
| 18 | Episode reclassification | (pipeline) | canonical TV | Decision 016 |
| 19 | No-entry play bug | (bug) | player failure state | §2.5, §8.1 |
| 20 | Wrong poster/desc | (pipeline) | metadata matching | §7.1 |
