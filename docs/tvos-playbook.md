# tvOS Playbook — Archive Watch

A durable reference for building a world-class tvOS 17+ experience. Synthesized from the tvOS HIG, WWDC sessions (2020–2025), Apple developer docs, shipping app analysis (Apple TV app, Channels, UHF, Plex, Infuse), and hard-earned production patterns. Every concrete rule in this playbook is citable — sources are listed per section so future decisions stay traceable.

When designing or coding any screen of this app, open the relevant section first. When in doubt, the footer "Five unbreakable rules" at the bottom are the backstops.

---

## 1. Core principles

Apple's HIG frames tvOS around five principles. Internalize them before writing any view.

1. **Connected.** Every interactive element should feel tactile to the Siri Remote's touch surface — subtle motion, parallax, lift on focus.
2. **Clear.** Ruthless hierarchy, generous margins, never clutter. Users must instinctively know where they are.
3. **Immersive.** Edge-to-edge artwork, cinematic framing, no heavy chrome around media.
4. **Shared / living-room.** Multiple people may be watching. Defaults must be safe (hence Decision 012's adult filter).
5. **Ten-foot UI.** Typical viewing distance is 8–12 ft. Touch-target thinking is replaced by focus-reach thinking. 29 pt is the body text floor.

Implicit sixth principle, cited across every WWDC focus talk: **focus is the primary interaction model.** Subtract focusable elements before you add them. If a layout has trap focus, it is broken.

Sources: Apple HIG — Designing for tvOS; WWDC20 #10049 "Create great designs for tvOS"; BPXL Craft HIG primer.

---

## 2. Focus engine — the API surface and decision tree

The single most-mis-used part of the platform. Every tvOS app lives or dies on its focus engine work.

### 2.1 Every focus API and when to reach for it

| API | Role | When to use |
|---|---|---|
| `@FocusState` (Bool) | Single focusable's focus state | Only one item being programmatically focused |
| `@FocusState` (enum) | Multi-target in one scope | Any time you have 2+ possible focus targets |
| `.focused($state)` / `.focused($state, equals: .x)` | Bind a view to FocusState | Read current focus + drive it programmatically |
| `.focusable()` | Make a non-interactive view participate | Custom views that need to receive focus (not `Button`s — those are focusable for free) |
| `.focusable(_: interactions:)` | Specify focus-activation semantics | Custom views needing `.activate`, `.edit`, or `[.activate, .edit]` |
| `.focusEffect()` / `.focusEffectDisabled()` | Custom focus treatment / suppress system halo | When rendering focus state yourself via `@Environment(\.isFocused)` |
| `.focusSection()` | Mark a container as a traversal unit | Sidebar, content pane, each shelf — use for irregular layouts |
| `.focusScope()` + `@Namespace` | Reset-able focus boundary | Modal roots where `defaultFocus` should retarget on re-entry |
| `.defaultFocus($state, .value)` | Declarative initial focus | **Preferred** over imperative `onAppear` assignment (avoids race) |
| `.prefersDefaultFocus(_:in:)` | Specific view prefers default within scope | Older API; `defaultFocus` is cleaner |
| `.onMoveCommand(_:)` | Intercept directional presses | Only when focus engine wouldn't consume them |
| `.onExitCommand(_:)` | Intercept Back button | **Sparingly** — only for custom player UI or custom overlays |
| `.onPlayPauseCommand(_:)` | Intercept Play/Pause | Media screens + toggle-able contexts |
| `.hoverEffect(.highlight \| .lift)` | System focus treatment | Stock behavior on posters/buttons — don't stack with custom scale |
| `@Environment(\.isFocused)` | Read current view's focus | In `PrimitiveButtonStyle` / custom styles |

### 2.2 Decision tree — "I need X focus behavior"

**Q: Default-focus a button on view appear.**
→ `.defaultFocus($focus, .play)` on the container. Never `focus = .play` in `onAppear` (races first render). If the view loads data, gate with `if !items.isEmpty`.

**Q: Set focus programmatically after data loads.**
→ `.task { focus = .play }` — runs after first render. Or `.onChange(of: items) { ... }`.

**Q: Focus should restore when a sheet / modal re-opens.**
→ `.focusScope(ns)` + `.defaultFocus($focus, .x, in: ns)`.

**Q: My custom view with no standard controls should be focusable.**
→ `.focusable(true)` + render focus state with `@Environment(\.isFocused)`.

**Q: I want to fully replace the system focus halo on a button.**
→ Custom `PrimitiveButtonStyle` reading `@Environment(\.isFocused)`, plus `.focusEffectDisabled()`. Do **not** use `.buttonStyle(.plain)` — it destroys focusability on tvOS.

### 2.3 Traversal mechanics (geometric, not hierarchical)

tvOS's focus engine is **geometric**. When you press right from a focused element:

1. Collect all focusable views currently on screen.
2. Filter to those in the rightward half-plane from the current focus center.
3. Score by angular proximity (angle weighted heavily) + center distance.
4. Pick the winner.

`.focusSection()` changes step 2: if no focusable exists inside the current section in the pressed direction, the engine treats the section as the origin and picks the nearest sibling section's default/last-focused child. Without it, focus bleeds diagonally between dense and sparse regions.

`.focusScope()` does **not** constrain traversal. It defines a namespace for default-focus restoration only.

### 2.4 Canonical patterns

**Sidebar + content (manual HStack approach):**

```swift
HStack(spacing: 0) {
    SidebarView()
        .frame(width: 320)
        .focusSection()
    ContentView()
        .focusSection()
}
.defaultFocus($focus, .sidebar)
```

Parent HStack **does not** get `.focusSection()`. Only children.

**Detail with pinned Play button, no scroll-jump:**

```swift
@FocusState private var focus: DetailFocus?
ScrollView {
    VStack(alignment: .leading, spacing: 40) {
        HeroHeader()
        HStack {
            Button("Play") { ... }.focused($focus, equals: .play)
            Button("Favorite") { ... }.focused($focus, equals: .favorite)
        }
        .focusSection()
        MetadataBlock()
        CastRow().focusSection()
    }
}
.defaultFocus($focus, .play, priority: .userInitiated)
```

`.userInitiated` beats `.automatic`. The `.focusSection` on the button row prevents diagonal jumps into metadata below.

**Horizontal shelf in vertical scroll:**

```swift
ScrollView(.vertical) {
    LazyVStack(spacing: 60) {
        ForEach(shelves) { shelf in
            VStack(alignment: .leading) {
                Text(shelf.title).font(.title2)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 30) {
                        ForEach(shelf.items) { PosterCard($0) }
                    }
                }
                .scrollClipDisabled()  // lets focus scale bloom past row edges
            }
            .focusSection()
        }
    }
}
```

**Custom focus treatment (no system halo):**

```swift
struct PosterButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Body(configuration: configuration)
    }
    private struct Body: View {
        @Environment(\.isFocused) var focused
        let configuration: Configuration
        var body: some View {
            configuration.label
                .scaleEffect(focused ? 1.08 : 1.0)
                .shadow(radius: focused ? 24 : 0)
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: focused)
                .onTapGesture { configuration.trigger() }
        }
    }
}
// Apply: .buttonStyle(PosterButtonStyle()).focusEffectDisabled()
```

### 2.5 Common bugs and fixes

- **`.buttonStyle(.plain)` kills focusability** — use `.buttonStyle(.card)` or `.borderless`, or a custom `PrimitiveButtonStyle` with `@Environment(\.isFocused)`.
- **ScrollView yanks layout** when focus handoff between focusables needs reconciling — wrap shelves with `.focusSection()`, never nest vertical ScrollViews.
- **`defaultFocus` not honored** — target not yet in hierarchy (gate with `if !items.isEmpty`), or competing `prefersDefaultFocus`, or FocusState is on a recreating view.
- **`focusSection` not bounding** — it's a hint, not a wall. For true constraint, `.onMoveCommand` intercepts and consumes the event.
- **Focus stuck in sidebar** — content pane has no focusable at same Y as the focused sidebar row; add `.focusSection()` + `.defaultFocus` on content.
- **`onExitCommand` swallowed** — a focused child ate it. Move handler to the focused level.
- **FocusState race in `onAppear`** — use `.task { ... }` or `.defaultFocus` instead.

### 2.6 Antipatterns (never do these)

- Calling `.focusable()` on a `Button` (double-declaring creates ghost candidates).
- Using `.onTapGesture` on actionable elements instead of `Button` (clickpad center press is unreliable with tap gestures).
- Putting `.focusSection()` on parent HStack **and** both children — the parent's section conflicts with children's.
- Reassigning `@FocusState` inside `onChange(of: focus)` — loop.
- `.animation(.default)` on a view containing focusable children — scope animations to specific properties.
- Assuming `.hoverEffect` is iOS-only. On tvOS it's **the** focus effect.

### 2.7 NavigationSplitView on tvOS — know the trade-off

The tvOS 17.2 Apple TV app redesign uses a sidebar pattern. The community signals are mixed:
- Apple's HIG endorses `NavigationSplitView` + `.tabViewStyle(.sidebarAdaptable)` (tvOS 18+ only) for apps with 6+ top-level destinations.
- The production focus-engine experts advise **manual HStack + focusSection per child** for tvOS 17+ because NavigationSplitView's built-in focus assumptions sometimes fight custom treatments.
- For Archive Watch's 5 tabs: manual HStack is the safer path given tvOS 17+ target. Revisit if deployment target moves to tvOS 18+.

Sources: WWDC21 #10153 "Direct and reflect focus in SwiftUI"; WWDC23 #10162 "The SwiftUI cookbook for focus"; WWDC24 #10144 "Work with windows in SwiftUI"; WWDC25 #284 "What's new in SwiftUI"; Apple developer docs (`FocusState`, `focusSection`, `focusScope`, `defaultFocus`, `focusEffectDisabled`); Airbnb Engineering "Mastering the tvOS Focus Engine"; Apple Developer Forums (#706321 ScrollView + prefersDefaultFocus incompatibility, #756261 .plain button unfocusable).

---

## 3. Layout

### 3.1 Safe area and margins

- **Safe area insets (1080p and 4K, tvOS-wide):** 90 pt leading/trailing, 60 pt top/bottom. Constant across resolutions — points don't scale.
- **Overscan reality:** older TVs crop 2–5% off every edge. Critical content (titles, buttons, posters) must stay inside the safe area. Decorative bleed (hero art, gradient washes) can extend to edges.
- **Usable width at 1920 pt:** 1920 − 180 = **1740 pt**.
- **Standard gutter between horizontal cards:** 30–80 pt (typical 40–60 pt).
- **Standard vertical spacing between stacked shelves:** minimum 80 pt — a 1.1× focused card must not collide with a neighbor row.
- **Shelf row height:** ~400–500 pt (card + title + subtitle + focus headroom).

### 3.2 Card sizes (observed across shipping apps)

| Context | Orientation | Size (approx.) | Notes |
|---|---|---|---|
| Home shelf poster | 2:3 | 200 × 300 pt | Plex/Infuse size |
| Home shelf landscape (TV, newsreel) | 16:9 | 380 × 214 pt | Apple TV size |
| Spine/sidebar poster | 2:3 | 140 × 210 pt | UHF channel spine |
| Detail hero backdrop | 16:9 full-bleed | Full width × ~45–60% height | |
| Detail poster inset | 2:3 | 260 × 390 pt | Overlapping backdrop |
| Category tile | 4:3 | 260 × 195 pt | |

### 3.3 Title labels on cards

- **Apple convention: titles below poster** in 1 line (bolder apps 2 lines max).
- **Infuse's move:** show title **only on focus** (fades in). Cleanest treatment in the study — eliminates baseline clutter.
- **Title font size at 10ft:** 20–22 pt is the readable sweet spot. 18pt is borderline. 17pt is unreadable at 10ft — per HIG.

Sources: Apple HIG — Layout; Median content-formatting guide; BPXL Craft primer; shipping app analysis (Apple TV, Plex, Infuse, Channels, UHF).

---

## 4. Typography

### 4.1 The tvOS ramp — use these tokens, don't hardcode

| Token | Size | Weight | Leading | Use |
|---|---|---|---|---|
| Large Title | 76 pt | Medium | 80 pt | Hero headlines, tentpoles |
| Title 1 | 57 pt | Medium | 61 pt | Shelf / section titles |
| Title 2 | 48 pt | Medium | 52 pt | Subsections |
| Title 3 | 38 pt | Regular | 42 pt | Card headlines |
| Headline | 38 pt | Semibold | 42 pt | Emphasized body start |
| **Body** | **29 pt** | **Regular** | **36 pt** | **Default — floor for 10ft** |
| Callout | 31 pt | Regular | 38 pt | Highlighted inline |
| Subheadline | 29 pt | Regular | 36 pt | Secondary |
| Footnote | 23 pt | Regular | 32 pt | Metadata |
| Caption 1 | 25 pt | Regular | 32 pt | Captions, badges |
| Caption 2 | 23 pt | Medium | 32 pt | Denser metadata |

Rules:
- **29 pt is the 10-ft body text floor.** Below that is "difficult to read at living room distances" (direct HIG quote).
- **Titles 48 pt or larger.**
- SF Pro Display for all text ≥ 20 pt (automatic with system tokens).
- Avoid Ultralight/Thin — they shimmer at distance.
- Line-height 1.1–1.25×, never tighter than 1.05×.
- Serif is acceptable as display type (Archive Watch's editorial flavor) but **body must stay sans at 29 pt**.
- **Dynamic Type does NOT apply on tvOS.** Bold Text is honored automatically when using system tokens.

### 4.2 Reading text on hero art

Never place body text directly on a poster/backdrop without a scrim. Target ~7:1 contrast ratio because couch glare eats 1.5–2 stops off whatever you design.

Sources: Apple HIG — Typography; BasThomas tvOS-guidelines; createwithswift Materials.

---

## 5. Color & materials

- **Dark-first, always.** tvOS's default is dark; bright backgrounds bleach the room and clash with cinematic content. Only ship Light mode if it earns its keep.
- **System materials** (hardware-accelerated blur + vibrancy):
  - `.regularMaterial` — full-screen backgrounds, panels with text
  - `.thinMaterial` — stacked layers where depth matters
  - `.ultraThinMaterial` — transient HUDs only
  - **Text container?** favor `.regular` or `.thick`.
- **Vibrancy colors** only on materials — don't paint solid hex over a vibrancy layer; use the semantic vibrant palette so legibility adapts to backdrop luminance.
- **Contrast:** WCAG AA floor, but target 7:1 for body on ambient hero art.
- **Focus = the single strongest brightness affordance** in a screen. Reserve the lift for focused items; don't spray bright accents everywhere.
- **Avoid quaternary colors on `.thin`/`.ultraThin` materials** — contrast is insufficient.

Archive Watch's per-category accent palette (Decision 013) is the correct approach: one accent per content category (Feature Film #FF5C35, Silent Era #C9A66B, etc.), used sparingly for focused-state glow, shelf-title accent dot, and the brand's home rail.

Sources: HIG Materials; WWDC22 "Design with accessibility in mind".

---

## 6. Motion

### 6.1 Canonical animation values

| Transition | Value |
|---|---|
| Focus scale (tiles/cards) | **1.08–1.10** (Plex 1.08, Infuse 1.10, Channels 1.06) |
| Focus scale (buttons/controls) | **1.06–1.08** |
| Focus transition | `.spring(response: 0.4, dampingFraction: 0.82, blendDuration: 0)` — ~400ms critically-damped |
| Card press-down | `.spring(response: 0.25, dampingFraction: 0.75)` |
| Modal / detail push | `.smooth(duration: 0.5)` or `.spring(response: 0.5, dampingFraction: 0.9)` |
| Tab switch | `.easeInOut(duration: 0.35)` (no spring — tabs don't bounce) |
| Shelf auto-scroll | `.timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.5)` ease-in-out |
| Full-screen player present | `.spring(duration: 0.6, dampingFraction: 0.78)` + crossfade to black |
| Hero carousel rotation | **7–8 seconds** per item (Apple ~7s, Infuse ~8s, Plex 10s too slow) |
| Hero crossfade duration | 0.6–0.8 s |
| Hero Ken Burns zoom | 1.0 → 1.05 over the full dwell |

### 6.2 `hoverEffect` (the tvOS focus effect)

- `.highlight` — brightens ~+15% luminance, scales ~1.10, adds specular sheen tracking Siri Remote trackpad. **Use for poster art and image-forward content.**
- `.lift` — scale ~1.08 + drop shadow (y:12, blur:24, opacity:0.35), no specular. **Use for buttons, text cards, settings rows.**
- **Never stack `hoverEffect` with custom `scaleEffect`** driven by `@FocusState` — they fight. Pick one:
  - Stock: `.hoverEffect(.highlight)` alone
  - Custom: `.hoverEffectDisabled()` + drive scale/shadow/rotation yourself

### 6.3 Parallax on focused tiles

The real Apple TV parallax uses layered image stacks (`.imagestack` in the asset catalog) with per-layer translation/rotation driven by Siri Remote trackpad position.

SwiftUI approximation paths:
1. **Layered images + `rotation3DEffect`** driven by drag on the Remote — best visual, most code
2. **`UIViewRepresentable` + `UIInterpolatingMotionEffect`** — most accurate, UIKit plumbing
3. **`.visualEffect` + `GeometryProxy`** (tvOS 17+) — cheap pseudo-parallax, focus-state-driven

For Archive Watch: option 3 for every card in a grid (can't afford 200 UIKit parallax layers); option 2 for the hero.

### 6.4 Attention & micro-motion

- **Idle pulse on primary CTA:** scale 1.0 → 1.03 → 1.0 over 1.6 s ease-in-out, repeating, only after focused for >3 s with no input. Never pulse continuously — reads as nagging.
- **Shimmer for skeleton posters:** linear gradient sweep L→R over 1.2 s ease-in-out, looped. Angle 20°, gradient width ~30% of card.
- **Hero carousel:** crossfade (0.8 s) + slow Ken Burns zoom (1.0 → 1.05 over the full 6–8 s dwell). Crossfade alone feels static; zoom alone induces motion sickness at 10 ft.

### 6.5 Performance costs

Apple TV HD (A8, 1GB RAM) vs. 4K (A10X–A15, 3GB). tvOS locked at 60fps as of tvOS 26 (no 120fps).

Cost ranking (cheap → expensive):
1. `opacity`, `scaleEffect`, `offset` — effectively free (GPU composited)
2. `rotation3DEffect` — cheap up to ~50 instances
3. `shadow(radius:)` — **expensive**, rasterized per frame. Budget ~20 shadowed views onscreen. Wrap in `.drawingGroup()` to flatten if needed.
4. `blur(radius:)` — **very expensive** on A8. Each 8 pt ≈ doubles cost. Never animate blur radius. Prefer `Material` (hardware-accelerated).
5. `matchedGeometryEffect` on images — moderate; 1–2 active hero transitions is fine.

**Rules for Archive Watch:** animate transforms (scale/offset/rotation/opacity) freely; treat shadow and blur as static set-dressing; never animate blur radius; use `.drawingGroup()` on complex focused cells only if profiling shows dropped frames on A8.

### 6.6 Reduce Motion (App Store requirement)

Check `@Environment(\.accessibilityReduceMotion)`. When true:
- Disable parallax on focused posters
- Disable hero carousel auto-rotate
- Replace spring animations with crossfade/instant state change

Sources: WWDC16 #210 "Focus Interaction in tvOS"; WWDC20 #10042 "Design for the Living Room"; WWDC23 #10158 "Animate with Springs"; WWDC23 #10054 "Explore SwiftUI animation"; WWDC24 #10144 "Enhance your UI animations"; HIG — Motion.

---

## 7. Image pipeline

### 7.1 Why AsyncImage is wrong for poster grids

- Starts download only when a LazyHStack/Grid cell is **realized** — not appearance, not focus. That's the pop-in.
- Routes through `URLSession.shared` and respects `URLCache.shared` — but the decoded `UIImage` is thrown away on every view rebuild.
- No prefetching API.
- Decoding on draw time (lazy) = main-thread hitches when multiple cells paint at once.
- Re-downloads on view identity changes (URL computed in `body` triggers teardown).

### 7.2 Custom `ImageLoader` architecture

Actor pattern with NSCache + URLSession + ImageIO decoding, inflight-coalesced:

```swift
actor ImageLoader {
    static let shared = ImageLoader()
    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage, Error>] = [:]
    private let session: URLSession

    init() {
        cache.countLimit = 400           // ~3-4 viewports worth
        cache.totalCostLimit = 150_000_000  // 150 MB decoded (80 MB for ATV HD)
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache.shared
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    func image(for url: URL, targetSize: CGSize, scale: CGFloat) async throws -> UIImage {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        if let task = inFlight[url] { return try await task.value }
        let task = Task<UIImage, Error> {
            let (data, _) = try await session.data(from: url)
            try Task.checkCancellation()
            let image = try await Self.decode(data: data, targetSize: targetSize, scale: scale)
            cache.setObject(image, forKey: url as NSURL, cost: image.estimatedByteCost)
            return image
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        return try await task.value
    }

    static func decode(data: Data, targetSize: CGSize, scale: CGFloat) async throws -> UIImage {
        try await Task.detached(priority: .userInitiated) {
            let maxDim = max(targetSize.width, targetSize.height) * scale
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,  // force eager decode
                kCGImageSourceThumbnailMaxPixelSize: maxDim
            ]
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { throw ImageError.decode }
            return UIImage(cgImage: cg, scale: scale, orientation: .up)
        }.value
    }
}
```

**The magic line: `kCGImageSourceShouldCacheImmediately: true`** — forces decode now, not at draw. Also downsamples in one pass at the final display size, saving ~10× memory vs decoding raw JPEG.

### 7.3 SwiftUI wrapper

```swift
struct RemoteImage: View {
    let url: URL?
    let targetSize: CGSize
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Color.black.opacity(0.15) }
        }
        .task(id: url) {
            guard let url else { return }
            image = try? await ImageLoader.shared.image(
                for: url, targetSize: targetSize, scale: 2
            )
        }
    }
}
```

`.task(id: url)` gives free cancellation on disappearance / URL change.

### 7.4 Prefetching pattern (SwiftUI has no built-in API)

Drive from the data source, not the view. When shelf items array changes:

```swift
.onChange(of: shelfItems) { _, new in
    for item in new.prefix(20) {
        Task.detached(priority: .utility) {
            _ = try? await ImageLoader.shared.image(for: item.posterURL, ...)
        }
    }
}
```

**Focus-direction prefetch:** when focus lands on shelf index `i`, prefetch `[i+1 ... i+6]` at high priority and `[i-2 ... i-1]` at low. Six items is the sweet spot.

### 7.5 Memory budgets

- Decoded 240×360@2x poster (480×720 RGBA) = ~1.4 MB
- ATV HD (1GB shared, ~300MB practical): keep decoded-cache ≤ 100 MB (~70 posters)
- ATV 4K (3GB, ~700MB practical): keep ≤ 200 MB
- `NSCache.totalCostLimit` is a soft cap; trust the OS memory-pressure signal

### 7.6 SwiftUI gotchas

- AsyncImage re-download on rebuild: **never compute URLs in `body`** — store on the model.
- Don't `.id(item.id)` on `RemoteImage` — use on the container only.
- `.task(id:)` cancellation works only if the loader checks `Task.isCancelled` between awaits.
- Pending image load must NOT gate layout. Always render a placeholder Color immediately.

Sources: WWDC18 #219 "Image and Graphics Best Practices"; WWDC21 "Demystify SwiftUI"; Apple sample "Destination Video" (tvOS target); Nuke / Kingfisher source for reference.

---

## 8. Remote control + accessibility

### 8.1 Siri Remote (2nd gen) button semantics

| Button | At root | In-app | In playback |
|---|---|---|---|
| Back (short) | Exit to Home | Pop one level | Exit player |
| Back (long-press) | Home Screen (system) | Home Screen | Home Screen |
| TV | Home / last app (user pref) | — | — |
| Siri | Dictation / search UI | Context search | "Who said that?" rewind |
| Play/Pause | — | Activate focused item (some screens) | Toggle playback |
| Clickpad center | Select focused | Select focused | Pause/resume |
| Clickpad edges | Move focus | Move focus | Scrub / chapter nav |

### 8.2 Back button contract (App Store rejection risk if violated)

- **Never override Back outside player/modal** — Guideline 4.0 treats reassignment as rejection risk.
- Back at tab root = exit app (system behavior, don't intercept).
- Back inside NavigationStack = pop (system behavior — your own `onExitCommand` is usually redundant).
- Back in modal = dismiss.
- Back in full-screen player = exit player (AVKit does it).
- Long-press Back = Home Screen (system, don't intercept).

### 8.3 Play/Pause semantics

- Non-video screens: ignore (unless you have ambient trailer).
- **Focused film card + Play/Pause = start playback** (convention across Apple TV, Netflix, Disney+). Wire via `.onPlayPauseCommand` on the focused card.
- Video player: AVPlayerViewController handles — don't override.

### 8.4 Accessibility — non-negotiables

- **Dynamic Type does NOT apply on tvOS.** Use system tokens; don't hardcode sizes.
- **Bold Text** — honored automatically with system fonts.
- **Reduce Motion** — required. `@Environment(\.accessibilityReduceMotion)` gate on every spring/parallax/auto-rotate.
- **Increase Contrast** — `@Environment(\.colorSchemeContrast)`. Drop scrims, raise accent opacity when `.increased`.
- **VoiceOver** — every custom focusable needs `.accessibilityLabel` + `.accessibilityHint`. `.accessibilityAddTraits(.isButton)` on focusable non-Buttons.
- **Switch Control** — works via focus engine for free if all actionables are `Button`s or `.focusable(true)`.
- **Closed captions** — AVPlayerViewController surfaces from HLS/MP4 tracks. For Archive items without tracks, check via `AVAsset.mediaSelectionGroup(forMediaCharacteristic: .legible)` and surface a "Captions not available" notice.

### 8.5 Internationalization

- RTL: focus engine auto-swaps left/right directions. `onMoveCommand` gives you semantic `.leading`/`.trailing` — never physical `.left`/`.right` in logic.
- Dates/numbers: `.formatted(date: .abbreviated, ...)`, `Duration.seconds(x).formatted()` honor locale automatically.

Sources: HIG — Remote and Controllers; Apple Support "Siri Remote"; WWDC21 #10046 "Design for the Siri Remote"; WWDC22 #10032 "Dive into App Intents"; App Store Review Guidelines 2.5.1, 4.0; AVPlayerViewController docs.

---

## 9. Shipping-app patterns (what to copy, what to avoid)

### 9.1 Navigation shell — the spectrum

- **Apple TV (17.2+):** sidebar — ~80pt collapsed / ~280pt expanded, auto-expands on focus entry. 6+ top-level destinations.
- **Channels, Plex, Infuse:** top tabs, 4–6 destinations, centered.
- **UHF:** inverts the model — left "channel spine" IS the content, not navigation chrome.

**Decision for Archive Watch:** 5 top-level tabs is in tab-bar territory. But we've committed to sidebar per user request. Implementation: manual HStack + `.focusSection()`, expand on focus, orange accent for selected.

### 9.2 Home screen patterns

- Hero carousel: 7–8 second rotation, crossfade, subtle Ken Burns (1.0 → 1.05). Pause on focus entry.
- Hero content: category, title, year/runtime/byline. **No synopsis** (noisy, unread at 10ft).
- Randomize the hero pool per-launch, not a fixed 7. Draw from top-N-by-popularity (shelf count), shuffle, take 7.
- Below hero: 4–8 shelves typical. Continue Watching first if non-empty, Editor's Picks / For You second, then editorial.

### 9.3 Shelf design

- Card size: 200×300 pt portrait, 380×214 pt landscape (match content type to aspect).
- Spacing: 30–40 pt between cards.
- **Title below card, on focus only** (Infuse pattern) is the cleanest. Alternative: always-visible 1-line title at 20–22 pt.
- Focus effect: scale 1.08 + soft drop shadow (radius 20pt, opacity 0.3) + accent glow on border.

### 9.4 Detail screen

- **Auto-focus Play on entry** (Plex's miss is the #1 complained-about detail behavior).
- Full-bleed backdrop top ~45–60%. Poster insets lower-left, metadata to its right.
- Play button pill, large, pinned at the seam between backdrop and metadata (roughly Y = 55%).
- "More Like This" shelf at the bottom.
- Back = pop (don't intercept).

### 9.5 Search

- Use Apple's directional keyboard (`UISearchController` / `.searchable`) — you get Siri dictation free.
- Live results — don't require submit.
- Never invent a grid keyboard — tests worse with Siri Remote trackpad.

### 9.6 Playback

- AVPlayerViewController baseline. Minimal custom chrome.
- Persist timecode (not percent) for resume.
- Info panel: chapters, subtitles, audio, runtime, source attribution.
- Infuse-level scene thumbnails on scrub = aspirational, not required.

Sources: Field study of Apple TV app (17.2+), Channels, UHF, Plex, Infuse — reviews from The Verge / 9to5Mac / MacRumors, Firecore release notes, Fancy Bits (Channels) blog.

---

## 10. Archive Watch-specific applications

Mapping the above to our app's concrete decisions already logged in DECISIONS.md:

- **Decision 006 (tvOS-first):** the whole playbook applies.
- **Decision 007 (TMDb):** 500px w500 posters = 500×750 native; target 240×360@2x display = 480×720 decoded. ImageIO downsample in one pass (§7.2).
- **Decision 011 (hybrid curation):** hero rotation uses randomized top-N from the full catalog (§9.2), not just curated 7.
- **Decision 012 (adult filter on):** safe living-room defaults align with HIG "shared device" principle (§1).
- **Decision 013 (per-category accents):** reserve brightness for focus (§5); accents used sparingly for focus glow, shelf dot, brand rail.
- **Decision 014 (random actions):** App Intents + `onPlayPauseCommand` wiring (§8.3).
- **Decision 015 (Top Shelf):** 1920×1080 hero, `.sectioned` style, deep links (`archivewatch://item/{id}`).

---

## Five unbreakable rules (the backstops)

When in doubt, check against these:

1. **Dark-first, 29 pt body floor, 90/60 safe area.**
2. **Back is sacred — never intercept outside player/modal.**
3. **Reachability contract — every focusable reachable from every other via arrows, in every direction that has content.**
4. **No `.buttonStyle(.plain)` on tvOS** — breaks focusability. Use `.borderless` + `.focusEffectDisabled` + custom `isFocused` treatment, or `.buttonStyle(.card)`.
5. **Preserve focus across state changes** — by stable identifier, not index.

---

*Playbook last reviewed: 2026-04-19. Revisit after each WWDC.*
