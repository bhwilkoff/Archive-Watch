# Archive Watch — TV Platform Implementation Backlog

**Status:** Active. Strategy = Decision 047. UI rules = `docs/TV-DESIGN.md`.
Platform viability/fees/submission = `docs/TV-PLATFORM-EXPANSION.md`.
**Created:** 2026-08-03.

Every item has an ID, an owner (**ENG** = implementable here, **OWNER** = only
Ben can do it), a size, dependencies, acceptance criteria, and the skill to
invoke. **Owner-blocked items are also collected in §OWNER at the bottom** —
that section is the answer to "what do I have to do to publish this?"

Sizes: **S** ≤ half a day · **M** 1–3 days · **L** 1–2 weeks · **XL** > 1 month.

---

## The shape of the work

Two builds unlock five of the seven native targets, and two zero-app routes cover
the closed platforms:

```
android/ (Kotlin + Compose + Media3, zero GMS)
    └── + TV form factor ──┬── Google TV / Android TV   (Play, $0 more)
                           └── Fire TV                  (Amazon, $0)

/ (vanilla PWA, no build step)
    └── + TV focus layer ──┬── LG webOS      (Seller Lounge, $0, global)
                           ├── Samsung Tizen (Seller Office, $0, US-only tier)
                           └── VIDAA / Titan / Zeasn  (partnership-gated)

Cast receiver (HTML) ──── Chromecast · Google TV · Chromecast-built-in (≈ Vizio)
AVPlayer (already ships) ─ AirPlay 2 TVs (Samsung · LG · Vizio · Sony · TCL · Roku TV)

Roku ──────────────────── full BrightScript/SceneGraph rewrite. Separate decision.
```

**Sequencing rationale.** Phase 1 (Cast + AirPlay) is days of work and is the
*only* realistic Vizio reach. Phase 2 (Android TV → Fire TV) is the biggest device
reach for ~100% engine reuse. Phase 3 (web-TV) reuses the PWA and needs no new
runtime. Roku is last because it is the only target with 0% code reuse.

---

## Phase 0 — Foundation (do first; unblocks everything)

| ID | Item | Who | Size | Status |
|---|---|---|---|---|
| **F1** | Land + correct `TV-PLATFORM-EXPANSION.md` on main | ENG | S | ✅ done |
| **F2** | `docs/TV-DESIGN.md` binding doc | ENG | M | ✅ done |
| **F3** | This backlog | ENG | S | ✅ done |
| **F4** | `DECISIONS.md` 047 — the TV expansion decision | ENG | S | ✅ done |
| **F5** | Add **Android TV** + **Web-TV** coverage to `PARITY.md` | ENG | S | ✅ done (§8b — a dedicated section, not 2 more columns on already-6-wide tables) |
| **F6** | Author project skills `androidtv-compose-focus` + `smarttv-web-app` | ENG | M | ✅ done |

**F5 note:** the existing tables are already six columns wide, so TV coverage
landed as a dedicated `PARITY.md` §8b (client table + verb table + a compliance-gate
line) rather than two more columns. Every non-✅ cell still carries a reason
(`cross-platform-parity-discipline`).

**F6 rationale:** no existing skill covers Compose for TV focus or Tizen/webOS
packaging. `android-production-gotchas` is phone-shaped; `web-platform-patterns`
is pointer-shaped. Per CLAUDE.md, patterns learned the hard way become skills
rather than being re-derived.

---

## Phase 1 — Zero-app reach: Cast + AirPlay

*Highest ROI in the whole backlog. No store, no review, no certification.*

| ID | Item | Who | Size | Deps |
|---|---|---|---|---|
| **C1** | Register in the Google Cast SDK Developer Console; pay the one-time **$5**; create an app ID | **OWNER** | S | — |
| **C2** | Build the **Custom Web Receiver** (CAF v3) page, hosted at `archivewatch.org/cast/` | ENG | M | C1 |
| **C3** | Cast **sender** in the web viewer (Cast SDK for Web) | ENG | M | C2 |
| **C4** | Cast **sender** in the Android phone app — **excluded from the Fire variant** | ENG | M | C2, A7 |
| **C5** | Register a physical Cast device for testing | **OWNER** | S | C1 |
| **A0** | Confirm + expose the **AirPlay** route in the iOS player | ENG | S | — |

**C2 notes.** The receiver is HTML/JS and reuses the PWA player, including the
`captions[]` → `<track>` conversion and the resilient reconnect. It is hosted
static — it fits the existing GitHub Pages model exactly. Receiver v2 is
deprecated; build **CAF v3**.

