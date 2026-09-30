# How far below iOS 26 can the iPhone/iPad app go? (measured 2026-09-29)

Owner, 2026-09-29: *"The current native app requires ios 26, but we are
investigating if we can make it work on older hardware."* An iPhone 6 Plus on
iOS 12.5.8 (iPhone7,1, USB-paired to the Mac) prompted it.

Method: the Decision 148 method for tvOS — build the iOS scheme at a lower
deployment target from the command line (`IPHONEOS_DEPLOYMENT_TARGET=…`, or the
app target alone lowered in a throwaway edit of project.pbxproj, restored with
`git checkout`), count the errors, never commit the experiment.

## What the toolchain allows

The iOS 27 SDK in the installed Xcode states `MinimumDeploymentTarget: 15.0`
(`SDKSettings.json`), and App Store uploads must be built with a current SDK.
**No native build can target iOS 12** — or anything below 15 — at all.

## What the code allows

| Target | Result | What fails |
|---|---|---|
| 16.0 | 428 errors (app target alone) | SwiftData (`@Model`, `ModelContext`, `Schema`) and Observation (`@Observable`) — every piece of user state and all shared app state. Below 17 means rewriting the data layer. |
| 17.0 | 55 errors / 29 sites, 6 files | the iOS 18 Tab API (RootView), `Mutex`/`withLock`, `Color.mix`, `presentationSizing`, plus everything listed for 18 |
| **18.0** | **17 sites, 2 files** | `AutoCaptions.swift` (7: `SpeechTranscriber`, `AssetInventory` — iOS 26), `ClipExporter.swift` (10: the iOS 26 Core Image composition API `init(applyingFiltersTo:applier:)` / `Configuration`) |

The widgets build at 18 (their `OpenURLIntent` is iOS 18, `containerBackground` 17).

## Hardware

iOS 17 and iOS 18 run on the SAME iPhones (XS / XS Max / XR and newer); iOS 26
is what dropped the XS and XR. So 18 reaches every phone 17 would, with half the
fallbacks. iPhones 6s–X stop at iOS 15/16: out of reach of the data layer.
iPhone 5s–6 Plus stop at iOS 12: out of reach of the toolchain.

## So

- **Native floor 18** is a small change: `#available(iOS 26, *)` around live
  captions (a feature that stays iOS 26-only, Decision 154) and the older
  `AVVideoComposition(asset:applyingCIFiltersWithHandler:)` path for clip export
  on 18–25. Unverified until an iOS 18 device exists on the bench — none does
  today (iPhone 12 on 26.6.1, iPhone 15 Pro and iPad Pro on 27.2).
- **iOS 12** is served only by the website. Safari 12 cannot parse today's
  viewer: `watch.js` has 64 optional chains and 3 nullish coalescings, `app.js`
  28, the sync files 18 more plus `??=`/`||=` — one syntax error blanks the
  script. Layout also leans on flex `gap` (62, Safari 14.1), `inset` (13, 14.1),
  `aspect-ratio` (8, 15), `dvh` (4, 15.4), `color-mix` (1, 16.2); the clipboard
  (6, 13.1) and shared-list decoding (`DecompressionStream`, 16.4) need feature
  checks. The site's rule is vanilla JS with no build step, so the syntax is
  rewritten by hand.

## Outcome (same day)

Owner chose the native floor of 18 (Decision 155). Two more iOS 26 sites surfaced
once compilation got further — the Clip Studio look preview and LibraryView's
`dropDestination` overload — plus LiveCaptions' stored `AnalyzerInput`
continuation. All gated; iOS, tvOS and macOS Release build with zero warnings.
