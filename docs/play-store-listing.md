# Google Play Console — Archive Watch (Android)

Paste-ready listing copy + the full first-time setup walkthrough. Unlike the
iOS addition (which rode the existing ASC app record), Play starts from zero:
developer account → app record → store listing → testing track → production.

## Assets (prepared, outside the repo — upload material, regenerable)

    ~/Desktop/ArchiveWatch-PlayStore-Assets/
        icon-512.png                   — 512×512 app icon (required; from the
                                         photographic 1902 icon — the ONLY
                                         brand icon; the old SVGs are deleted)
        feature-graphic-1024x500.png   — feature graphic (required)
        phone/                         — 8 Pixel 9 Pro shots, 1280×2856:
                                         Home, Channels EPG, His Girl Friday,
                                         The Invisible Man (1933), Four Star
                                         Playhouse (series), Surprise,
                                         Superman: Electric Earthquake, Browse
        tablet-7/                      — 6 shots, 1200×1920 (Tablet_7 AVD):
                                         Home, Channels, Invisible Man, Four
                                         Star Playhouse, Superman, Browse
        tablet-10/                     — same 6, 1600×2560 (Tablet_10 AVD)
        ArchiveWatch-1.2.24.aab        — signed release App Bundle (upload this)

Tablet AVDs were cloned from the Pixel 9 Pro config (no cmdline-tools on this
box) — gotcha: the copied config.ini carries `skin.name`/`skin.path`, and the
SKIN overrides hw.lcd.* (first boot came up 1280×2856); set
`skin.name=<W>x<H>` + delete hardware-qemu.ini before booting. On tablet
widths the app shows the nav RAIL (left), so the Browse shot is a rail tap,
not a bottom-bar tap.

Screenshot regeneration: deep links drive navigation —
`adb shell am start -a android.intent.action.VIEW -d "archivewatch://item/{id}" com.archivewatch.app`
(also `://channels`, `://surprise`, `https://archivewatch.org/series/{slug}`).
Use archiveIDs that exist in the LIVE full DB (the IMDb dedup drops duplicate
copies — seed-only ids spin; check with the catalog-db release asset).

## Identifiers / basics
- Package `com.archivewatch.app` · versionName **1.2.24** · versionCode 1
- minSdk 29 (Android 10) · targetSdk 36
- Upload key: `~/keystores/archivewatch-upload.jks` (creds in
  `~/.gradle/gradle.properties` — NEVER in git)
- **Price: Free** · no ads, no IAP (Decision 010)
- Category: **Entertainment** · Tags: Movies & Video

---

## ⚠️ One-time gotcha: personal accounts need 12 testers

If the Play developer account is a **personal** account created after
Nov 2023, Google requires a closed test with **12 testers opted-in for 14
continuous days** before you can apply for production access. An
**organization** account has no such requirement. Plan accordingly:
- Personal: expect ~2–3 weeks of closed testing before the public listing.
- Organization (needs a D-U-N-S number): production access immediately.

---

## Step-by-step walkthrough

### 1. Developer account (owner, one-time)
1. https://play.google.com/console → sign in with the Google account you want
   to own the app long-term.
2. Choose account type (see gotcha above), pay the **$25 one-time** fee,
   complete identity verification (can take a day or two).

### 2. Create the app
1. Play Console → **Create app**.
2. Name `Archive Watch` · Default language English (US) · **App** ·
   **Free** · accept declarations.

### 3. Set up the app (the "Set up your app" dashboard checklist)
All of these are required before any release goes live:

- **Privacy policy**: `https://archivewatch.org/privacy.html`
- **App access**: "All functionality is available without special access" —
  no login required (Sign in with Google/Drive sync is NOT in this build).
- **Ads**: No, the app contains no ads.
- **Content rating**: fill the IARC questionnaire (see section below).
- **Target audience**: 13+ (do NOT select under-13 — archival content is
  unrated; selecting children triggers the Families policy). "App not
  designed for children."
- **News app**: No.
- **Data safety**: see the exact answers below.
- **Government app**: No.
- **Financial features**: None.
- **Health**: None.

### 4. Store listing (Grow → Store presence → Main store listing)
Paste from the "Listing copy" section below + upload:
- App icon: `icon-512.png`
- Feature graphic: `feature-graphic-1024x500.png`
- Phone screenshots: everything in `phone/` (order as numbered)
- 7"/10" tablet screenshots: upload from `tablet-7/` and `tablet-10/`
  (the Console required them for this listing).

### 5. Play App Signing + first upload
1. Release → **Testing → Internal testing** → Create release.
2. Accept **Play App Signing** (Google generates and holds the production
   signing key; our `.jks` becomes the UPLOAD key — exactly what the
   build.gradle comment anticipates).
3. Upload `ArchiveWatch-1.2.24.aab`, name the release `1.2.24 (1)`, add the
   release notes below, roll out to internal testing.
4. Add your own Google account as an internal tester (Testers tab → create an
   email list), install via the opt-in link on a real device, spot-check:
   browse, play a title, Channels tune-in, resume.

### 6. ⚠️ After enrolling in Play App Signing: fix App Links
Play App Signing means the PRODUCTION cert differs from our upload key, so
`https://archivewatch.org/.well-known/assetlinks.json` must gain the Play
cert or `archivewatch.org/item/...` links won't open the app:
1. Play Console → Setup → **App signing** → copy the **App signing key
   certificate** SHA-256.
2. Add it to the `sha256_cert_fingerprints` array in `assetlinks.json` in
   this repo (keep the upload + debug prints) and push — Pages serves it.