**C4 warning.** Cast is **GMS-dependent**. It must be compiled out of the Fire TV
variant or the Fire build breaks (`TV-DESIGN §6.6`). This is the single
cross-cutting constraint between Phase 1 and Phase 2.

**A0 notes.** `AVPlayer` already exposes AirPlay with no entitlement and no fee.
This is verify-and-document, not build. It reaches Apple TV plus AirPlay-2 TVs
from Samsung, LG, Vizio, Sony, TCL, Hisense, Roku TV and Philips — but only in
Apple households, so it is reach, not discovery.

**Phase 1 acceptance:** a film plays on a Chromecast-built-in TV from both the
web viewer and the Android phone app, with captions selectable and resume
written back; AirPlay route confirmed on a real iPhone.

---

## Phase 2 — Android TV → Google TV, then Fire TV

*~100% engine reuse. The work is a 10-foot UI, not a port.*

### 2a — Platform compliance

| ID | Item | Who | Size | Acceptance |
|---|---|---|---|---|
| **A1** ✅ | `LEANBACK_LAUNCHER` intent filter (TV-ML) | ENG | S | App appears in the Android TV launcher |
| **A2** ✅ | `touchscreen` + TV-absent hardware `required="false"` (TV-MT) | ENG | S | Play accepts the AAB for the TV form factor |
| **A3** ✅ | **320×180 banner containing the app name** + ≥160×160 xhdpi icon (TV-LB/TV-BN) | ENG | S | Banner renders in the launcher; name legible |
| **A4** ✅ | Landscape, no letterboxing, 5% overscan insets (TV-LO/TV-OV) | ENG | S | Nothing clipped on a real panel |
| **A5** ✅ | **TV-G6 audit: 64-bit + 16 KB page size** across `sqlite-bundled`, Media3, Coil | ENG | M | Every bundled `.so` is 16 KB-aligned; **live requirement since 2026-08-01** |
| **A6** ✅ | Confirm TV-PS (`minSdk` ≤ 31 — currently 29) and TV-G1 (AAB) | ENG | S | Both already satisfied; assert in CI |

**A5 is the sleeper risk.** It went live two days before this backlog was
written, it is not automatically satisfied, and it blocks the TV form factor.
Do it early — the fix may be a dependency bump, which has lead time.

### 2b — The 10-foot UI (the real work)

| ID | Item | Who | Size | Deps |
|---|---|---|---|---|
| **A7** ✅ | Add `androidx.tv:tv-material` **1.1.0**; runtime TV branch via `UiModeManager` (TV-DESIGN §6.5) | ENG | S | — |
| **A8** ✅ | Focus primitives: focusable card with scale+ring+lift, initial-focus claim, row/grid containers on standard `LazyRow`/`LazyColumn` | ENG | M | A7 |
| **A9** ✅ | TV **Home** — hero + editorial rows + category/decade rows | ENG | M | A8 |
| **A10** | TV **Browse/Movies** + **TV Shows** grids with facets | ENG | M | A8 |
| **A11** | TV **Detail** — hero, metadata, Play/Favorite, More Like This | ENG | M | A8 |
| **A12** | TV **Search** — D-pad-operable, with the no-typing browse escape (TV-DESIGN §3.6) | ENG | M | A8 |
| **A13** | TV **Library** + **Settings** | ENG | S | A8 |
| **A14** ✅ | TV **Player**: Media3 `PlayerView` TV controls, D-pad center/left/right (TV-PC), `KEYCODE_MEDIA_PLAY_PAUSE` (TV-PP), title+description overlay (Decision 037) | ENG | M | A8 |
| **A15** ✅ | **⚠️ Gate `media3-session` MediaSession OFF on TV; pause video on switch-away (TV-NP)** | ENG | S | A14 |
| **A16** ✅ | Back returns to launcher from root, never mid-playback (TV-DB) | ENG | S | A8 |
| **A17** | Subtitles via Media3 `SubtitleConfiguration` from `captions[]` | ENG | S | A14 |
| **A18** | v1.1 surfaces: Channels · Surprise · Collections (TV-DESIGN §2) | ENG | L | A9 |

**A15 is a shipped-code conflict, not a new feature.** The MediaSession added for
phone lock-screen controls in the 2026-06-13 parity wave violates TV-NP for a
video app. It must be gated by device type.

**Skill:** invoke `androidtv-compose-focus` (F6) plus `android-production-gotchas`
for the data-layer/`produceState` discipline, which is unchanged on TV.

### 2c — Ship

