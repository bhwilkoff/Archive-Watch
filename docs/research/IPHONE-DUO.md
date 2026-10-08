# iPhone Duo + the new App Store assets — research (2026-10-08)

Owner: *"There are new fields, screenshots, and a whole new device class that need
to be figured out for our Apple App Store submissions. I will be purchasing an
iPhone Duo, but I don't have it available for testing."*

Everything below is from Apple's own pages, App Store Connect itself (read in
Chrome on our app, 6776697407, without changing anything), or our code. Blog
summaries were read and NOT relied on — several contradict Apple.

---

## 1. What Apple now asks of a submission

| Item | Status | Source |
|---|---|---|
| **iPhone Duo screenshots** | Upload is OPEN now (a third device tab on the iOS version page, beside "iPhone with Dynamic Island (medium)" and "iPad 13"). **Required from April 2027** for any app built with the iOS 27.1 SDK or later | ASC release notes 2026-10-05; screenshot specifications |
| **Product page header** (creative asset) | New, optional. ASC version page → Product Page Information → **Header and Search Results** tab. "0 of 1 Header Asset" | ASC release notes 2026-10-05; seen on our page |
| **Search results asset** (creative asset) | New, optional. Same tab. If absent, In-App Events, previews, then the first three screenshots show instead | asset best practices |
| **Asset Library** | New sidebar item. Holds screenshots, previews and creative assets; an asset can be submitted and approved ON ITS OWN, ahead of use, once the app has an approved version | "Manage your App Store assets", "Submit assets from Asset Library" |
| **Device Preview** | New button on the screenshots tab: renders the product page and the search results page on any device, including Duo closed/open, rotated, Dark Mode | seen on our page |
| **Minimum SDK** | From April 2027 every upload must use the iOS/iPadOS/tvOS 27 SDK or later | news 2026-09-09 |
| App Review contact phone | Must be international format (`+1…`) | release notes 2026-08-19 |
| No alpha | Screenshots may not carry an alpha channel or transparency | release notes 2026-07-08 |

Creative assets are only shown to people on iOS/iPadOS 27 or later. They go live
when the version (or the standalone asset submission) is approved and released.

### 1a. Exact specifications

**iPhone Duo screenshots** (one "iPhone Duo" set, up to 10, .png/.jpg, no alpha):

| Display | Portrait | Landscape |
|---|---|---|
| Outer (closed) | 1398 × 2034 | 2034 × 1398 |
| Inner (open) | 2007 × 2853 | 2853 × 2007 |

**iPhone Duo app previews**: 886 × 1920 or 1920 × 886, 15–30 s, ≤30 fps,
H.264 10–12 Mbps (or ProRes 422 HQ), stereo AAC 256 kbps, ≤500 MB, up to 3.

**Creative assets** (images: no alpha):

| Placement | Ratio | Pixels | Format |
|---|---|---|---|
| Product page header | 21:9 | 3840 × 1646 | .jpg/.png |
| Search results | 3:2 | 1920 × 1280 min, 3840 × 2560 max | .jpg/.png |
| Universal (header AND search) | 16:9 | 5244 × 2950 | .png |
| Header video | 21:9 | 3840 × 1646, 30/60 fps, 5–30 s | .mov/.m4v/.mp4 |
| Search video | 3:2 | as the image, 30/60 fps, 5–30 s | .mov/.m4v/.mp4 |

Videos loop and play muted (search results cannot unmute). In-App Event media
(16:9 card / 9:16 detail) now live in the same library.

### 1b. What the Preview tool showed for OUR page today

- **Duo, closed, product page**: the App Store itself puts its toolbar and tab
  bar in a vertical strip on the right; our existing 6.3" iPhone screenshots are
  used as the fallback, two across.
- **Duo, open**: five of our phone screenshots across the page.
- **Duo, search results**: our icon, name, subtitle and the **first three
  screenshots** (Home, Night of the Living Dead, His Girl Friday). A search
  results asset would replace those three.

So nothing is broken today; the Duo slot falls back to scaled phone shots. It
becomes a rejection only in April 2027.

### 1c. The App Store Connect API

The legacy `appScreenshotSets` API has **no Duo display type** (its
`ScreenshotDisplayType` stops at `APP_IPHONE_67`). Duo screenshots and the creative
assets go through the new **Asset Library** API: display class `IPHONE_DUO`,
placement types `APP_SCREENSHOT`, `PRODUCT_PAGE_HEADER_ASSET`,
`APP_STORE_SEARCH_RESULTS_ASSET`. Any upload automation we write targets
that API, not the old one.

---

## 2. The device, from Apple's HIG and docs

- Two displays, a hinge. **Outer**: wider and shorter than any iPhone, compact
  width. **Inner**: the largest iPhone display, regular width. Ships with iOS
  27.1 on 2026-10-23.
