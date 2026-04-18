# tvOS Home Screen Integration — Research & Plan

> "The Home Screen integration for the now-watching / resume-watching
> feature that the latest version of tvOS supports."

This document inventories the four tvOS surfaces where Archive Watch
can declare its content to the system, decides which to ship in which
milestone, and sketches the implementation approach for each.

---

## TL;DR

There are **two integrations worth shipping**, **one that's free
upside**, and **one that's a partner-only program we should skip for v1.**

| Surface | What it is | Ship in | Effort |
|---|---|---|---|
| **App Top Shelf** (when our icon is focused) | Sectioned shelf of Continue Watching + Editor's Picks + New This Week | M4 | Medium (separate target) |
| **NSUserActivity on Detail screens** | Enables "Hey Siri, add this to my Up Next" → adds to Apple TV app's Up Next queue | M2 | Tiny (one struct + a modifier) |
| **App Intents for "what to play"** | Lets Siri / Shortcuts surface and trigger our random actions ("Surprise me") | M2 | Small |
| **Apple TV app full integration** (Up Next surface, universal search, single-sign-on) | Our content shows up *inside* the Apple TV app alongside Apple TV+ | **Skip v1** | Heavy partner program |

---

## 1. App Top Shelf

### What it is

When the user focuses Archive Watch's icon on the tvOS Home Screen
(without launching it), the system hides everything above and shows
**our** Top Shelf content in that strip. This is where Continue
Watching belongs for our app specifically — Apple TV+, Netflix etc.
each get the same treatment when their icon is focused.

### Architecture

A separate Xcode target — a **TV Top Shelf Extension** — that ships
inside the main app's bundle. The system loads the extension on demand
(when our icon focuses) and renders its content. The extension is
sandboxed; it cannot write to the main app's data, but it can read
from a shared App Group container.

```
ArchiveWatch.app/
  ├── ArchiveWatch (the main tvOS app)
  └── PlugIns/
      └── TopShelf.appex/
          └── TopShelfContentProvider (subclass of TVTopShelfContentProvider)
```

### Four content styles

Apple gives us four templates to choose from:

| Style | When to use |
|---|---|
| `.carouselActions` | Hero auto-advancing carousel with action buttons (Play, More info). Best for promoting one or two featured items. |
| `.detailsCarousel` | Like above but with structured metadata (description, genre, runtime). Good for editorial promotion. |
| `.sectioned` | Multiple horizontal rows, each labeled. **The right answer for us** — Continue Watching, Editor's Picks, New This Week as three rows. |
| `.inset` | Single full-width branded image. Pure marketing; no actions. Reject — wastes the surface. |

We use **`.sectioned`** with three sections:

1. **Continue Watching** (read from shared App Group container; sourced from SwiftData where the main app writes playback positions)
2. **Editor's Picks** (read from a cached `featured.json` snapshot in the App Group)
3. **What's New** (the same recent-uploads feed the dashboard's ticker page surfaces; cached in the App Group)

If Continue Watching is empty (first run), we degrade to two sections.

### Data sharing — App Group

```
group.com.bhwilkoff.archivewatch
  ├── continueWatching.json      ← written by main app when user pauses/exits playback
  ├── featuredCache.json         ← written by main app on first launch + refresh
  └── whatsNewCache.json         ← written by main app's background refresh task
```

Top Shelf extension reads, never writes. Image URLs in the cached JSON
point to TMDb's CDN; the system handles fetching + caching.

### Item structure

```swift
TVTopShelfSectionedItem(identifier: contentItem.archiveID)
  .title = contentItem.title
  .imageShape = .poster                  // 2:3 for films, .hdtv for TV
  .setImageURL(contentItem.posterURL, for: .screenScale1x)
  .setImageURL(contentItem.posterURLDouble, for: .screenScale2x)
  .displayAction = TVTopShelfAction(url: deepLinkToDetail)
  .playAction = TVTopShelfAction(url: deepLinkToPlayback)
```