| ID | Item | Who | Size |
|---|---|---|---|
| **A19** | Emulator verification (Android TV emulator image) on every surface | ENG | M | ⚠️ **BLOCKED on this machine** — `system-images;android-36;android-tv;arm64-v8a` + a `tv_1080p` AVD are installed, but QEMU hangs before opening its console ports. Root cause: **~9 GB free disk**. Freeing space should unblock it. |
| **A20** | **Buy an Android TV / Google TV device** for real-remote QA | **OWNER** | S |
| **A21** | Play Console → *Setup › Advanced settings › Form factors › Add Android TV*; accept the TV policy | **OWNER** | S |
| **A22** | TV screenshots (≥1, up to 8) + TV banner upload + "Android TV" in the description | **OWNER** (assets by ENG) | S |
| **A23** | Submit; pass the **separate Android TV app-quality review** | **OWNER** | S |

### 2d — Fire TV

| ID | Item | Who | Size | Notes |
|---|---|---|---|---|
| **A24** ✅ | Fire variant: **exclude Cast/any GMS**; re-assert zero-GMS in CI | ENG | S | Dependency set is already GMS-free — keep it that way |
| **A25** | Validate Media3 1.9.4 progressive-MP4 playback on **real Fire hardware** | ENG+OWNER | M | Do **not** adopt the stale `amzn` ExoPlayer port |
| **A26** | **Buy a Fire TV Stick (~$30)** | **OWNER** | S | Amazon expects physical-device QA |
| **A27** | **Create a free Amazon Developer account** | **OWNER** | S | $0 registration, $0 submission |
| **A28** | Submit to the Amazon Appstore (APK/AAB + assets + Fire TV form factors) | **OWNER** | S | Review ≈ 3–5 business days |

**Phase 2 acceptance:** the same AAB installs and is fully D-pad-operable on an
Android TV device and a Fire TV Stick; both pass the §9 remote/ten-foot/parity
tests; phone build is byte-for-byte unaffected in behavior.

---

## Phase 3 — Web-TV → LG webOS, then Samsung Tizen

*Reuses the PWA. The work is an input layer, not a rewrite.*

### 3a — Shared TV layer

| ID | Item | Who | Size | Notes |
|---|---|---|---|---|
| **W1** ✅ | Vanilla **spatial-navigation focus engine** (~200 lines): registry, nearest-in-direction resolver, roving `tabindex`, `scrollIntoView`, single `keydown` | ENG | M | Norigin et al. are React-only → out (TV-DESIGN §7.1) |
| **W2** ✅ | Register/unregister focusables on `showView()` — same lifecycle discipline as the IntersectionObservers | ENG | S | |
| **W3** ✅ | TV CSS breakpoint: 1920×1080, 5% overscan insets, 24px body floor, dark-first | ENG | M | Additive to the mobile-first CSS |
| **W4** ✅ | Player key contract: center=play/pause, L/R=seek, media keys; overlay syncs with controls | ENG | M | |
| **W5** | Subtitles: SRT→WebVTT client-side → `<track>` | ENG | S | Already the web viewer's model |
| **W6** ✅ | Lifecycle: pause on suspend/blur; resume state | ENG | S | |
| **W7** ✅ | Bump the service-worker shell version | ENG | S | Or TVs serve a stale app for days |

### 3b — LG webOS *(first: individuals can publish globally)*

| ID | Item | Who | Size | Notes |
|---|---|---|---|---|
| **L1** ✅ | `appinfo.json`; `ares-package` → `.ipk` | ENG | S | Verify the current CLI version at install time — sources disagree (1.12.x vs 3.2.x) |
| **L2** ✅ | webOS shim: Back = keyCode **461**; `webOSLaunch`/`webOSRelaunch` | ENG | S | |
| **L3** | **Magic Remote pointer coexistence** with D-pad focus | ENG | M | Not optional (TV-DESIGN §7.4) |
| **L4** | **Create a free LG Seller Lounge account** (individual, 18+, global OK) | **OWNER** | S | |
| **L5** | **Create an LG Developer account + enable Developer Mode on an LG TV**; side-load the `.ipk` | **OWNER** | S | Requires access to an LG TV |
| **L6** | Store assets: **1280×720** screenshots, description, content rating | ENG assets / **OWNER** upload | S | |
| **L7** | **UX scenario doc + the mandatory self-checklist** | ENG drafts / **OWNER** submits | M | Missing or thin self-checklist = automatic rejection |
| **L8** | Submit; pretest + function test + content test | **OWNER** | S | ≈ 5–10 business days, often 2–3 cycles |

### 3c — Samsung Tizen

