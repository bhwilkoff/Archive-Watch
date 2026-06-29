# Mac App Store submission — Archive Watch for macOS

Paste-ready. The macOS app ships **inside the existing "Archive Watch" App Store
Connect record** as the macOS platform — it shares the bundle id
`app.archivewatch.tvos` with the already-approved tvOS + iOS apps (the same way
iOS was added as a second platform to the tvOS record). One record, three
platforms. It is the parity browse/play/library face PLUS the Mac-exclusive
**Creation Studio** multi-clip editor (Decision 042).

---

## Build state — VERIFIED review-ready (2026-06-24, 1.3.104 / 626)

Confirmed by archiving the `ArchiveWatchMac` scheme (Release) and inspecting the
signed app — nothing below is a guess:

- **Archive succeeds**, automatic signing generated *"Mac Team Provisioning
  Profile: app.archivewatch.tvos"* — the SHARED App ID supports the macOS platform
  and carries all the capabilities (iCloud/CloudKit, App Groups, Sign in with
  Apple, Associated Domains).
- **Bundle id** `app.archivewatch.tvos` (shared with tvOS + iOS → same ASC record)
  · **Team** `L2G756LY8N` · **Min macOS** 26.0.
- **Version** `1.3.104` · **Build** `626` (from `AppVersion.xcconfig`). Build
  numbers are per-platform in a multiplatform record, so macOS 626 is the first
  macOS build regardless of the tvOS/iOS history.
- **App Sandbox ON** (required for the Mac App Store) with exactly the scopes the
  app uses: `network.client` (archive.org / TMDb / CloudKit), `files.user-selected.read-write`
  (import a music bed, export MP4 / save `.archiveproj`), CloudKit + iCloud
  container `iCloud.app.archivewatch.tvos`, App Group `group.app.archivewatch.tvos`,
  Sign in with Apple, Associated Domains (`archivewatch.org`).
- **Hardened Runtime ON**; signed `-o runtime`.
- **App icon**: full macOS set (16→1024, `AppIcon.icns` in the bundle).
- **Privacy manifest** `PrivacyInfo.xcprivacy` bundled (Data Not Collected).
- **`LSApplicationCategoryType`** = `public.app-category.entertainment`.
- **`ITSAppUsesNonExemptEncryption`** = `false` (HTTPS only — exempt).
- **No runtime subprocess / ffmpeg** — the whole engine is native AVFoundation
  (cache-then-export, two-pass grade→overlay), so nothing trips the sandbox.
  `NSMicrophoneUsageDescription` is present for the voiceover recorder (audio stays
  on device — never transmitted).

---

## Build pathway — getting an APPROVABLE build when you only have Xcode beta

This is the load-bearing part. The dev machine currently has **only Xcode 27 beta**
(Swift 6.4, macOS 27 SDK). That matters because:

> **The rule (Apple, confirmed 2026):** you MAY upload a beta-Xcode / beta-SDK build to
> **TestFlight** (internal + external testing), but you may **NOT submit it for App Store
> review**. App Review requires a build made with a **released** Xcode (or the latest
> **Release Candidate**) and its **released SDK**. A beta-toolchain build is rejected at
> submission. Apple also requires the *current* released SDK within a few months of each OS
> release, so always use the newest GA Xcode, not an old one.

### Step 0 (DONE, 2026-06-28) — make the app COMPILE on the released SDK
A bare `if #available(macOS 27, *)` is NOT enough: the macOS-27 symbols the app calls
(`AVVideoComposition(applyingFiltersTo:applier:)` + `AVCIImageFilteringResult` in
`Looks_macOS.swift`; `pixelBufferAndDisplayTime(forItemTime:)` in `PlaybackFreezeGuard.swift`)
exist ONLY in the macOS 27 SDK, so a released Xcode 26 (macOS 26 SDK) would fail to *compile*
them — not just gate them at runtime. Both sites are now wrapped in **`#if compiler(>=6.4)`**
(= "the Xcode 27 / Swift 6.4 toolchain"), with the deprecated-but-functional macOS 26 API in
the `#else`. Result:
- **Xcode 27 beta** (Swift 6.4) → compiles the new API, warning-free (unchanged dev experience).
- **Xcode 26 GA** (Swift < 6.4) → compiles the macOS 26 API → **archives + submits cleanly**.
- This ALSO unblocks tvOS/iOS GA builds (`PlaybackFreezeGuard` is shared across all targets).

