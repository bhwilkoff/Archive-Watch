# Archive Watch — Claude Code Project Context

## Why we build

Every feature in this app is built in service of human learning and
growth — not to replace thinking, but to deepen it. At each decision
point, ask: does this design invite the user to engage more fully,
think more critically, or connect more meaningfully? If a feature
makes a person more passive, reconsider it. If it opens a door to
curiosity or collaboration, prioritize it. The goal is never a slick
product — it is a tool that makes someone more human.

**Before implementing any feature**, invoke the
`learning-orientation-design` skill — the four-question test that
operationalizes this paragraph.

---

## How we build

This project follows a methodology that lives in **global skills**
(`~/.claude/skills/`). Don't re-derive these patterns; invoke the
skill when its trigger matches.

| When | Skill |
|---|---|
| Starting any feature change | `feature-shipping-discipline` |
| Proposing UI / IA work | `binding-design-doc-discipline` |
| Designing any view (tvOS or web) | `mobile-first-density-design` + `native-platform-first` |
| Adding a list / grid / sheet / shelf | `universal-feature-states` |
| Logging an architecture decision | `architectural-decision-log` |
| Any tvOS UI / focus / animation work | consult `docs/tvos-playbook.md` first; then invoke the relevant `all-ios-skills:*` |
| User pushback after 3+ iterations of "still broken" | `3d-feature-debug-loop` |

iOS framework depth lives under `all-ios-skills:<name>` — most still
apply to tvOS (`swiftui-patterns`, `swiftui-navigation`, `swiftdata`,
`ios-networking`, `swiftui-liquid-glass`, `app-intents`,
`app-store-review`, `codable-patterns`, etc.). Design skills live
under `KUI:<name>`. The global skills list is the source of truth —
don't enumerate skills in this file beyond the triggers above.

### Archive Watch-specific guardrails (tvOS)

These came from real iteration on this project and are not in any
global skill. The fuller catalog of tvOS patterns is in
`docs/tvos-playbook.md` — read it before iterating on focus,
sidebar, navigation, or animation bugs.

- **Never `buttonStyle(.plain)` on tvOS** — destroys focusability.
  Use `.borderless` or a custom `ButtonStyle`.
- **SourceKit phantom errors are stale index, not real.** Cross-file
  "Cannot find … in scope" warnings on tvOS often disappear after a
  clean build. Trust `xcodebuild`, not the editor squiggles.
- **`@Query` macro can cascade unrelated "Cannot find X in scope"
  errors** across views in the same file. If you see a cascade of
  resolution errors after touching a view that uses `@Query`, the
  macro is the cause — move data fetching out of that view (see
  commit `e62601c`).
- **Reset a tab's `NavigationPath` when the user leaves it via the
  sidebar** — otherwise tab state pollutes the next visit (commit
  `a8188fe`).
- **Initial-focus views (`HeroCarousel`, first-tab landings) must
  imperatively claim focus on appear** — relying on default focus
  alone is unreliable on tvOS (commit `1f789b1`).
- **Consolidate Home-only components inside `HomeView.swift`**
  when SourceKit cannot resolve them cleanly across split files
  (commit `f7fe380`).

---

## Debugging philosophy

**Do not iterate blindly on behavior you cannot observe.** When a
feature does not work correctly and the root cause is not immediately
clear from reading the code, the first move is diagnostics — not
another implementation attempt.

1. Add observability before trying another implementation
2. Design diagnostics to answer a specific question — write down what
   you expect to see vs. what would indicate the bug
3. Isolate layers — verify each independently before changing any
4. For tvOS interaction bugs (focus, animation, video) the user
   cannot easily share a console for, add a temporary on-screen
   debug overlay
5. Remove diagnostics before declaring a fix complete

If user pushback returns after 3+ iterations of "still broken,"
that's the signal to invoke `3d-feature-debug-loop` and reset to
research-agent + observable-evidence discipline.

---

## What this app does

**Archive Watch** is a tvOS (Apple TV) app that turns the Internet
Archive's vast public-domain moving-image collection — feature films,
classic TV, newsreels, silent cinema, animation, ephemeral industrial
films — into a cinematheque-style browsing and viewing experience.
Titles are enriched with posters, cast, synopses, and genres sourced
from TMDb (with Wikidata, Wikimedia Commons, and the Library of
Congress as fallbacks), so archival content is presented with the
same care and visual dignity as a modern streaming service. The
audience is curious viewers who would rather wander a well-stocked
repertory cinema than doomscroll a recommendation feed.

**Primary platform: tvOS 17+ (currently building against tvOS 26 /
Liquid Glass).** The Apple TV app is the product.

The `index.html` / `css/` / `js/` web scaffold in this repo is
retained as a **companion editorial dashboard** — a small static
page served via GitHub Pages where the curator maintains
`featured.json` and runs `build-catalog.html` to generate the
`catalog.json` seed the tvOS app consumes. It is not a
consumer-facing viewer, and the template's Dual-Platform Feature
Parity Model does **not** apply here.

---

## Web app (editorial dashboard only)

**Stack**: Vanilla HTML/JS — no framework, no build step. Custom
CSS, mobile-first. GitHub Pages static hosting, branch `main`,
root `/`.

**Key directories**:
- `/` — root: `index.html`, `whats-new.html`, `build-catalog.html`,
  `featured.json`, `catalog.json`, working docs
- `/css/styles.css` — single main stylesheet
- `/js/api.js`, `/js/app.js`, `/js/build-catalog.js`,
  `/js/whats-new.js` — API abstraction + view system per tool
- `/assets/` — static assets (icon master, previews)

**Run locally**: `python3 -m http.server 8080` → visit
http://localhost:8080. Deploy: push to `main`; GitHub Pages serves
automatically.