| ID | Item | Who | Size | Notes |
|---|---|---|---|---|
| **S1** ✅ | `config.xml`; `tizen build-web` + `tizen package` → signed `.wgt` | ENG | S | **Keep the signing certificate — updates must reuse it** |
| **S2** ✅ | Tizen shim: `tizen.tvinputdevice.registerKey()` for media keys; `tizenhwkey` Back; `visibilitychange` pause | ENG | S | |
| **S3** | **Create a free TV Seller Office account** | **OWNER** | S | |
| **S4** | **Decide: US-only Public Seller, or sign an offline contract with Samsung HQ for Partner (global)** | **OWNER** | — | Business decision, not engineering |
| **S5** | Enable Developer Mode on a Samsung TV (keyed to the TV's IP); side-load | **OWNER** | S | Requires access to a Samsung TV |
| **S6** | Submit; Samsung manual QA against the Launch/Development checklists | **OWNER** | S | ≈ 1–2 weeks, multi-cycle rejections common |

### 3d — Aggregators (opportunistic)

| ID | Item | Who | Size | Notes |
|---|---|---|---|---|
| **G1** | Inquire with **Titan OS** partner portal (all Philips TVs from 2026; strong in Europe) | **OWNER** | S | Closest thing to self-serve HTML5 onboarding; cost not published |
| **G2** | Inquire with **VIDAA/Hisense** (~40M devices) and **Zeasn/Foxxum** | **OWNER** | S | Same HTML5 build; no public indie door found (2026-08) |

**Phase 3 acceptance:** one shared web build runs fully D-pad-operable on an LG
TV and a Samsung TV, differing only in the shim files; the phone/desktop web
viewer is unaffected.

---

## Phase 4 — Roku (separate funded decision; NOT started)

**0% code reuse.** BrightScript + SceneGraph is a proprietary stack with no
Swift/Kotlin/JS runtime and no general WebView app model. Industry consensus is
**~2–4 months for one experienced Roku developer**, more when learning
BrightScript cold. Roku's no-code Direct Publisher was sunset in January 2024,
and its feed ceiling never fit a 40k-item catalog anyway.

**The case for it:** Roku is **#1 in US CTV** (~37–38% of devices, ~44% of CTV
viewing hours, 100M+ global active households) and skews toward exactly the
value-seeking free-content viewer Archive Watch is for. It is the highest-reach
platform we are not on. Fees are **$0**.

**Known blockers to price in before committing:**

- **R-a — Deep linking is mandatory** for public video apps, and feeds Roku
  Search. Real, non-trivial new work.
- **R-b — Performance thresholds:** home fully rendered **within 15s**, content
  playing **within 8s**. ⚠️ The archive.org `/download` 302-redirect latency
  (~0.5–1.0s TTFB measured on Apple) is the most likely certification friction
  point. **Measure this on real Roku hardware before committing budget.**
- **R-c — Playback resilience regression.** Roku's `Video` node **owns
  networking**; there is no `AVAssetResourceLoaderDelegate` equivalent, so
  Decisions 021/031/034 (byte-range resume, node failover) **cannot be
  reproduced**. Mitigate by preferring HLS/DASH derivatives where available.
  This is a genuine quality regression and must be an accepted trade-off, in
  writing, before starting.
- **R-d — Certification drifts.** Roku ships periodic certification updates
  (a Spring 2026 update exists). Read the live checklist at submission time.

**Not blockers:** Roku Pay does not apply (free, no login), and the new
2026-10-01 Continue Watching / Instant Resume mandates apply only above
5M hours/month (US) — far above us.

**Recommendation:** do not start Roku until Phases 1–3 ship and R-b has been
measured on hardware. Then log it as its own decision with a budget.

---

## Not pursued (with reasons)

| Platform | Why not |
|---|---|
| **Vizio SmartCast** | No public self-serve program or open SDK; onboarding is BD-gated through Vizio-designated partners and requires credentials Vizio issues. Post-Walmart it is an ad-monetization vehicle — a free, no-ads PD app is strategically uninteresting to them. **Reach it via Cast + AirPlay instead.** |
| **Comcast/Sky (RDK/Firebolt)** | Public SDK, but distribution is partner/certification-gated. Build-possible, ship-unlikely for a solo free app. |
| **TiVo OS (Xperi)** | HTML5, but no public self-serve indie program surfaced. |

---

## §OWNER — everything only Ben can do

Grouped by when it is needed. Nothing here is blocked on engineering unless noted.

### Accounts & fees (total cash outlay: **$5** + hardware)