The `displayAction` URL opens our app at the Detail screen via deep
link (`archivewatch://item/{id}`). The `playAction` skips Detail and
goes straight to the player. **Both must be supported for the system
to offer the right affordances.**

### Refresh cadence

The system polls the extension on its own schedule (~ every 10 minutes
when the device is awake). We do **not** call APIs from inside the
extension itself — that's a quick way to get a slow, broken Top Shelf.
Instead the main app writes the JSON snapshots to the App Group, and
the extension reads them.

Background refresh in the main app uses `BGAppRefreshTask` to update
`whatsNewCache.json` every few hours.

### Milestone

**M4 (App Store polish)** — adds the Top Shelf extension target,
wires the App Group, ships the Continue Watching + Editor's Picks +
What's New surface. Not a launch blocker; reasonable to add before
TestFlight.

---

## 2. NSUserActivity — "Hey Siri, add this to my Up Next"

### What it is

When the user is on a Detail screen, we declare what they're looking
at via an `NSUserActivity`. The system picks this up and lets the user
say *"Hey Siri, add this to my Up Next"* — which adds the item to the
**Apple TV app's** Up Next queue (the system-wide watchlist surface
shared across Apple's first-party app and partner apps).

> Note: Handoff is **not** supported on tvOS. `NSUserActivity` exists
> only for the Siri integration; cross-device continuity in the
> traditional iOS sense is not available.

### Implementation (sketch)

```swift
struct DetailView: View {
    let item: ContentItem

    var body: some View {
        // … detail UI …
            .userActivity("com.bhwilkoff.archivewatch.viewing-item",
                          isActive: true) { activity in
                activity.title = item.title
                activity.userInfo = ["archiveID": item.archiveID]
                activity.isEligibleForSearch = true
                activity.contentAttributeSet = makeSearchableAttributes(for: item)
            }
    }
}
```

The `contentAttributeSet` (CSSearchableItemAttributeSet) is what Siri
inspects to learn the title, the year, the genre — letting it present
the Up Next item with proper metadata.

### What "Up Next" actually means here

Two distinct things share the name "Up Next" on tvOS:

1. **Our internal Continue Watching shelf** — purely SwiftData-backed,
   shown inside Archive Watch on Home. Already specified for M2.
2. **The Apple TV app's system-wide Up Next queue** — Apple's
   first-party watchlist. NSUserActivity is what gets us in there
   *via Siri voice command only* (no programmatic write API exists
   for non-partner apps; see Section 4).

So shipping NSUserActivity gives users the convenient "Siri, save
this for later" affordance without joining the partner program. It's a
small, free win.

### Milestone

**M2** — alongside Favorites and Search.

---

## 3. App Intents — Siri & Shortcuts

### What it is

`AppIntents` (the modern replacement for SiriKit shortcuts) lets users
trigger our random actions by voice or via the Shortcuts app:

- *"Hey Siri, surprise me on Archive Watch"* → Random Movie
- *"Hey Siri, random Archive Watch collection"* → Random Collection
- A Shortcut that runs Random Movie every Saturday morning at 8am

### Implementation (sketch)

```swift
struct SurpriseMeIntent: AppIntent {
    static let title: LocalizedStringResource = "Surprise Me"
    static let description = IntentDescription("Open a random film from Archive Watch.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        let item = try await EnrichmentService.shared.randomMovie()
        await Navigator.shared.openPlayback(for: item)
        return .result()
    }
}

struct ArchiveWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SurpriseMeIntent(),
                    phrases: ["Surprise me on \(.applicationName)",
                              "Random film on \(.applicationName)"])
    }
}
```

Three intents to ship in M2:
- `SurpriseMeIntent` — random movie, opens player directly
- `RandomCategoryIntent` — random category browse
- `RandomCollectionIntent` — random collection browse

### Milestone

**M2** — these dovetail with the random actions in Decision 014.

---

## 4. Apple TV App full integration (the partner program)

### What it is

The big one — your content shows up *inside Apple's TV app* alongside
Apple TV+, Netflix, etc.:
- **Up Next** surface (system-wide watchlist with deep links into your app)
- **Universal Search** (Siri "show me Buster Keaton films" returns our
  results with our app icon attribution)
