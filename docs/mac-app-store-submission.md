# Mac App Store submission — Archive Watch for macOS

Paste-ready. The macOS app is a SEPARATE App Store Connect record from
tvOS/iOS because its bundle id differs (`app.archivewatch.macos` vs
`app.archivewatch.tvos`). It is the parity browse/play/library face PLUS the
Mac-exclusive **Creation Studio** multi-clip editor (Decision 042).

---

## Build state — VERIFIED review-ready (2026-06-24, 1.3.103 / 625)

Confirmed by archiving the `ArchiveWatchMac` scheme (Release) and inspecting the
signed app — nothing below is a guess:

- **Archive succeeds**, automatic signing resolved *"Mac Team Provisioning
  Profile: app.archivewatch.macos"* — the App ID is registered with all its
  capabilities.
- **Bundle id** `app.archivewatch.macos` · **Team** `L2G756LY8N` · **Min macOS** 26.0.
- **Version** `1.3.103` · **Build** `625` (from `AppVersion.xcconfig`).
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

### The ONE caveat before upload
The verification archive was built with **Xcode-beta**. App Store Connect rejects
builds made with a beta toolchain once the GM is out. **Archive + upload with the
RELEASE Xcode 26** (the same toolchain that shipped the approved tvOS 1.2.24 build).
Everything else is identical.

---

## Owner steps, in order

1. **App Store Connect → new app.** Apps → ➕ → New App → Platform **macOS** →
   Name `Archive Watch` → Primary language English (U.S.) → Bundle ID
   `app.archivewatch.macos` → SKU `archivewatch-macos`. (This is a distinct record
   from the tvOS/iOS app — different bundle id.)

2. **Confirm capabilities** on the App ID (already resolved by the archive, so this
   is a verification, not new work): iCloud + **CloudKit** (container
   `iCloud.app.archivewatch.tvos`), **App Groups** (`group.app.archivewatch.tvos`),
   **Sign in with Apple**, **Associated Domains**, **Push** (CloudKit uses it).
   CloudKit schema is already in **Production** (verified cross-device on tvOS/iOS,
   2026-06-11) — the Mac shares the same container, so no new deploy.

3. **Archive with release Xcode 26.** Open `ArchiveWatch/ArchiveWatch.xcodeproj`,
   scheme **ArchiveWatchMac**, Destination *Any Mac*, Product ▸ Archive. In the
   Organizer: **Distribute App → App Store Connect → Upload** (automatic signing
   re-signs with Apple Distribution + an App Store profile). Let it run validation;
   it should pass clean.

4. **Fill the listing** (copy below), **upload Mac screenshots** (specs below),
   select the build you just uploaded (HEAD is `1.3.104 (626)`), answer **App Privacy** = *Data Not Collected*
   (mirror tvOS — favorites/progress live in the user's own iCloud; nothing reaches
   us), encryption is already declared exempt.

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
1–10 per localization. Suggested set, in order:
1. Home — hero + curated shelves (the cinematheque)
2. A Detail page — poster, cast, synopsis (the "produced" look)
3. Channels — the live TV guide
4. **Creation Studio editor** — timeline with clips + program monitor (the hook)
5. **Text → Supercut** sheet mid-compose (the differentiator)
6. Export / Publish to the Internet Archive

Capture with the real release build, window at the chosen size, no debug overlays
(don't set `AW_CS_*` env vars). `⌘⇧4` then Space to grab a window, or
`screencapture -o -w shot.png`.

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

- **Separate ASC record by design.** If the owner later wants one unified app
  record, the Mac would need to adopt the `app.archivewatch.tvos` bundle id (a
  bigger change). The current `app.archivewatch.macos` ships as its own Mac app —
  the simplest path, and what the archive already signs.
- **Min macOS 26.0 is deliberate** (Liquid Glass + the macOS-26 SpeechAnalyzer the
  supercut uses). High floor, but consistent with the tvOS/iOS 26 stance.
- **TMDB_BEARER_TOKEN** is injected from `Secrets.xcconfig` at build time (gitignored)
  — make sure it's present in the release build environment, as for tvOS/iOS.
