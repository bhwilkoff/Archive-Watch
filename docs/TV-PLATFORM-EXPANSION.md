# Smart-TV Platform Expansion — Viability & Process

**Status:** Research complete + re-verified. Strategy is now committed as
**Decision 047**; the binding UI rules live in `docs/TV-DESIGN.md` and the
ordered work list in `docs/TV-PLATFORM-BACKLOG.md`.
**Date:** 2026-08-02, re-verified against live vendor docs 2026-08-03.
**Scope:** Getting Archive Watch onto the smart-TV / streaming-device app stores
beyond Apple: Roku, Samsung (Tizen), LG (webOS), Vizio (SmartCast),
Google TV / Android TV, Amazon Fire TV, plus the white-label OS aggregators and
the cast/AirPlay routes.

> Companion to `docs/MULTIPLATFORM-PLAN.md` (Decision 028, the iOS/Web/Android
> expansion) and `PARITY.md`. This doc extends the same "feature parity, native
> per platform, one shared data plane" thesis to the living-room TV stores that
> Decision 028 did not cover. Nothing here is committed as a decision yet; log
> a DECISIONS.md entry (`/decision`) before starting a platform.

---

## 2026-08-03 re-verification log — what changed since the first pass

Seven corrections from re-reading the live vendor docs. The strategy holds; four
of these are new hard requirements and one is a shipped-code conflict.

1. **`TvLazyRow` / `tv-foundation` no longer exist.** Their functionality moved
   into `compose-foundation` 1.7.0-beta02. Use the standard `LazyRow` /
   `LazyColumn` / `LazyVerticalGrid` and depend only on
   **`androidx.tv:tv-material` (1.1.0, 2026-07-30)**. Any tutorial showing
   `TvLazy*` or `rememberTvLazyListState` is stale.
2. **NEW — TV-G6 is live as of 2026-08-01:** TV apps must support 32-bit *and*
   64-bit architectures **and comply with 16 KB page sizes**. We ship native
   `.so`s via `sqlite-bundled`, Media3 and Coil, so this needs an actual
   verification pass — it is not automatically satisfied.
3. **NEW — TV-PS (since Dec 2025):** `minSdkVersion` must be **≤ 31**. Ours is
   **29 — already compliant.**
4. **NEW — TV-G1:** Android App Bundles are mandatory for TV. We already ship AAB.
5. **⚠️ TV-NP conflicts with shipped code.** The rule: *"Video apps must NOT use
   [Now Playing / background media] controls; video must pause when switching
   out."* Archive Watch shipped a `media3-session` `MediaSession` in the
   2026-06-13 parity wave for phone lock-screen controls. **That must be gated
   off on TV** or it is a quality-review failure.
6. **GMS audit — done, and the answer is the best case.** `libs.versions.toml`
   has **zero** Google Play Services / Firebase dependencies (OkHttp,
   kotlinx-serialization, Coil, Media3, androidx.sqlite only). The Fire TV port
   therefore carries **no GMS removal work**. The single rule to preserve: if
   Cast is added, it is GMS-dependent and must be excluded from the Fire variant.
7. **Roku's 2026 mandates don't reach us.** The new Continue Watching / Instant
   Resume requirements (effective 2026-10-01) apply only to apps streaming
   **>5M hours/month (US)** or **>1M (non-US)**. Deep linking + the performance
   thresholds still apply from day one.

Two smaller notes: **Norigin Spatial Navigation is React-only**, so it cannot be
used in our vanilla no-build web app — the focus engine is ours to write (small).
And Amazon now explicitly tells Fire OS 14+ developers to **move from ExoPlayer to
Media3**, which confirms the "don't adopt the stale `amzn` port" call below.

---

## TL;DR

The platforms split into **four technology families**, and Archive Watch's
existing codebases already cover two of them. Brand names matter less than the
runtime underneath.