No further code change is needed when Xcode 27 goes GA — `#if compiler` automatically picks
the new API once the GA toolchain is Swift 6.4.

### Step 1 — install the released Xcode 26 ALONGSIDE the beta
Two Xcodes coexist fine. Get the **latest released Xcode 26.x** (NOT a beta):
- Mac App Store ("Xcode"), OR
- <https://developer.apple.com/download/all/> → search "Xcode 26" → the build WITHOUT
  "beta" in the name (a Release Candidate is also accepted for submission).
- Install to `/Applications/Xcode.app` (keep the beta at `/Applications/Xcode-beta.app`).
- First launch: let it install additional components; accept the license.

### Step 2 — point the toolchain at the RELEASED Xcode for the archive
Per-command (recommended — leaves your beta default intact):
```
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```
…or globally `sudo xcode-select -s /Applications/Xcode.app` (revert later with
`-s /Applications/Xcode-beta.app`). In the GUI it's simply whichever Xcode you opened.

**Verify it is GA, not beta** before archiving — this is the whole point:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version            # → Xcode 26.x (NOT 27)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift --version                # → Swift < 6.4
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -showsdks | grep macOS   # → macOS 26.x
```
If `swift --version` says 6.4 or the SDK says macOS 27, you're still on the beta — fix
`DEVELOPER_DIR` before continuing.

### Step 3 — archive + upload with the released Xcode
GUI: open `ArchiveWatch/ArchiveWatch.xcodeproj` in **/Applications/Xcode.app**, scheme
**Archive Watch Mac**, Destination **Any Mac**, **Product ▸ Archive** → Organizer →
**Distribute App ▸ App Store Connect ▸ Upload** (keep automatic signing ON). Or headless:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ArchiveWatch/ArchiveWatch.xcodeproj \
  -scheme "Archive Watch Mac" -configuration Release -destination 'generic/platform=macOS' \
  -archivePath build/ArchiveWatchMac.xcarchive archive -allowProvisioningUpdates
# then Organizer ▸ Distribute, or xcodebuild -exportArchive + xcrun notarytool/altool to upload.
```
Bump BOTH numbers in `AppVersion.xcconfig` first — every upload must be a new build number.

### Interim: ship to TESTERS today without the GA Xcode
You can get the app into real hands NOW with the beta build: archive with the beta and
**Distribute ▸ TestFlight Internal Only** (no review). External TestFlight needs a one-time
Beta App Review but still accepts beta-built builds. Fastest feedback loop while you install
Xcode 26 for the actual store submission.