### 7. Production
- Personal account: run the 12-tester closed test first (promote the internal
  release to **Closed testing**, recruit 12 testers, wait 14 days, then apply
  for production in the dashboard).
- Then Release → **Production** → promote the release → choose countries
  (all) → roll out. First production review typically takes a few days.

---

## Listing copy (paste-ready)

### App name (≤30)
`Archive Watch`

### Short description (≤80)
`Classic films, old TV, and live retro channels — free from the public domain.`

### Full description (≤4000)
```
Archive Watch turns the Internet Archive's vast public-domain moving-image
collection into a cinematheque you can carry — feature films, classic
television, silent cinema, animation, newsreels, and the strange, wonderful
world of vintage commercials and ephemeral film.

Every title is presented with the care of a great repertory house: real
posters, cast, synopses, and genres, so a 1920s silent and a 1950s sci-fi
B-movie look as considered as anything on a modern streaming service.

LIVE CHANNELS — A REAL TV GUIDE
• A programmed channel guide, laid out like a true TV listing: see what's on
  now and next, scroll the broadcast day
• Tune in and it plays straight through, one title rolling into the next
• Vintage public-domain commercials play between programs — the retro-TV feel
• Build your own channel from any mix of type and era

A REPERTORY HOUSE, NOT A FEED
• Hand-curated shelves alongside the most-watched titles from the Archive
• Browse by decade, genre, and collection
• Classic TV with real series, seasons, and episodes — binge straight through
• Tap any cast or crew name to wander their filmography
• Surprise Me and Cartoon Mode — for when you'd rather be delighted than decide

MADE FOR ANDROID
• Modern Material Design 3, built with Jetpack Compose
• Media3 playback hardened against slow archival servers
• Now Playing controls on the lock screen and in Quick Settings
• Playlists, favorites, resume across launches
• App shortcuts: long-press the icon to jump straight to Surprise or Channels

FREE, AND RESPECTFUL OF YOU
• No subscription, no in-app purchases, no ads
• No account, no sign-in — just watch
• No tracking, no analytics — nothing about you is collected or shared

All content is sourced from the public domain via the Internet Archive.
Metadata and artwork come from TMDb, Wikidata, Wikimedia Commons, and the
Library of Congress. This product uses the TMDB API but is not endorsed or
certified by TMDB.

If you'd rather wander a well-stocked repertory cinema than doomscroll a
recommendation feed, Archive Watch is for you.
```

### Release notes (internal/closed/production, ≤500)
```
Archive Watch arrives on Android — a cinematheque for the Internet Archive:

• Live Channels: a real TV-listing guide — scroll the broadcast day, tune in,
  and it just plays (vintage commercials included).
• 30,000+ public-domain films, classic TV series with real seasons and
  episodes, silent cinema, animation, and newsreels — with real posters and
  cast.
• Playlists, favorites, resume, Cartoon Mode, Surprise Me.
• Free. No ads, no account, no tracking.
```

---

## Data safety form (exact answers)

- **Does your app collect or share any of the required user data types?**
  → **No.**
  (No backend, no analytics, no ads SDKs, no crash reporting SDK. All user
  state — favorites, playlists, progress, custom channels — is in a local
  SQLite file. Network calls fetch public catalog/metadata/video from
  archive.org, GitHub Pages, TMDb image CDN; no user identifier is sent.
  Google Drive sync is NOT in this build — revisit this form when it ships.)
- **Is all of the user data collected by your app encrypted in transit?**
  → question is skipped when nothing is collected.
- **Do you provide a way for users to request that their data is deleted?**
  → skipped (nothing collected).
- Play may also ask about the **device or other IDs** type because of the
  `INTERNET` permission — the answer remains No (none are collected).

## Content rating (IARC questionnaire)
- Category: **Entertainment** (not user-generated content — the catalog is
  curator-controlled, the rights/adult filters are upstream).
- Violence: archival films can contain **infrequent mild violence**
  (e.g. Night of the Living Dead is in the catalog) → answer Yes to
  "infrequent/mild" fantasy/realistic violence depictions where asked.
- Sexuality/nudity: No (mature collections are excluded by the upstream
  adult filter and there is NO client toggle on Android).
- Drugs/alcohol/tobacco: depictions possible in archival film → mild/infrequent.
- Gambling, profanity, user interaction, location sharing, purchases: No.
- Expected result: **Teen / PEGI 12-ish** — mirrors the ~12+ Apple rating.

## App content declarations quick sheet
| Question | Answer |
|---|---|
| Ads | No |
| In-app purchases | No |
| Target audience | 13+ |
| Designed for families | No |
| News app | No |
| COVID-19 app | No |
| Data safety | Nothing collected/shared |
| Government app | No |
| Login required | No |

---

## Build commands (reference)
```bash
cd android
JAVA_HOME=$(/usr/libexec/java_home) ./gradlew bundleRelease   # → app/build/outputs/bundle/release/app-release.aab
JAVA_HOME=$(/usr/libexec/java_home) ./gradlew assembleRelease # APK for emulator/device spot-checks
```
versionCode must increase on every Play upload (versionName is free-form and
tracks the Apple marketing version).

## Owner checklist (condensed)
1. Create/verify the Play developer account ($25; note the personal-account
   12-tester rule).
2. Create app → complete the "Set up your app" checklist (answers above).
3. Main store listing: paste copy, upload icon + feature graphic + phone
   screenshots.
4. Internal testing → accept Play App Signing → upload the AAB → test on
   device.
5. Add the Play App-Signing SHA-256 to assetlinks.json (repo) and push.
6. Closed test (if personal account) → Production rollout.