- **Poses**: closed; open flat; partially folded like a book; set down like a
  laptop (tabletop); standing on its edges. Apple: *don't design a layout per
  pose* — compact width outside and regular width inside cover every pose.
- **Vertical controls**: the status bar, Dynamic Island, toolbars, back button
  and tab bar move to a strip down the right edge, on the outer display and on
  the inner display in landscape. The inner display in portrait keeps normal
  horizontal bars. Standard `TabView`/`NavigationStack`/`.toolbar` get this for
  free; custom bars do not.
- **Reserved regions**: the outer camera (always), the inner camera (only while
  active), and the **fold** (only while partially folded). System sheets, alerts,
  menus and split views move away from the fold; custom views use
  `GeometryProxy.reservedRegions(kind:)` (`.division`, `.occlusion`).
- **ArrangementView** (`UIArrangementViewController`): a primary + secondary
  container. Split arranges side by side or stacked; overlay puts one over the
  other and separates them across the fold. Apple's own example is a **player
  with an Up Next list** — our exact shape.
- **Tabletop**: Apple: media at the top, tappable controls on the stable bottom
  half; the same controls as every other pose. Partially folded video
  "extends to fill half of the screen".
- **Multitasking**: every app takes part in Split View on the inner display, and
  Duo is "the first iPhone to support multiple instances of your app's UI" — on
  the inner display only.
- **Hinge**: `onHingeChange` / `UIHingeInteraction` — for effects only, never
  layout.

### 2a. SDK behavior (this decides our first move)

| Built with | On iPhone Duo |
|---|---|
| iOS 26 SDK or earlier | Runs boxed: centered with empty space when open; left of the status bar when closed |
| iOS 27 SDK | Fills most of the inner display; still avoids the right-edge status bar |
| **iOS 27.1 SDK** | Edge to edge on both displays; bars move vertical |

**Our App Store builds use Xcode 26.6** (`appstore-build.yml`), i.e. the iOS 26
SDK, so today's Archive Watch runs BOXED on a Duo. Screenshots of a boxed app
would be accurate and poor. Getting the Duo look needs Xcode 27.1 in CI. GitHub's
`xcode-27` runner image lists Xcode 27.0 beta only, so it has to be checked when
we switch. The April 2027 iOS 27 SDK minimum forces the move anyway.

---

## 3. Our iOS code against Apple's checklist (audited 2026-10-08)

**Clean on every hard rule**: no `UIScreen.main`, no `UIWindow(frame:)`, no
`UIDevice` orientation, no `userInterfaceIdiom`, no device-size checks, no
layout computed once at launch, no `UIRequiresFullScreen`. All three
orientations are declared. `docs/IPAD-DESIGN.md` §5.2 already forbids
orientation-driven layout. That is why the app should resize correctly.

**What will change on a Duo, and needs a look:**

1. **Every "iPad" layout turns on when the Duo opens.** 13 views key on
   `horizontalSizeClass == .regular`, which Apple now says is NOT iPad. This is
   mostly what Apple wants (two-column Detail and Series, sidebar-adaptable tabs,
   the Channels guide grid, the Clip Studio side-by-side editor, Studio inspector
   as a column). Their comments say "iPad" and should say "regular width". Two
   need a decision on the glass: **Channels** drops the "On Now / Guide" picker at
   regular width, and the **sidebar** places appear (Cartoons, Party Play…).
2. **Full-bleed fills crop harder on the wider outer display**: Home hero
   (`HomeView_iOS.swift:319`, full width × 232 pt), Series header
   (`SeriesDetailView_iOS.swift:84`, 16:9 fill at full width × 220 pt). Apple
   names `.fill` on wide displays as a known problem.
   Decision 097 (a hero never reshapes its art) already governs the answer.
3. **The fold.** Our own overlays — the player's title/description overlay
   (Decision 037), the caption overlay (D070/118), the Channels guide — are
   custom views. They are the places to read `reservedRegions(kind: .division)`.
   The player + Up Next / Episodes shape is Apple's own `ArrangementView` example.
4. **Toolbar items** need a symbol AND a title (`Label`) to move into the vertical
   strip; text-only buttons stay horizontal. Not yet audited item by item.
5. **Multi-window**: our scene manifest is `UIApplicationSceneManifest~ipad`
   only, so the Duo gets no second window ("Open in New Window" stays hidden).
   Whether the Duo should offer it is an owner call, not a defect.
6. Small: `Services/ImageLoader.swift:41,91` decodes at a fixed 2× scale (Apple
   asks for `displayScale`); `ClipTimeline_iOS.swift:191` sets its zoom from the
   first layout's width only, so the zoom stays at the old width after a fold.

---

## 4. How to make Duo screenshots without the device