| # | Action | Cost | Needed for |
|---|---|---|---|
| O1 | Register in the **Google Cast SDK Developer Console**, pay the one-time **$5**, create an app ID | **$5** | Cast (C1) |
| O2 | Play Console → *Setup › Advanced settings › Form factors › **Add Android TV***; accept the TV policy | $0 (same $25 account) | Google TV (A21) |
| O3 | Create a free **Amazon Developer account** | $0 | Fire TV (A27) |
| O4 | Create a free **LG Seller Lounge account** (individual, 18+) + a separate **LG Developer account** for Developer Mode | $0 | webOS (L4, L5) |
| O5 | Create a free **Samsung TV Seller Office account** | $0 | Tizen (S3) |

### Blocked right now — free up disk

| # | Action | Why |
|---|---|---|
| **O0** | **Free disk space on the dev Mac** (~9 GB free at 2026-08-03) | The Android TV emulator (A19) cannot boot — QEMU hangs before opening its console ports. This is the same disk-pressure issue logged 2026-06-26. Everything else in Phase 2 is verified by build + static audit; the emulator pass needs room. |

### Hardware (certification expects physical devices — emulators do not satisfy)

| # | Action | Approx. cost |
|---|---|---|
| O6 | An **Android TV / Google TV** device | ~$30–100 |
| O7 | A **Fire TV Stick** | ~$30 |
| O8 | Access to an **LG TV** (Developer Mode app from the LG Content Store) | — |
| O9 | Access to a **Samsung TV** (Developer Mode, keyed to the TV's IP) | — |
| O10 | A **Cast device** registered in the console for testing | — |
| O11 | *(Roku only, if pursued)* a Roku device | ~$30–100 |

### Decisions only you can make

| # | Decision | Why it's yours |
|---|---|---|
| O12 | **Samsung: accept US-only distribution, or pursue Partner Seller?** Partner requires signing an offline contract with Samsung HQ or a local subsidiary — i.e. a business entity. | Business/legal, not technical |
| O13 | **Fund Roku?** ~2–4 months of work, 0% reuse, for the largest US CTV audience — with an accepted playback-resilience regression (R-c). | Budget + risk acceptance |
| O14 | **Aggregator inquiries** (Titan OS, VIDAA, Zeasn/Foxxum) — pricing is unpublished; these are partnership conversations. | Requires you to negotiate |

### Submission steps (per store, when the build is ready)

| # | Store | Steps |
|---|---|---|
| O15 | **Google Play (TV)** | Add the TV form factor, upload the TV banner + ≥1 TV screenshot, mention "Android TV" in the description, submit for the **separate TV app-quality review** |
| O16 | **Amazon Appstore** | Upload APK/AAB + assets, target Fire TV form factors, submit (≈3–5 business days) |
| O17 | **LG Seller Lounge** | Upload `.ipk`, 1280×720 screenshots, description, rating, **UX scenario + self-checklist** (mandatory — thin submissions are auto-rejected), submit (≈5–10 business days) |
| O18 | **Samsung Seller Office** | Upload the signed `.wgt` (**keep the certificate for future updates**), metadata, rating, submit to manual QA (≈1–2 weeks) |

### Standing rights obligation (applies to every platform)

**O19 — The rights-audit exclusions (Decisions 027 / 044) must stay enforced.** A
reviewer spot-checking a famous copyrighted title on the home screen is a
rejection *and takedown* risk on every one of these stores, exactly as on Apple.
The nightly `publish-db` enforcement is what keeps this true — do not let it
drift into report-only mode again.

---

## Skill map

| Work | Skill to invoke |
|---|---|
| Any TV surface | `docs/TV-DESIGN.md` first, then the below |
| Android TV focus/UI | **`androidtv-compose-focus`** (to author, F6) + `android-production-gotchas` |
| Web-TV focus/packaging | **`smarttv-web-app`** (to author, F6) + `web-platform-patterns` |
| Any custom component | `native-platform-first` — exhaust the platform first |
| Layout/type/density | `mobile-first-density-design` |
| Loading/empty/error/offline on every new row + grid | `universal-feature-states` |
| Playback resilience per platform | `resilient-media-streaming` |
| Data layer for a new client | `shared-data-plane-contract` + `docs/CATALOG-CONTRACT.md` |
| Parity bookkeeping | `cross-platform-parity-discipline` |
| Before implementing any feature | `learning-orientation-design` |
| New view/row/overlay proposals | `binding-design-doc-discipline` |
| Play submission | `play-cli-submission` + `store-submission-playbook` |
| Logging a decision | `architectural-decision-log` / `/decision` |
