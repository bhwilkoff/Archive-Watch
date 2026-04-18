# Archive Watch — Claude Code Project Context

## A Note on Why We Build

Before writing a single line of code, take a moment to understand the
orientation of this work. Every feature in this app is built in service of
human learning and growth — not to replace thinking, but to deepen it. At
each decision point, ask: Does this design invite the user to engage more
fully, think more critically, or connect more meaningfully? If a feature
makes a person more passive, reconsider it. If it opens a door to curiosity
or collaboration, prioritize it. The goal is never a slick product — it is a
tool that makes someone more human.

---

## Debugging and Diagnostic Philosophy

**Do not iterate blindly on behavior you cannot observe.** When a feature
does not work correctly and the root cause is not immediately clear from
reading the code, the first move is always diagnostics — not another
implementation attempt.

### Rule: Instrument before iterating

1. **Add console diagnostics immediately.** One round of real data is worth
   more than ten rounds of guessing.
2. **Design diagnostics to answer a specific question.** Write down what you
   expect to see vs. what would indicate the bug.
3. **Isolate layers.** Verify each layer independently before changing any.
4. **For iOS interaction bugs, add a temporary visual overlay** when the user
   cannot easily share a console.
5. **Remove all diagnostics before considering a fix complete.**

---

## What This App Does

**Archive Watch** is a tvOS (Apple TV) app that turns the Internet Archive's
vast public-domain moving-image collection — feature films, classic TV,
newsreels, silent cinema, animation, ephemeral industrial films — into a
cinematheque-style browsing and viewing experience. Titles are enriched
with posters, cast, synopses, and genres sourced from TMDb (with Wikidata,
Wikimedia Commons, and the Library of Congress as fallbacks), so archival
content is presented with the same care and visual dignity as a modern
streaming service. The audience is curious viewers who would rather
wander a well-stocked repertory cinema than doomscroll a recommendation
feed.

**Primary platform: tvOS 17+.** The Apple TV app is the product.

The `index.html` / `css/` / `js/` web scaffold in this repo is retained
for a future **companion editorial dashboard** — a tiny static page
published via GitHub Pages where curators maintain the "Editor's Picks"
JSON that the tvOS app fetches. It is not a consumer-facing viewer, and
the Dual-Platform Feature Parity Model below does **not** apply in the
usual sense.

---

## Platforms

### Feature Parity Model

Both platforms implement the same core feature set. Platform-specific
implementation choices are acceptable and expected. What should stay in sync:

- Which views/features exist
- Core UX flows
- Design language and color tokens
- API usage patterns

---

## Web App

### Tech Stack

- **Rendering:** Vanilla HTML/JS — no framework, no build step required
- **Styling:** Custom CSS (mobile-first, CSS custom properties for theming)
- **API:** <!-- FILL IN: Your API approach -->
- **Auth:** <!-- FILL IN: Your auth approach -->
- **Deployment:** GitHub Pages static hosting (branch: main, root: /)

### Key Directories

- `/` — Root: index.html, CLAUDE.md, SCRATCHPAD.md, DECISIONS.md
- `/css/` — Stylesheets (styles.css is the single main stylesheet)
- `/js/` — JavaScript modules (app.js, api.js)
- `/assets/` — Static assets (icons, images)

### How to Run Locally

```
open index.html
# or
python3 -m http.server 8080  # then visit http://localhost:8080
```

### How to Deploy

1. Push changes to `main` branch
2. GitHub Pages serves from root of `main` automatically
3. Live URL: <!-- FILL IN -->

### Web Conventions

- All API calls go through `js/api.js` — never call `fetch` directly from other files
- Auth state is managed exclusively in a single module
- CSS custom properties (variables) are defined in `:root` in `styles.css`
- Mobile-first: all media queries use `min-width` breakpoints
- Semantic HTML throughout — use `<article>`, `<section>`, `<nav>`, `<button>`
- No inline styles — all styling via CSS classes
- Error states must be user-visible (not just console logs)
- **Navigation**: All nav items live inside `#channels-sidebar`
- **IntersectionObserver cleanup**: Any `IntersectionObserver` created for a
  view must be disconnected when leaving that view to prevent memory leaks
- **View system**: Use `showView(name)` to switch between views; each view is
  a `<section>` with `hidden` attribute toggled

### Web Constraints

- GitHub Pages static deployment only — no server runtime, no Node.js
- Zero-cost tools only — no paid APIs, no paid hosting
- No build pipeline — everything must work as plain HTML/CSS/JS

### Do Not Touch (Web)

- `.git/` directory
- GitHub Pages deployment settings

---

## iOS App

### Tech Stack

- **Language / UI:** Swift 6, SwiftUI (`@Observable`, iOS 17+)
- **Local persistence:** SwiftData
- **Auth storage:** Keychain via Security framework
- **API:** <!-- FILL IN: Your API approach -->
- **Fonts:** <!-- FILL IN: Custom fonts if any -->
- **Deployment:** Xcode build → App Store Connect → TestFlight / App Store