**The route is the iPhone Duo simulator in Xcode 27.1 (Device Hub)**, which
Apple calls "the best way to test the full native experience". It simulates open,
closed, rotated and partially folded. This Mac has Xcode 27.0 beta (27A5194q)
with no Duo device type and no iOS 27 runtime, so step 1 is installing Xcode 27.1
RC (a multi-GB download — owner's go-ahead first).

Then the existing recipe (`docs/app-store-listing.md` "Screenshots (iOS)")
carries over unchanged: Debug build, `SIMCTL_CHILD_AW_START_TAB=<tab>` or
`SIMCTL_CHILD_AW_START_ITEM=<archiveID>`, wait for the seed DB, `xcrun simctl io
<udid> screenshot`. Two checks before trusting it:

- the captured pixel size must equal the spec (1398 × 2034 outer, 2007 × 2853
  inner); if the simulator renders at another scale, the capture is wrong, not
  resizable;
- the build must be the **27.1 SDK** one, or the shots show the boxed app.

**Which shots** (Apple: "show your app across orientations"). One Duo set, both
displays mixed, sequenced as a story:

1. Outer, portrait — Home (hero + shelves), the vertical strip visible.
2. Inner, landscape — Detail, two-column (poster + facts).
3. Inner, portrait — Channels guide grid.
4. Inner, landscape — Browse grid.
5. Outer, landscape — the player.

A partially-folded pose cannot be shown in a flat screenshot; skip it.
Screenshots stay plain captures with no captions, as now (our copy rule, and
Apple's "show the app in use").

**Then check the set in Device Preview** before submitting, including Dark Mode.

---

## 5. Header and search results assets for Archive Watch

What Apple asks: one clear idea, a first-time visitor in mind, the app's purpose
"at a glance" in search, the subject in the center (the page crops by device).
**Not allowed**: prices, URLs (so no "archivewatch.org"), copyright symbols,
awards, other platforms' logos, anything above a 4+ rating.

What OUR rules add:

- **No AI-written copy** (owner 2026-09-26). The asset is text-free, or carries
  words the owner writes. Apple says text "enhances rather than describes".
- **Rights**: a still in a public advertisement is closer to a broadcast than to
  a clip. Draw it from the hero tier (`isHeroRightsSafe`, the marquee's
  evidence bar), not from everything the app shows.
- **4+**: the horror canon that sits in our screenshots today (Night of the Living
  Dead) is a poor choice for a header.
- **Recommended first asset**: ONE **universal** 16:9 PNG at 5244 × 2950, so a
  single approved image serves both the header and search. A film still from the
  hero tier, centered subject, no text; check the crops in Device Preview.
  Apple's templates (Figma universal, Photoshop/Pixelmator header + search, with
  safe areas) are linked from <https://developer.apple.com/app-store/asset-best-practices/>.
- A **search video** (3:2, 5–30 s loop, muted) is the stronger form for a film
  app, and it can be cut from a guaranteed-tier film with our own Creation
  Studio.
- Submit it **standalone from the Asset Library**: our iOS app has an approved
  version, so it needs no new build.

---

## 6. Owner decisions (nothing is blocked today)

1. **Install Xcode 27.1 RC on this Mac?** Required for the Duo simulator and the
   screenshots. A large download from developer.apple.com.
2. **Move App Store builds to Xcode 27.1** (the iOS 27.1 SDK) — the only way the
   app goes edge-to-edge on a Duo, and required for all uploads by April 2027.
   Depends on GitHub's runner image; Decision 148 (tvOS floor below 27) and 155
   (iOS 18 floor) are unaffected — the SDK is not the deployment target.
3. **The header/search image**: which still (or none), and any words — yours.
4. **Duo multi-window** (section 3.5): offer "Open in New Window" on the inner
   display, or keep it iPad-only.
5. Before any Duo UI change: an iOS-DESIGN.md section for the Duo (binding-doc
   rule), then PARITY.md.

## Sources

- ASC release notes: <https://developer.apple.com/help/app-store-connect/release-notes/>
- Screenshot specifications: <https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications>
- App preview specifications: <https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications>
- Creative assets specifications: <https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications>
- Manage your App Store assets: <https://developer.apple.com/help/app-store-connect/manage-app-information/manage-your-app-store-assets>
- Submit assets from Asset Library: <https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-assets-from-asset-library>
- Asset best practices + templates: <https://developer.apple.com/app-store/asset-best-practices/>
- Prepare for iPhone Duo: <https://developer.apple.com/iphone-duo/prepare/>, <https://developer.apple.com/iphone-duo/>
- HIG, Designing for iPhone Duo: <https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo>
- Preparing your app for iPhone Duo: <https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo>
- Tech talks 111461–111466 (design, prepare, bars, poses, multiple displays, camera)
- News 2026-09-09, 09-16, 09-18, 10-05: <https://developer.apple.com/news/>
- GitHub runner Xcode 27: <https://github.com/actions/runner-images/issues/14404>
- ASC API enums: `ScreenshotDisplayType`, `AppAssetLibraryDisplayClass`, `AppAssetLibraryPlacementType`