**Conventions** (the load-bearing ones — see skills for the rest):
- All Archive.org / TMDb calls through `js/api.js` — never `fetch`
  directly elsewhere
- CSS custom properties in `:root` in `styles.css`
- Mobile-first; all media queries use `min-width`
- No inline styles
- Error states must be user-visible (not just console logs)
- IntersectionObservers created per-view are disconnected on view
  switch
- Use `showView(name)` to switch views; each view is a `<section>`
  with `hidden` toggled

**Safari layout pitfall** (cross-project):
`body { height: 100dvh; display: flex; flex-direction: column;
overflow: hidden; }` with `main { flex: 1; overflow-y: auto;
min-height: 0; }`. NO `viewport-fit=cover`. NO `position: fixed`
overlays — they break Safari's compositor at the Dynamic Island.

---

## tvOS app

**Stack**: Swift 6, SwiftUI (`@Observable`, tvOS 17+, currently
running on tvOS 26 with Liquid Glass), SwiftData for local
persistence, URLSession direct to Archive / TMDb / Wikidata
(no third-party packages).

**Project structure** — Xcode Cloud compatible:

```
/                              ← repo root
├── ArchiveWatch.xcodeproj/    ← at root (Xcode Cloud requirement)
├── ArchiveWatch/
│   ├── App/                   ← entry point
│   ├── Models/                ← ContentItem, Taxonomy, CollectionRegistry
│   ├── Views/                 ← SwiftUI views (one folder per feature)
│   ├── Components/            ← HeroCarousel, ShelfRow, DecadeTilesRow, …
│   ├── Networking/            ← ArchiveClient, TMDbClient, WikidataClient
│   ├── Services/              ← EnrichmentService, SeedCatalog
│   └── Resources/
├── AppVersion.xcconfig        ← shared version numbers
├── Secrets.xcconfig           ← gitignored; TMDB_BEARER_TOKEN
├── ci_scripts/                ← Xcode Cloud build scripts
├── docs/                      ← research + tvOS playbook
├── index.html                 ← editorial dashboard
├── catalog.json               ← bundled seed catalog
├── featured.json              ← curator picks + dynamic shelves
└── tools/                     ← validation + enrichment scripts
```

**Critical conventions**:

- **All API calls through a shared singleton** — never URLSession
  directly from views
- **Global nav state in `@Observable` store** with `NavigationPath`
  per tab; reset a tab's path when the user leaves it via the sidebar
- **Version numbers via `AppVersion.xcconfig` only** — never edit
  through Xcode identity panel (creates per-target overrides)
- **tvOS 17+ minimum** — currently targeting tvOS 26 / Liquid Glass
- **No third-party Swift packages** — Apple frameworks only
- **`Secrets.xcconfig` is gitignored** — TMDB bearer token lives
  there; never commit secrets

For SwiftUI patterns, navigation, animation, performance — invoke
`all-ios-skills:<name>`. For Liquid Glass (tvOS 26+) see
`all-ios-skills:swiftui-liquid-glass`. For tvOS-specific patterns
not in any global skill — focus management, sidebar behavior, hero
carousels, the `@Query` cascade gotcha — consult
`docs/tvos-playbook.md`.

---

## Shared design system

**Brand chrome** (used in both dashboard + tvOS):

```css
:root {
  --color-primary:    #FF5C35;  /* marquee orange (Feature Film + CTA) */
  --color-accent:     #0047FF;  /* links, interactive */
  --color-bg:         #FFFFFF;
  --color-text:       #0A0A0A;
  --color-border:     #E0E0E0;
}
```

**Per-category semantic accents** (content meaning only, see
DECISIONS 013): Feature Film `#FF5C35`, Classic TV `#2D5BFF`,
Silent Era `#C9A66B`, Animation `#FF4D8D`, Newsreel `#8A8F98`,
Documentary `#3FA796`, Ephemeral `#7C5BBA`, Short Film `#E8A317`.

The split is binding — never use a brand color for content meaning,
never use a semantic color for chrome.

**Typography hierarchy**: three weights × two sizes = six levels.
Refuse a seventh; refactor instead. See `mobile-first-density-design`
for the discipline.

**Density rule**: density comes from removing chrome, not adding
decoration. On tvOS the analogue is *focus does the work* — the
focused card is the chrome; surrounding cards should be quiet.

---

## When to create a binding design doc

This project has grown past ~5 views (Home, Browse, Detail, Player,
Settings, Search, TV series shelf, …). A `tvOS-DESIGN.md` binding
design doc would be earning its keep — quote the rule before
proposing any new view / sheet / overlay / shelf type. Invoke
`binding-design-doc-discipline` when adding it.

Until that doc exists, `docs/tvos-playbook.md` is the closest thing
this project has to a binding spec — consult it first for any tvOS
UI change.

---

## Standing instructions

- **Read the relevant skill before re-deriving a pattern.** The
  global skills exist because the patterns came from real iteration.
- **Commit messages quote the user's request verbatim** when
  applicable. See `feature-shipping-discipline`.
- **DECISIONS.md leads with WHY, not WHAT** for entries 016+;
  entries 001–015 use the older Decision / Rationale / Alternatives /
  Trade-offs format and remain as-is — append-only is the rule.
- **Don't add features beyond what's requested.** Fix only the bug.
- **Don't refactor surrounding code.** Scoped diffs.
- **Default to writing no comments.** Only add one when the WHY is
  non-obvious — a hidden constraint, a subtle invariant, a workaround
  for a specific bug.
- **No emojis in code or commits** unless explicitly requested.

---

## Current state

See @SCRATCHPAD.md for active milestone + tvOS feature status.
See @DECISIONS.md for architecture decisions.
See `docs/tvos-playbook.md` for tvOS-specific patterns learned the
hard way on this project.