### Project Structure — Xcode Cloud Compatible

The `.xcodeproj` lives at the **repository root** so Xcode Cloud finds it
automatically. No subdirectory nesting, no spaces in project names.

```
/                              ← repo root
├── AppName.xcodeproj/         ← Xcode project at root (Xcode Cloud requirement)
├── AppName/                   ← iOS source code
│   ├── App/                   ← Entry point, app delegate
│   ├── Models/                ← Data models
│   ├── Views/                 ← SwiftUI views (one subfolder per feature)
│   ├── Components/            ← Reusable UI components
│   ├── Networking/            ← API client
│   ├── Store/                 ← @Observable global state
│   ├── Resources/Fonts/       ← Custom font files
│   ├── Assets.xcassets/       ← App icons, colors, images
│   └── Info.plist
├── AppVersion.xcconfig        ← Shared version numbers (both targets read this)
├── ci_scripts/                ← Xcode Cloud build scripts
│   └── ci_post_clone.sh
├── index.html                 ← Web app (GitHub Pages serves from root)
├── css/                       ← Web stylesheets
├── js/                        ← Web JavaScript
└── assets/                    ← Shared static assets
```

### How to Create the Xcode Project

1. Open Xcode → File → New → Project → iOS → App
2. Product Name: `AppName` (no spaces — critical for Xcode Cloud)
3. **Save location: the repository root** (not a subdirectory)
4. Interface: SwiftUI, Language: Swift
5. In project settings, add `AppVersion.xcconfig` to both Debug and Release
   configurations (Project → Info → Configurations → set config file)
6. Verify: `AppName.xcodeproj` should be directly in the repo root

### iOS Conventions (Learned from Production)

- All API calls go through a shared client singleton — never call `URLSession` directly from views
- Auth state owned exclusively by one manager — views read via `@Environment`
- Global navigation state lives in an `@Observable` store with `NavigationPath`
- All views use `.toolbarBackground(.regularMaterial, for: .navigationBar)` +
  `.toolbarBackground(.visible, for: .navigationBar)` to prevent content
  scrolling behind the nav bar
- **Sidebar header**: use `VStack` with `.background()` modifier — never a
  `ZStack` with a `Color` sibling (layout-greedy, expands to fill height)
- **fullScreenCover with data**: use `fullScreenCover(item:)` with an
  `Identifiable` carrier struct. Never use `fullScreenCover(isPresented:)` +
  separate `@State` arrays (SwiftUI may evaluate content before state applies)
- **Image grid cells**: always constrain both width AND height before
  `.clipped()`. `scaledToFill()` without width constraint overflows columns
- **VideoPlayer animation crash**: wrap `VideoThumbnailView` (or any view
  containing `AVPlayerViewController`) with `.transaction { $0.animation = nil }`
  to block SwiftUI animation propagation into AVKit
- **Video fullscreen**: present `AVPlayerViewController` directly via UIKit
  `present(_:animated:completion:)` — NOT via SwiftUI `fullScreenCover`.
  Create a fresh `AVPlayer` at current seek position to avoid shared-player conflicts
- **Image resize for uploads**: keep a single shared static resize function.
  Never duplicate resize logic across compose and inline-reply paths
- **Share sheet with Safari**: use `UIActivityViewController` presented via
  UIKit with a custom `UIActivity` subclass for "Open in Safari". SwiftUI's
  `ShareLink` and `.sheet`-wrapped `UIActivityViewController` both suppress
  Safari when presented from within a WKWebView context
- **URLCache**: configure at app launch with large capacity (100 MB memory /
  500 MB disk) to persist `AsyncImage` and `URLSession` responses
- **Seen posts**: use in-memory `@State` `Set<String>` cache instead of
  `@Query` to avoid ForEach cascade re-renders on every SwiftData insert
- **NSFW filtering**: add `isAdultContent` computed property on your post
  model checking labels. Apply in all feed merge steps. Keep search
  intentionally unfiltered (user controls via toggle)
- **Hybrid feeds**: when merging multiple API feeds, fetch in parallel with
  `async let`, deduplicate by URI, sort by trending score. Secondary feeds
  use `try?` so failures never break the primary source