- **Single Sign-On** (we don't need it; we have no auth)
- **Subscription Registration** (we don't need it; we're free)

### Why we skip v1

Apple's partner program requires:
1. A formal application via [tvpartners.apple.com](https://tvpartners.apple.com)
2. Apple-side review of brand, business model, content rights
3. Sustained engineering investment to maintain the integration spec
4. Content metadata feeds in Apple's prescribed format (separate from
   our existing pipeline)

For a free, labor-of-love public-domain catalog with no subscription
revenue, the cost/benefit is wrong. The program is fundamentally
designed for premium streaming partners.

**However** — once Archive Watch has real users (say, > 5,000 active
installs), we could revisit. The Up Next surface is a powerful
discovery channel and Apple has shown willingness to onboard
non-commercial apps with strong taste. v2 conversation, not v1.

### What we get without it

NSUserActivity (Section 2) is the consolation prize, and it's a real
one. Users can still say *"Hey Siri, add this to my Up Next"* on our
Detail screens; it just won't have a clickable thumbnail in the Apple
TV app linking back into Archive Watch — only a text entry.

---

## Deep linking (prerequisite for #1 + #2)

Both the Top Shelf extension and `NSUserActivity` rely on the main app
being able to handle deep link URLs. Two schemes:

```
archivewatch://item/{archiveID}            → Detail screen
archivewatch://play/{archiveID}            → Playback screen (skip Detail)
archivewatch://random/{movie|category|collection}  → Random action
```

Wired via SwiftUI's `.onOpenURL { url in … }` modifier in the root
`ArchiveWatchApp`. Routes feed into the existing `@Observable`
`AppStore.navigationPath`.

Universal Links (https://archive-watch.app/...) would be nicer but
require a domain we control + apple-app-site-association file. Defer
to v2.

### Milestone

**M2** — we need deep linking before the random actions are useful via
App Intents anyway.

---

## Updated milestone landing

The original SCRATCHPAD has these as M1–M4. With the integration plan,
they line up cleanly:

| Milestone | New additions |
|---|---|
| M1 | (no change) |
| M2 | + Deep linking (`.onOpenURL`)<br>+ NSUserActivity on Detail screens<br>+ Three App Intents (Surprise Me / Random Category / Random Collection) |
| M3 | (no change) |
| M4 | + Top Shelf extension target with `.sectioned` style<br>+ App Group container + JSON snapshot writers in main app<br>+ Background refresh of whatsNewCache.json |

No changes to M0 or M1.

---

## Implementation gotchas

1. **Extension memory limits.** Top Shelf extensions get ~30 MB of
   memory and ~5 seconds to render. Cache JSON locally; don't fetch
   from network inside the extension.
2. **Image sizes.** Apple expects 1x and 2x; passing only 2x results
   in fuzzy thumbnails on older Apple TVs.
3. **Deep link handler must be defensive.** Users may have stale Top
   Shelf data; an Archive ID that no longer exists must degrade to
   the Detail screen with a friendly "this item is no longer
   available" — not crash.
4. **App Group entitlement** must be added to **both** the main app
   target and the Top Shelf extension target. Easy to forget on the
   second target and end up with a silently-empty Top Shelf.
5. **NSUserActivity activity types** must be declared in the main
   app's `Info.plist` under `NSUserActivityTypes`. Without this, the
   activity type is ignored by the system.
6. **Privacy.** App Intents that surface user-specific content
   (Continue Watching) will sync to other devices via iCloud
   (`isEligibleForHandoff` semantics). Since we have no accounts,
   this isn't a concern, but if we ever add cloud sync we'd revisit.

---

## Open questions

- Should Top Shelf "What's New" reflect *Archive uploads* or *editorial
  picks*? Probably editorial picks for the polished surface; the
  recent-uploads feed is a curator-only tool exposed in the dashboard.
- Should App Intents return a result that AppleTV's Shortcuts UI can
  display (e.g., "Surprise Me ran and chose *Charade*")? Worth a brief
  prototype in M2.
