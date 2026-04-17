# Dual App Template — Web + iOS with Claude Code

A project template for building web and iOS apps in parallel with full
feature parity. Designed for use with Claude Code, GitHub Pages, and Xcode
Cloud.

## What's in the Template

```
/
├── CLAUDE.md              Project identity + standing instructions for Claude
├── SCRATCHPAD.md          Session state, milestones, feature parity table
├── DECISIONS.md           Append-only architecture decision record
├── .claude/               Claude Code hooks and slash commands
├── index.html             Web app entry point
├── css/styles.css         Mobile-first CSS with custom properties
├── js/app.js              Web app logic (view system scaffold)
├── js/api.js              API abstraction layer
├── manifest.json          PWA manifest
├── assets/                Static assets (icons, images)
├── ios/                   iOS Swift source files (starter kit)
│   ├── App/               Entry point
│   ├── ContentView.swift  Root view + sidebar
│   ├── Models/            Data models
│   ├── Views/             Feature views
│   ├── Components/        Reusable UI components
│   ├── Networking/        API client
│   ├── Store/             @Observable global state
│   └── Assets.xcassets/   App icon + colors
├── AppVersion.xcconfig    Shared version numbers
├── ci_scripts/            Xcode Cloud build scripts
└── .gitignore             Ignores build artifacts, Xcode user data
```

## Setup — 7 Steps

1. **Use this template** on GitHub (or clone and re-init git)
2. **Fill in CLAUDE.md** — project name, description, tech stack, design tokens
3. **Fill in SCRATCHPAD.md** — milestones M1, M2, M3
4. **Create the Xcode project**:
   - Xcode → File → New → Project → iOS → App
   - Product Name: `AppName` (NO SPACES — critical for Xcode Cloud)
   - Save to the **repository root** (not a subdirectory)
   - Move the Swift source files from `ios/` into the Xcode-created
     `AppName/` group, then delete the `ios/` directory
   - Add `AppVersion.xcconfig` to both Debug and Release configurations
5. **Push to GitHub** and enable GitHub Pages (Settings → Pages → main branch)
6. **Xcode Cloud** (optional): Create a workflow in App Store Connect.
   The `.xcodeproj` at root means Xcode Cloud finds it automatically
7. **Start coding** — Claude Code loads context automatically via the
   session-start hook

## How Sessions Work

1. Session-start hook injects CLAUDE.md + current state from SCRATCHPAD.md
2. Claude follows standing instructions silently
3. At session end, update SCRATCHPAD.md current state and append session log
4. Slash commands: `/status`, `/milestone`, `/decision`

## Xcode Cloud Compatibility

This template solves the "Project does not exist at the root of the
repository" error by keeping `.xcodeproj` at the repo root with no spaces
in the project name. The `ci_scripts/ci_post_clone.sh` script runs after
Xcode Cloud clones the repo — use it for any pre-build setup.

## Key Conventions Baked In

**From building Bsky Dreams (production web + iOS app):**

- Web: vanilla HTML/CSS/JS, single-page view system, API abstraction layer
- iOS: SwiftUI + @Observable + SwiftData, no third-party packages
- Shared: feature parity tracking, design token alignment, dual-platform
  decision records
- Version management via xcconfig (not Xcode UI)
- In-memory caches for SwiftData queries to prevent cascade re-renders
- NSFW/content label filtering pattern for feed views
- Hybrid feed merging (multiple API sources in parallel, dedup, trending sort)
- VideoPlayer crash prevention (`.transaction { $0.animation = nil }`)
- Image resize as a shared static method (not duplicated per-view)
- Share sheet via UIKit (not SwiftUI ShareLink) for full action support

## Claude Skills Available

This template is designed to work with Claude Code skills that were used
in building Bsky Dreams. See the full reference in CLAUDE.md. Highlights:

**UI/UX Design (Killer UI)**: `KUI:system`, `KUI:brand`, `KUI:screen`,
`KUI:review`, `KUI:code`, `KUI:a11y`, `KUI:darkmode`, `KUI:trends`,
`KUI:figma` — design system creation, accessibility audits, dark mode,
design-to-code conversion.

**App Store**: `app-store-screenshots` — generate screenshot pages and
promotional assets for App Store listings.

**iOS Development**: 40+ `all-ios-skills:*` skills covering SwiftUI,
SwiftData, networking, security, concurrency, testing, performance,
App Store review prep, and more.

**Code Quality**: `simplify` for code review, `claude-api` for building
with the Claude/Anthropic SDK.

To use a skill, ask Claude directly: "Use KUI:system to create a design
system" or "Run all-ios-skills:app-store-review to check for rejection
risks."

## Learning Orientation

Every feature is evaluated against six criteria before implementation:

1. Does it deepen understanding?
2. Does it invite participation?
3. Does it support human agency?
4. Clarity over cleverness
5. Accessible by default (WCAG AA)
6. Responsive from the start (mobile-first)