- **Version numbers**: use `AppVersion.xcconfig` at repo root with
  `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. Both targets reference
  it. Never edit versions via the Xcode identity panel (creates per-target
  overrides that cause drift)

### iOS Constraints

- iOS 17+ minimum deployment target
- No third-party Swift packages — use only Apple frameworks
- Keychain for all credential storage — never UserDefaults for secrets

---

## Shared Design System

### Design Tokens (both platforms)

<!-- FILL IN: Your color palette -->
```
Accent:          #FF5C35   — buttons, active states
Blue:            #0047FF   — links, interactive elements
Near-black:      #0A0A0A   — borders and shadows
Background:      #FFFFFF
Border:          #E0E0E0
```

<!-- FILL IN: Your design rules -->

---

## Standing Instructions for Claude

### Learning Orientation — Six Criteria

Evaluate before implementing any feature:

1. **Does it deepen understanding?** Active engagement, not passive delivery
2. **Does it invite participation?** Ask something of the user
3. **Does it support human agency?** Make people more capable, not dependent
4. **Clarity over cleverness** — simpler implementation always wins
5. **Accessible by default** — WCAG AA from line one
6. **Responsive from the start** — mobile-first, test at 375px before 1440px

### Autonomous Work Guidelines

- When uncertain between approaches, document in DECISIONS.md and choose simpler
- No feature additions beyond what's requested
- Only fix the bug, don't refactor surrounding code
- If a feature conflicts with learning-orientation values, surface the conflict

---

---

## Claude Skills Reference

The following Claude Code skills were used in Bsky Dreams development and
are available for this project. Invoke them via the Skill tool or by name.

### UI/UX Design — Killer UI (KUI)

These skills live in `.claude/skills/killer-ui/` and `.claude/commands/KUI/`.

| Skill | When to use |
|---|---|
| `KUI:system` | Create a design system (palette, typography, spacing, components) |
| `KUI:brand` | Develop brand identity (strategy, visual language, logo direction) |
| `KUI:screen` | Design screens following platform-native patterns |
| `KUI:review` | Full design critique (heuristic evaluation, visual hierarchy) |
| `KUI:code` | Convert designs into production-ready accessible frontend code |
| `KUI:a11y` | WCAG 2.2 AA accessibility audit with remediation plan |
| `KUI:darkmode` | Audit and fix dark mode issues (contrast, inverted colors) |
| `KUI:trends` | Research current design trends for any industry |
| `KUI:figma` | Generate Figma-ready specs (auto-layout, components, tokens) |

**Used for**: Bsky Dreams' neubrutalist + Memphis design system, dark mode
implementation, accessibility compliance, component patterns.

### App Store Assets

| Skill | When to use |
|---|---|
| `app-store-screenshots` | Generate App Store screenshot pages and promotional assets |

**Used for**: Bsky Dreams App Store listing screenshots and promotional text.

### iOS Development — all-ios-skills

40+ specialized iOS skills available. Most relevant for app development:

| Skill | When to use |
|---|---|
| `all-ios-skills:swiftui-patterns` | MV architecture, state management, environment |
| `all-ios-skills:swiftui-navigation` | NavigationStack, NavigationPath, deep linking |
| `all-ios-skills:swiftui-animation` | Animations, transitions, matched geometry |
| `all-ios-skills:swiftui-gestures` | Gesture handling, custom recognizers |
| `all-ios-skills:swiftui-performance` | Audit and improve runtime performance |
| `all-ios-skills:swiftdata` | Data persistence with SwiftData |
| `all-ios-skills:ios-networking` | URLSession, async/await networking |
| `all-ios-skills:ios-security` | Keychain, CryptoKit, secure storage |
| `all-ios-skills:ios-accessibility` | VoiceOver, Dynamic Type, accessibility |
| `all-ios-skills:storekit` | In-app purchases and subscriptions |
| `all-ios-skills:live-activities` | Live Activities and Dynamic Island |
| `all-ios-skills:widgetkit` | Home screen and Lock Screen widgets |
| `all-ios-skills:app-intents` | Siri, Shortcuts, and App Intents |
| `all-ios-skills:push-notifications` | Push notification implementation |
| `all-ios-skills:photos-camera-media` | Photo picking, camera, media handling |
| `all-ios-skills:swift-concurrency` | Async/await, actors, Swift 6 concurrency |
| `all-ios-skills:swift-testing` | Swift Testing framework, test migration |
| `all-ios-skills:debugging-instruments` | LLDB, Memory Graph, Instruments profiling |
| `all-ios-skills:app-store-review` | App Store review prep, rejection prevention |
| `all-ios-skills:codable-patterns` | JSON encoding/decoding patterns |
| `all-ios-skills:swiftui-liquid-glass` | Liquid Glass effects (iOS 26+) |

**Used for**: Bsky Dreams' SwiftUI architecture, gesture handling
(ConstellationView), SwiftData persistence, Keychain auth, AVKit video
playback, photo picking with resize, App Store submission.

### Web Development

| Skill | When to use |
|---|---|
| `frontend-design` | Production-grade frontend interfaces |
| `ui-ux-pro-max` | UI/UX design with 50 styles, 21 palettes, 50 font pairings |
| `killer-ui` | Comprehensive UI skill set |

### Code Quality

| Skill | When to use |
|---|---|
| `simplify` | Review changed code for reuse, quality, and efficiency |
| `claude-api` | Build apps with Claude API or Anthropic SDK |

### How to Use Skills

Skills are invoked when relevant to your task. You can also request them
directly: "Use the KUI:system skill to create a design system" or "Run
the app-store-review skill to check for rejection risks."

For iOS skills, prefix with `all-ios-skills:` — e.g., "Use
all-ios-skills:swiftui-performance to audit the feed scroll performance."

---

## Current State

See @SCRATCHPAD.md for per-platform feature status and planned work.
See @DECISIONS.md for all architecture decisions (web and iOS).