### Alternative: Xcode Cloud (no second local Xcode at all)
Xcode Cloud builds on Apple's runners with a Xcode you pick — choose the **latest released**
Xcode 26 (not "Latest Beta"). With Step 0's `#if compiler` guard the project compiles there
and the workflow can archive + deliver to TestFlight/App Store, sidestepping a local GA Xcode
entirely. (Decision 002's repo-root `.xcodeproj` requirement is already satisfied.)

---

## Owner steps, in order

1. **No new app record.** The macOS build uploads into the EXISTING "Archive
   Watch" record because it shares the bundle id `app.archivewatch.tvos`. App Store
   Connect makes the **macOS platform** available on the record once the first
   macOS build is uploaded (step 3) — the same flow used to add iOS to the tvOS
   record. (Capabilities are inherited from the shared App ID — iCloud/CloudKit,
   App Groups, Sign in with Apple, Associated Domains, Push — nothing to register.
   CloudKit schema is already in **Production**, verified cross-device 2026-06-11;
   the Mac shares the same container.)

2. **First-time Mac signing.** No Mac provisioning profile existed for the shared
   App ID until this work generated one. In Xcode, keep **Automatically manage
   signing** ON for the `ArchiveWatchMac` target (Team `L2G756LY8N`); the first
   archive creates the Mac App Store distribution profile automatically. (On the
   command line this is `-allowProvisioningUpdates`, already exercised here.)

3. **Archive with release Xcode 26.** Open `ArchiveWatch/ArchiveWatch.xcodeproj`,
   scheme **ArchiveWatchMac**, Destination *Any Mac*, Product ▸ Archive. In the
   Organizer: **Distribute App → App Store Connect → Upload** (automatic signing
   re-signs with Apple Distribution + an App Store profile). Let it run validation;
   it should pass clean. After upload, the macOS platform appears in the "Archive
   Watch" record.

4. **Fill the macOS listing.** In the "Archive Watch" record, create a new **macOS**
   version matching the build you uploaded (`1.3.105`), paste the copy below,
   **upload Mac screenshots** (specs below),
   select the build you just uploaded (HEAD is `1.3.105 (627)`). App Privacy is
   shared across platforms (already *Data Not Collected* — favorites/progress live
   in the user's own iCloud; nothing reaches us); encryption is already declared
   exempt. (Name, category, and URLs are app-level/shared; description, screenshots,
   keywords, promo, and What's New are per-platform — use the macOS copy below.)

5. **Submit for review.** Add the review notes below so the reviewer can exercise
   Creation Studio and understands the public-domain content + attribution.

---

## Listing copy (paste-ready)

**Name (≤30):** `Archive Watch`

**Subtitle (≤30):** `Watch & edit public-domain film`

**Promotional Text (≤170):**
`A cinematheque for the Mac — wander a vast public-domain film collection, then
clip and recut it in Creation Studio, the Mac-only multi-clip editor.`

**Keywords (≤100):**
`public domain,classic movies,silent film,video editor,clip,supercut,cinema,documentary,free movies,film noir`

**Description (≤4000):**
```
Archive Watch turns the Internet Archive's vast public-domain moving-image
collection into a cinematheque you can wander from your Mac — feature films,
classic television, silent cinema, animation, newsreels, and the strange,
wonderful world of vintage commercials and ephemeral film. Every title is
presented with the care of a great repertory house: real posters, cast,
synopses, and genres, so a 1920s silent and a 1950s sci-fi B-movie look as
considered as anything on a modern streaming service.

And because it's the Mac, Archive Watch doesn't stop at watching.

CREATION STUDIO — MAKE SOMETHING (Mac only)
- A real multi-clip timeline editor that composes clips across different
  archive.org titles into one new film
- Text to Supercut: type a line and the catalog speaks it back to you,
  word by word, assembled from the films themselves
- Color looks, cross-dissolve and wipe/push transitions, speed, music beds,
  and recorded voiceover
- Export a finished MP4, or publish straight back to the Internet Archive
- Everything is non-destructive and every export can carry an automatic
  public-domain provenance credit

A REPERTORY HOUSE, NOT A FEED
- Hand-curated shelves alongside the most-watched titles from the Archive
- Browse by decade, genre, and collection; full-text search
- Classic TV with real series, seasons, and episodes
- Surprise Me — for when you'd rather be delighted than decide

YOURS, EVERYWHERE
- Favorites, playlists, and watch progress sync across your Apple devices
  through your own iCloud — no account with us, ever
- No ads, no subscription, no tracking. The content is public domain and free,
  and so is the app.

Archive Watch is a labor of love for the Internet Archive. Video is streamed
from and hosted by archive.org. Metadata and artwork are sourced from TMDB and
other open references. This product uses the TMDB API but is not endorsed or
certified by TMDB.
```

**What's New (≤4000):**
```
First release for the Mac. The full Archive Watch cinematheque — browse, search,
Channels, and play — plus Creation Studio, a Mac-exclusive multi-clip editor that
turns public-domain film into supercuts and fan edits you can export or publish
back to the Internet Archive.
```

**Category:** Primary **Entertainment** · Secondary **Photo & Video** (the editor)

**Copyright:** `© 2026 Ben Wilkoff` (covers the app only; public-domain content is
not owned — no URL, no "All Rights Reserved")

**URLs** (already live):
- Privacy Policy: `https://archivewatch.org/privacy.html`
- Support: `https://archivewatch.org/support.html`
- Marketing: `https://archivewatch.org/`

---

## Mac screenshots

Required size — pick ONE and use it for every shot (16:10):
**1280×800**, 1440×900, 2560×1600, or **2880×1800** (Retina, recommended).
Exact rule (Apple, confirmed 2026): macOS screenshots must be **16:10** and EXACTLY one of
those four pixel sizes; 1–10 per localization; `.png`/`.jpg`. Use **2880×1800** (Retina) for
all of them. Suggested set, in order (lead with the differentiator that justifies the
"Photo & Video" secondary category):
1. **Creation Studio editor** — timeline with clips + program monitor (the hook; Mac-only)
2. **Text → Supercut** sheet mid-compose (the differentiator)
3. Home — hero + curated shelves (the cinematheque)
4. A Detail page — poster, cast, synopsis (the "produced" look)
5. Channels — the live TV guide
6. Export / Publish to the Internet Archive

**Capture with the script** `tools/mac-screenshots.sh` (frames the frontmost window onto a
brand canvas at the EXACT required size — a raw window grab is never exactly 2880×1800):
```
# Run the RELEASE build, navigate to a screen, then (no AW_CS_*/AW_START_* env vars):
tools/mac-screenshots.sh 01-studio        # → ~/Desktop/ArchiveWatch-Mac-Screenshots/01-studio.png
# repeat: 02-supercut, 03-home, 04-detail, 05-channels, 06-export
```
One-time: grant **Screen Recording** permission to your terminal/Xcode (System Settings ▸
Privacy & Security ▸ Screen Recording) or the grab is blank. Manual fallback: `⌘⇧4` then
Space grabs a window, then run the file through the script's Pillow framing, or size the
window to a 16:10 and crop to exact dims. Screenshots may come from ANY build (they don't
have to be the submitted binary) — so you can capture from today's beta build now.

---

## App Review notes (paste into "Notes")

```
Archive Watch streams public-domain films hosted by the Internet Archive
(archive.org). No login is required to browse, search, or play. Sign in with
Apple is optional and only enables syncing your own favorites/playlists/progress
through your private iCloud (CloudKit) — no data is collected by us.

CREATION STUDIO (Mac-exclusive editor): open the app, choose any title with a
"Create"/Creation Studio affordance, mark an in/out point to add a clip, then use
the timeline to trim, add transitions, or use Text to Supercut. Export writes a
local MP4 (you'll be asked where to save). All editing is on-device with
AVFoundation; the app never runs external processes. The microphone permission is
only for recording an optional voiceover, which stays on device.

Only public-domain / Creative-Commons titles are made available for clipping
(rights-gated). Exports can include an automatic "archivewatch.org · Public
Domain" credit. This product uses the TMDB API but is not endorsed or certified
by TMDB; attribution is shown in Settings.
```

---

## Notes / open

- **One shared record (owner decision 2026-06-24).** The Mac adopted the
  `app.archivewatch.tvos` bundle id so all three platforms live in one App Store
  Connect record — simpler to manage. Verified: the shared App ID supports macOS
  (Xcode generated a Mac App Store profile for it) and every entitlement resolves.
  The `app.archivewatch.tvos` id literally contains "tvos" but that's just an
  opaque identifier — invisible to users, and it's the id the approved app already
  owns (a store bundle id can't be changed once shipped).
- **Min macOS 26.0 is deliberate** (Liquid Glass + the macOS-26 SpeechAnalyzer the
  supercut uses). High floor, but consistent with the tvOS/iOS 26 stance.
- **TMDB_BEARER_TOKEN** is injected from `Secrets.xcconfig` at build time (gitignored)
  — make sure it's present in the release build environment, as for tvOS/iOS.
