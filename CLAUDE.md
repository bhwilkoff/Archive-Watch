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
| Any UI change on any platform | its binding design doc FIRST (list under "Binding design docs" below), then the platform skill: `tvos-platform-patterns`, `ios-production-gotchas`, `macos-platform-patterns`, `android-production-gotchas` / `androidtv-compose-focus`, `roku-brightscript-app`, `smarttv-web-app` / `web-platform-patterns` |
| Any tvOS focus / animation bug | `docs/tvos-playbook.md` first; then the relevant `all-ios-skills:*` |
| Shipping any user-facing feature | `cross-platform-parity-discipline` — update `PARITY.md` in the same change set |
| Any macOS app work (shell / player / hero / browse) | consult `docs/macOS-DESIGN.md` (Part B) first; then `macos-native-app-shell` |
| macOS Creation Studio (editor / engine) work | consult `docs/macOS-DESIGN.md` (Part A) first; then `macos-creation-studio-engine` |
| Submitting any Apple App Store build | DEFAULT = the cloud workflow `gh workflow run appstore-build.yml` (the dev Mac's beta OS can't ship locally); see `apple-app-store-cli-submission` + `docs/mac-app-store-submission.md` |
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

**How we engineer** — the ten disciplines, each naming the incident
that produced it: `docs/ENGINEERING-PROCESS.md`. Read it before a
first change to this repo.

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

**Archive Watch** turns the Internet Archive's public-domain moving-image
collection — feature films, classic TV, newsreels, silent cinema,
animation, ephemeral industrial films — into a cinematheque-style
browsing and viewing experience. Titles are enriched with posters, cast,
synopses and genres from TMDb (Wikidata, Wikimedia Commons, OMDb, TVDb,
LoC as fallbacks) so archival content gets the same visual dignity as a
modern streaming service. Free, no ads, no accounts required.

It began tvOS-first (Decision 006) and is now **live on tvOS, iOS/iPadOS,
macOS, Android phone + Google TV, Fire TV, Roku, and the web at
archivewatch.org** (Decisions 028/047), with webOS/Tizen packages built
and unsubmitted. One catalog, one data plane (`docs/CATALOG-CONTRACT.md`),
native UI per platform — feature parity, not design consistency
(`PARITY.md`). Ship state lives in Pulse (`archivewatch.org/pulse/`),
not in any doc.

---

## Repo map

```
ArchiveWatch/ArchiveWatch.xcodeproj   ← ONE universal Apple project (tvOS + iOS + macOS
ArchiveWatch/ArchiveWatch/               targets + Top Shelf + Widgets); Swift 6, SwiftUI,
  App/ Views/ Components/ Models/        SwiftData, AVFoundation, no third-party packages
  Networking/ Services/ Store/ iOS/ macOS/
android/                              ← Kotlin + Compose M3; flavors `google` (Play, Google TV)
                                         and `amazon` (Fire TV, minSdk 23); Media3 player
roku/                                 ← BrightScript / SceneGraph channel 881015
index.html watch.js sw.js tv.js       ← web PWA viewer (site root); TV layer for webOS/Tizen
curate/                               ← the editorial dashboard (featured.json)
pulse/                                ← the analytics console (reads ops/pulse.json)
tools/                                ← ~300 Python/JS pipeline, audit, submission + test scripts
.github/workflows/                    ← ~48 workflows: catalog enrichment crons, publish-db,
                                         deploy-pages, store builds/submits, pulse, social
docs/                                 ← binding design docs, playbooks, decisions archive
AppVersion.xcconfig                   ← the ONE Apple version number (bump both, every commit)
Secrets.xcconfig                      ← gitignored; TMDb + OpenSubtitles keys
```

`catalog.json` / `catalog.sqlite` live on a GitHub Release, never in git
(Decisions 017/018). Test on **real devices only, never emulators**
(`docs/DEVICE-TESTING.md`; `tools/devlease.py` shares them between sessions).

**Critical conventions** (the load-bearing ones — the skills carry the rest):
- All Archive / TMDb / etc. calls go through the shared clients
  (`Networking/` on Apple, `js/api.js` on web) — never `fetch`/`URLSession`
  directly from a view.
- Version numbers via `AppVersion.xcconfig` only — never the Xcode identity
  panel (creates per-target overrides). Android `versionCode` in
  `android/app/build.gradle.kts`, bumped before every Play upload.
- Never commit secrets. Never regenerate the Roku signing key.
- Every catalog writer is additive and merge-guarded (Decision 020); a
  run that produced nothing goes red, a run that reported someone else's
  condition does not (Decisions 093/107).
- Web: vanilla JS, no build step, mobile-first (`min-width` queries only),
  CSS custom properties in `:root`, no inline styles, error states
  user-visible. Safari pitfall: `body { height: 100dvh; display: flex; …
  overflow: hidden }` + `main { flex: 1; overflow-y: auto; min-height: 0 }`;
  no `viewport-fit=cover`, no `position: fixed` overlays.

---

## Binding design docs

Quote the rule before proposing any new view / sheet / overlay / shelf;
if no rule fits, add the rule first (`binding-design-doc-discipline`).

`docs/tvOS-DESIGN.md` · `docs/iOS-DESIGN.md` · `docs/IPAD-DESIGN.md` ·
`docs/macOS-DESIGN.md` (Part A Creation Studio, Part B app shell) ·
`docs/ANDROID-DESIGN.md` · `docs/TV-DESIGN.md` (Android TV + web-TV) ·
`docs/ROKU-DESIGN.md` · `docs/WEB-DESIGN.md` · `docs/PULSE.md` +
`docs/PULSE-ANALYTICS.md` · `docs/CAPTIONS.md` · `docs/SHAREPLAY.md` ·
`docs/PLAYLIST-SHARING.md`. tvOS focus/animation lore that predates the
design doc: `docs/tvos-playbook.md`.

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

See @SCRATCHPAD.md for the current state, open owner items, and the two
most recent session-log entries (older: `docs/SESSION-LOG.md`).
See @DECISIONS.md for the index of every architecture decision plus the
most recent entries in full (older: `docs/decisions/`).
Both are loaded into every session — keep them small; roll history out,
never summarize it in place.