| Platform | Runtime | Reuse vehicle | Code reuse | Platform fees | Verdict |
|---|---|---|---|---|---|
| **Google TV / Android TV** | Android TV OS | Kotlin/Compose/**Media3 app** (`android/`) | ~100% engine + new TV UI | $0 (same $25 acct) | **Do first** |
| **Amazon Fire TV** | Fire OS (Android fork) | Same TV build, minus Google Play Services | Same as above | **$0** | **Do second** |
| **Samsung Tizen** | HTML5 web | **Vanilla-JS web PWA** (site root) | ~70–80% + TV input layer | $0 | **Do third** |
| **LG webOS** | HTML5 web | **Vanilla-JS web PWA** | ~70–80% + TV input layer | $0 | **Do third (pair w/ Samsung)** |
| **Roku** | BrightScript + SceneGraph (proprietary) | **None — full rewrite** | 0% | $0 | High reach, high cost — separate decision |
| **Vizio SmartCast** | Curated/partner HTML5 | — (no open program) | n/a | n/a | **Not viable natively → reach via Cast** |

Two "free reach" routes that are **not app stores**:

- **Google Cast ($5 one-time):** add a Cast *sender* to the web + Android apps and
  host one HTML *receiver* page. Reaches Chromecast, Android TV/Google TV, **and
  Chromecast-built-in TVs — which includes most Vizio sets.** This is the de-facto
  Vizio path.
- **AirPlay (≈free, likely already working):** the existing iOS/tvOS `AVPlayer`
  already exposes an AirPlay route to Apple TV + AirPlay-2 TVs (Samsung, LG, Vizio,
  Sony, TCL, Hisense, Roku TV, Philips). No extra program or cost.

### Strategic shape: two builds unlock five of the seven native targets

- **Build #1 — one Android TV app → ships to BOTH Google TV/Android TV AND Fire TV.**
  The engine (SQLite catalog, HTTPS MP4, Media3) carries over ~100%; the real work
  is a 10-foot D-pad focus UI.
- **Build #2 — one shared Tizen+webOS web app → ships to BOTH Samsung AND LG.**
  Both are literally HTML5 web runtimes; the PWA is the right shape. The real work
  is a TV input/focus/layout layer.
- **Roku** stands alone (proprietary rewrite). **Vizio** has no open path (use Cast).

### Recommended order

1. **Google Cast ($5) + confirm AirPlay** — highest ROI, days of work, reuses
   existing code, and it is the only realistic Vizio reach.
2. **Android TV build → Google TV, then Fire TV** — biggest device reach, ~100%
   engine reuse, $0 incremental fees.
3. **Shared web build → LG webOS first, then Samsung** — reuses the PWA; LG first
   because Samsung is US-only without a business entity.
4. **Roku** — only if funding a multi-month BrightScript rewrite for the US's
   largest living-room audience is worthwhile. Genuinely a separate decision.

### Cross-cutting facts that apply everywhere

- Archive Watch's **no-login / no-ads / no-IAP** posture dramatically lightens
  every certification: no billing flow, no auth, minimal data-safety disclosures.
  (On Roku it removes the entire Roku Pay requirement; on Google/Amazon it makes
  the Data Safety form near-empty.)
- The **rights-audit exclusions (Decisions 027 / 044) must stay enforced.** A
  reviewer spot-checking a famous copyrighted title on the home screen is a
  rejection/removal risk on every platform, exactly as on Apple.
- **Physical test hardware is required or strongly expected** on every family: a
  Fire TV Stick (~$30), one Samsung + one LG TV in Developer Mode, a Roku device
  (~$30–100). Emulators/simulators exist but do not satisfy certification.
- The existing **WebVTT `captions[]` side-load model** (Decisions 039 / 043) is
  directly usable on every platform (HTML5 `<track>`, Media3 `SubtitleConfiguration`,
  Roku `Video` node WebVTT) and satisfies the "if captions are present, they must
  be user-selectable" rules.
- **Progressive H.264 MP4 over HTTPS plays natively everywhere** — no DRM, no
  re-encode. Note the one regression risk (Roku) below.

---

## Family 1 — Android-based (Google TV / Android TV, Amazon Fire TV)

**Reuse vehicle: the existing native Android app** (`android/`, Kotlin + Jetpack
Compose, Media3/ExoPlayer, package `app.archivewatch.android`). The data layer
(downloaded SQLite catalog, HTTPS networking, Media3 playback of progressive H.264
MP4) carries over essentially unchanged. The genuine work is a **10-foot D-pad
focus UI** — the phone touch layouts cannot ship as-is.

### Shared TV adaptation work (applies to both)

- **Leanback launcher intent filter** — a launcher activity declaring
  `android.intent.category.LEANBACK_LAUNCHER` (can sit on the same activity as
  the phone `LAUNCHER`). Without it the app is invisible on TV devices.
- **`<uses-feature android:name="android.hardware.touchscreen" android:required="false"/>`**
  — mandatory to qualify as a TV app.
- **`<uses-feature android:name="android.software.leanback" android:required="false"/>`**
  — `required="false"` keeps the *same* app shipping to phones/tablets too.
- **Home-screen banner** — `android:banner`, **320×180 px**, must contain the app
  name as text, localized.
- **Verify no permission implies required hardware** (camera/telephony) that would
  exclude TV; force landscape; overscan-safe margins.
- **TV UI + D-pad/focus (the real work)** — every function reachable by remote with
  visible focus states. Recommended path: **Compose for TV** — a natural fit since
  the app is already on Compose. Depend on **`androidx.tv:tv-material` only**
  (1.1.0); `tv-foundation` and the `TvLazy*` composables were removed once their
  behavior landed in `compose-foundation`, so lists/grids use the standard
  `LazyRow` / `LazyColumn`. This is a dedicated navigation/layout pass, not an
  engine port.
- **Playback key handling (TV-PC / TV-PP)** — D-pad center toggles play/pause,
  left/right seek, and `KEYCODE_MEDIA_PLAY_PAUSE` must toggle during playback.
- **⚠️ TV-NP** — a *video* app must **pause on switch-away** and must **not** put
  background media controls in the system UI. Gate the shipped `media3-session`
  `MediaSession` off for TV.
- **TV-G6 (live 2026-08-01)** — 64-bit + **16 KB page size** compliance across
  every bundled native library. Verify, don't assume.

**Reuse estimate:** data layer / SQLite / networking / Media3 playback ≈ 100%;
UI/navigation is the adaptation cost.

### Google TV / Android TV

- **Same runtime.** "Google TV" is the launcher/UI skin over Android TV OS; one
  TV-capable AAB serves both. Media3/ExoPlayer is the recommended playback stack.
- **Account & cost:** the **same Google Play Developer account and the same package
  name** — TV is added as another **form factor of the same listing**, not a new
  app. Cost is the one-time **$25** already paid. No TV surcharge.
- **Submit:** Play Console → *Setup > Advanced settings > Form factors > Add Android
  TV*, accept the TV review policy. Upload the AAB with TV support; add the TV
  banner; ≥1 Android TV screenshot (up to 8); mention "Android TV" in the
  description.
- **Review:** a **separate Android TV app-quality review** against the
  [TV app quality guidelines](https://developer.android.com/docs/quality-guidelines/tv-app-quality)
  (D-pad reachability, no dead-ends, playback/back behavior, banner,
  touchscreen-not-required), on top of standard Play policy review. No published
  SLA; expect longer than a mobile update (directionally days, occasionally 1–2
  weeks).
- **Reach:** Google's own metric — **~270M active devices (Sept 2024) → 300M
  (2025)**; largest smart-TV-OS ecosystem by device count. ("Active devices" mixes
  TVs, boxes, operator set-tops.)

### Amazon Fire TV

- **Fire OS is an Android fork**, so the existing APK/AAB most likely runs with
  little to no change; the same leanback/banner/touchscreen declarations make it
  Fire-friendly, and the Fire remote maps to standard Android D-pad events (the
  Android-TV focus work carries over directly).
- **The GMS risk — audited, and we are clean.** Any GMS dependency (Google sign-in,
  Maps, FCM, Play Billing, **Cast**) fails on Fire OS. `libs.versions.toml` shows
  **zero** Google Play Services / Firebase dependencies today, so there is nothing
  to strip. **The standing rule:** Cast is GMS-dependent — when the Cast sender
  lands, it must be excluded from the Fire variant (and any future Drive sync
  likewise).
- **Playback:** modern Media3 works on Fire TV for progressive HTTP MP4, and
  Amazon now explicitly directs **Fire OS 14+ developers to migrate from ExoPlayer
  to Media3**. **Do not adopt Amazon's old ExoPlayer port**
  (github.com/amzn/exoplayer-amazon-port — stale at ExoPlayer 2.18.7, pre-Media3,
  effectively unmaintained). **Device-test on real Fire hardware** (a ~$30 Fire TV
  Stick) — Amazon requires physical-device QA anyway.
- **Account & cost:** a **separate Amazon Developer account**, **$0** to register
  and **$0** to submit; no per-app fee.
- **Submit:** Amazon Developer Console → upload APK/AAB, icon/screenshots/
  description, target Fire TV form factors; pass Amazon's App Testing criteria.
  Optional deeper launcher/universal-search integration needs Amazon's catalog
  manifest (`com.amazon.device.REQUEST_CAPABILITIES`) — not required to publish.
- **Review:** roughly **3–5 business days** (not a contractual SLA).
- **Reach:** **250M+ Fire TV devices sold** (late 2024); active users ~50M
  (Amazon, 2022) to ~118M (third-party 2025 estimates). Treat ~50–120M active as
  the realistic reach. Consistently #1/#2 US CTV device platform with Roku.

### Suggested sequencing within the family

Build the TV UI/focus layer once (Compose for TV). Ship to **Google TV/Android TV
first** (same account/listing, biggest reach, and the quality review surfaces
10-foot-UI gaps), then repackage the same build for **Fire TV** (free) after the
GMS-dependency audit and on-device Media3 validation.

---

## Family 2 — Web-based (Samsung Tizen, LG webOS)

**Reuse vehicle: the existing vanilla HTML/JS/CSS web PWA** (site root; no
framework, no build step — see `docs/WEB-DESIGN.md`, Decision 030). Both platforms
are literally HTML5 web runtimes, so the PWA is the right shape. **Keep the HTML5
`<video>` element** — progressive H.264 MP4 over HTTPS is exactly its sweet spot;
neither Samsung AVPlay, nor a webOS media API, nor any DRM is needed for baseline
playback.

Catalog logic (client-side JS + the downloaded index/SQLite), networking, artwork,
and most view code port directly. **Reuse ≈ 70–80%.**

### Shared new work: a TV input / focus / layout layer

- **Remote-key handling** — arrows, Enter, Back/Return, media keys. (Samsung:
  `tizen.tvinputdevice.registerKey()` + keydown listeners. webOS: `keydown` incl.
  Back = keyCode 461, plus the Magic Remote **pointer/cursor** mode layered on top
  of the D-pad, so handle both pointer events and arrow-key focus.)
- **Focus / spatial navigation** — a PWA built for pointer/touch needs a focus
  engine (roving `tabindex`, a spatial-nav library, or manual management) so the
  D-pad moves between cards/shelves.
- **App lifecycle** — Back must exit or navigate back per policy; pause video on
  suspend. (Samsung `visibilitychange`/`tizenhwkey`; webOS `webOSLaunch`/
  `webOSRelaunch`.)
- **TV-safe layout** — 1920×1080 baseline, 10-ft legibility, overscan-safe margins;
  the mobile-first CSS needs a TV breakpoint.

Build this layer **once** and share it across Samsung + LG, with small per-platform
shims for key codes, lifecycle events, and packaging. A single Tizen+webOS build
is realistic if the app stays vanilla (skipping LG's optional Enact framework).

### Samsung — Tizen

- **Package:** `.wgt` widget (signed zip: `config.xml` + signature files), built via
  **Tizen Studio** or the **Tizen CLI** (`tizen build-web` / `tizen package`).
- **Account & cost:** **Samsung TV Seller Office account is free; no submission
  fee.**
- **⚠️ Biggest single constraint — the seller tier:**
  - **Public Seller** (default on signup) can **only launch apps in the US.**
  - **Partner Seller** can launch in any country but requires registering
    **business/company information** + Content Manager approval.
  - For a free solo/portfolio app, **US-only Public Seller may be acceptable**;
    **global distribution effectively requires a business entity.**
- **Submit & certify:** upload `.wgt` in Seller Office → metadata/screenshots/rating
  → Samsung **manual QA** against the Launch/Development checklists (mandatory
  features, Back-button behavior, playback, stability, policy). **Keep the signing
  certificate** — updates must reuse it.
- **Timeline:** ~1–2 weeks, variable (multi-week rejection loops reported).
- **Device test:** strongly expected — side-load the `.wgt` via the TV's Developer
  Mode (keyed to the TV's IP). No Samsung-issued test TV.
- **Reach:** Tizen is consistently the **#1/#2 smart-TV OS globally (~20% ± several
  points)**, on **200M+ TVs across ~190 countries.**

### LG — webOS

- **Package:** `.ipk`, built with the **webOS TV SDK / webOS CLI** (`ares-generate`,
  `ares-package`, `ares-install`/`ares-launch`/`ares-inspect`) or **webOS Studio**
  (VS Code extension) + the **webOS TV Simulator**. Current tooling (2025): SDK
  v10.x, CLI v3.2.0, Simulator v1.4.1; the old CLI/extension were deprecated in
  2024. LG's **Enact** (React-based) framework is **optional** — plain web apps are
  fully supported.
- **Account & cost:** **LG Seller Lounge account is free; no submission fee.**
  Individual sellers (18+) can register and **publish globally** — no company
  strictly required to start (friendlier than Samsung). A separate LG Developer
  account is needed for Developer Mode / device testing.
- **Submit & certify:** Seller Lounge → `.ipk` + metadata (screenshots **1280×720**,
  description, rating) → LG technical review = **pretest + function test + content
  test**, plus supporting docs (a **UX scenario** and a **self-checklist**).
- **Timeline:** ~5–10 business days, can repeat 2–3 cycles.
- **Device test:** **required** — install the "Developer Mode" app from the LG
  Content Store, enable dev mode, side-load the `.ipk`. No LG-issued test TV.
- **Reach:** webOS is **#2 globally — ~25% installed base / ~12% quarterly
  shipments (Q4 2024)**, on **130M+ TVs.** (Installed-base vs shipment-share are
  different metrics; both are cited.)

### Why LG first, then Samsung

LG lets an individual publish globally with less friction; Samsung's default tier
is US-only without a business entity. Build the shared web+focus layer, ship LG
webOS to validate it globally, then package the same app as a Samsung `.wgt`.

---

## Family 3 — Roku (proprietary; full rewrite)

**Reuse vehicle: none.** Roku runs a proprietary two-language stack —
**SceneGraph** (XML UI framework: scenes, nodes, the focus/remote model, the
`Video` node) + **BrightScript** (BASIC-like scripting for logic). There is no
Swift/Kotlin/Java runtime and no general WebView app model, so **none of the tvOS,
Android, macOS, or web code ports.** What carries over is *architecture and
backend design*, not code.

- **The no-code escape hatch is gone.** Roku's feed-based **Direct Publisher** was
  disabled for new channels **July 2023** and **sunset Jan 12, 2024**. Its legacy
  path also had a ~500 KB feed ceiling that never fit Archive Watch's 25k–40k-item
  catalog. Today "no-code" means paying a third-party OTT SaaS (Enveu, Uscreen,
  OTTEngine, etc. — recurring cost, you don't own the code, limited to their UI).
  The realistic path is a **custom SceneGraph/BrightScript channel** (optionally
  accelerated by **SGDEX** templates for stock list/grid/detail screens — won't
  cover bespoke surfaces like the Channels EPG, Surprise, faceted Browse).
- **Fees: $0.** No enrollment, annual, publishing, or listing fee. Roku doesn't
  host content (archive.org already does). Cost is a ~$30–100 test device +
  engineering time.
- **Process:** Roku account → enroll in developer program → sideload to a test
  device → automated pre-cert tests (Static Analysis + Channel Behavior) → create
  the listing → submit deep-link test params → Roku QA → rollout. First review
  ~24–48h; full cert ~3–5 business days; +1–2 days to appear. Roku advises
  submitting ~1 month ahead of a launch.
- **Certification specifics that bite here:**
  - **Deep linking is mandatory** for public video apps (and feeds **Roku Search**);
    real, non-trivial new work.
  - **Performance thresholds:** home screen fully rendered **within 15s**, content
    playing **within 8s** of initiation. ⚠️ The archive.org `/download` 302-redirect
    latency (~0.5–1.0s TTFB measured on Apple) is the most likely cert friction
    point — **measure early.**
  - **Roku Pay does NOT apply** (free, no login) — removes billing/auth/trial
    certification burden entirely.
  - Captions: Roku's `Video` node supports **WebVTT** + 608/708, so the existing
    WebVTT captions satisfy the "if present, must be selectable" rule.
- **⚠️ Playback regression risk:** Roku's `Video` node **owns networking** — there
  is no equivalent of `ResilientStreamLoader` (Decisions 021/031/034). The custom
  byte-range resilience and node-failover cannot be reproduced; mitigate by
  preferring HLS/DASH derivatives where available (Roku documents these as the
  "preferred" formats), else accept `Video`-node defaults on progressive MP4.
- **Effort:** industry consensus **~2–4 months** for one experienced Roku dev
  (longer learning BrightScript cold), driven up by the large data plane, faceted
  Browse + FTS Search, TV drill-in, Channels EPG, Surprise, resume, deep linking +
  Roku Search, and ongoing maintenance as Roku revises certification.
- **The case for it — reach.** Roku is **#1 US CTV: ~37–38% of devices, ~44% of CTV
  viewing hours** (Pixalate Q1 2025), **100M+ global active households**, and skews
  toward exactly the value-seeking "free content" viewer Archive Watch targets. It
  is the highest-reach platform Archive Watch is not yet on.
- **⚠️ Verify before committing:** Roku ships periodic certification updates
  (a Spring 2026 update exists); read the live checklist on developer.roku.com /
  docs.roku.com directly, as criteria change.

---

## Family 4 — Closed / curated & the cast routes (Vizio, aggregators, Cast, AirPlay)

### Vizio SmartCast — effectively closed to independent devs

- **No public self-serve developer program or open SDK.** Apps are hosted HTML5,
  but onboarding is **business-development / content-partnership driven**, routed
  through Vizio-designated "preferred development partners" (e.g. Cinedigm
  Matchpoint). App submission needs a **username/password Vizio issues during
  registration** — you cannot just sign up and ship. Documented dev APIs lean toward
  account/subscription monetization (built for commercial streamers).
- **Post-Walmart (acquisition closed Dec 2024, ~$2.3B):** Vizio is primarily an
  **ad-monetization vehicle** (Walmart Connect). Gatekeeping is likely to get more
  commercial/ad-aligned, not more open — a free, no-ads PD app is strategically
  uninteresting to them.
- **Realistic path: not a native Vizio app.** SmartCast carries **Chromecast built-in
  and AirPlay 2**, so reach Vizio TVs via **Google Cast** (below) + AirPlay without
  Vizio's approval. The existing code helps for the *Cast* route, not a native app —
  the blocker there is access/approval, not code.

### Google Cast / Chromecast — the pragmatic winner

- **Fully open to independent devs.** Register in the **Google Cast SDK Developer
  Console**, pay a **one-time, non-refundable $5**, register the app for an
  application ID, and point it at a hosted **HTML5 "Custom Web Receiver"** page (fits
  the existing static-hosting model perfectly). Publishing is self-serve — no BD
  gate.
- **Reach:** Chromecast dongles, **Android TV / Google TV, and Chromecast-built-in
  TVs (many Vizio + others)** — no per-platform native TV app required.
- **Code reuse:** the receiver is HTML/JS (reuse the PWA player); *sender* SDKs bolt
  onto the existing **web + Android** apps. (iOS Cast sender paths are more limited;
  Web + Android senders are solid.) ⚠️ Cast depends on Google Play Services, so the
  sender is **not** available in the Fire TV build (consistent with the Family-1
  GMS note).

### AirPlay — likely already working

- **AirPlay 2 is a public API**; standard `AVPlayer` playback in the existing
  **iOS/tvOS** apps exposes an AirPlay route with no special entitlement, reaching
  Apple TV + AirPlay-2 TVs (Samsung, LG, Sony, Vizio, TCL, Hisense, Roku TV,
  Philips). Near-zero effort — **confirm/expose the route**; it is not a discovery
  channel of its own (Apple-household TVs only).

### VIDAA (Hisense) — same web build, no self-serve door

- **HTML5 runtime** (standard HTML5/CSS/JS plus some VIDAA proprietary system
  APIs), so the **Family-2 web build + focus layer covers it technically** — the
  Norigin ecosystem lists VIDAA alongside Tizen and webOS as a target.
- **~40M+ connected devices** globally, projected toward ~8% global TV-OS share by
  2029 — a real audience, and Hisense/Toshiba volume is growing.
- **No public self-serve developer program surfaced** (2026-08). Onboarding appears
  partnership-driven, like Vizio. Treat as **"the build is free, the door is
  closed"** — worth a partner inquiry once the web-TV build exists and can be
  demoed, not worth pre-building for.

### White-label OS aggregators — the most indie-accessible native TV OSes

- **Titan OS** (all Philips TVs from 2026, JVC, others; strong in Europe) — a
  **Partner Portal** where you create an account, submit a hosted HTML5 test URL +
  assets, and pass an intake + QA (~2–4 weeks). Existing HTML5 apps mostly need
  remote-key mapping + User-Agent work. Closest thing to self-serve HTML5 onboarding
  among TV OSes. **Cost not published (flag).**
- **Zeasn / Whale OS + Foxxum** (Zeasn acquired Foxxum 2023) — HTML5 app-store
  **aggregators** syndicated across many mid-tier TV brands; onboarding via their
  partner portal, historically open to smaller apps. Cost/terms not clearly public.
- The PWA is directly reusable for all of these (same hosted-HTML5 model; main work
  = remote keys, UA strings, TV-safe focus/layout — the same Family-2 layer).

### Operator / partner-gated (not worth solo pursuit)

- **Comcast/Sky (RDK):** public **Firebolt SDK** (JS/OpenRPC, HTML5, optional
  Lightning) across Xfinity X1/Flex, Sky Glass/Q — but **distribution is
  partner/certification-gated**, not a self-serve store. Build-possible,
  ship-unlikely for a solo free app.
- **TiVo OS (Xperi):** HTML5, but no public self-serve indie program surfaced;
  onboarding appears partnership-driven.

---

## Open questions / to verify before committing to any platform

- **Roku Spring-2026 certification criteria** — read the live checklist directly;
  criteria change and the automated fetch was blocked during research.
- **Roku 8-second play-start rule vs. archive.org redirect latency** — needs a real
  on-device measurement; most likely cert friction point.
- ~~**Fire TV GMS-dependency audit**~~ — **DONE 2026-08-03: zero GMS deps.** What
  remains is validating Media3 on real Fire hardware, and keeping Cast out of the
  Fire variant when it lands.
- **Samsung global distribution** — decide whether US-only Public Seller is
  acceptable, or whether to sign an offline contract with Samsung HQ / a local
  subsidiary for Partner status. **Confirmed 2026-08-03:** Public Seller = US
  launch only; Partner requires that signed contract plus a system request. This
  is an owner business decision, not an engineering one.
- **TV-G6 16 KB page-size compliance** — verify every bundled native library
  (`sqlite-bundled`, Media3, Coil) is 16 KB-aligned. Live requirement since
  2026-08-01; unverified.
- **VIDAA / Titan OS / Zeasn onboarding** — all run the same HTML5 build, none has
  a documented self-serve indie door. Inquire once the web-TV build is demoable.
- **Aggregator pricing** (Titan OS / Zeasn / Foxxum) — not publicly documented; get
  quotes if a native aggregator presence is wanted.
- Whether TV parity should be tracked in `PARITY.md` (Decision 028) once a platform
  is actually started, and which TV surfaces are in-scope vs. deferred per platform.

---

## Source notes

Compiled 2026-08-02 from official developer documentation and reputable
2024–2026 industry reporting across four parallel research passes (Roku;
Samsung + LG; Google TV + Fire TV; Vizio + cast/aggregator routes). Market-share
figures vary by source and by metric (installed base vs. quarterly shipments vs.
vendor "active device" counts) and are given as ranges, not false precision. Key
official references:

- **Google TV / Fire TV:** developer.android.com/tv (Create a TV app, TV
  checklists, TV app quality, Distribute to Android TV); developer.amazon.com
  (Fire TV submission, differences-from-Android-TV, app porting, media players).
- **Samsung / LG:** developer.samsung.com/smarttv + TV Seller Office (develop,
  AVPlay, membership, launch checklist); webostv.developer.lge.com (CLI guide, app
  ecosystem, Developer Mode app).
- **Roku:** developer.roku.com (SceneGraph/BrightScript overview, certification
  criteria + testing, deep linking, closed caption, media/streaming specs, channel
  publishing guide); Direct Publisher sunset notices.
- **Cast / Vizio / aggregators:** developers.google.com/cast (registration, custom
  web receiver); Vizio Preferred Developer Program + content-partner pages; Walmart
  acquisition release; Titan OS / Zeasn / Foxxum partner-portal write-ups.
- **Market share:** Pixalate Q1 2025 CTV device report; smart-TV OS statistics
  aggregators (Amra & Elma, ElectroIQ); Google/Amazon device-count announcements.
