<p align="center">
  <img src="assets/app-icon/app-icon.png" alt="Archive Watch" width="300">
</p>

<h1 align="center">Archive Watch</h1>

<p align="center">
  A cinematheque for the living room — the Internet Archive's public-domain
  moving-image collection, presented with the care of a great repertory house.
</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/archive-watch/id6776697407"><b>App Store</b> (Apple TV · iPhone · iPad · Mac)</a>
  &nbsp;·&nbsp;
  <a href="https://play.google.com/store/apps/details?id=com.archivewatch.app"><b>Google Play</b> (Android · Google TV)</a>
  &nbsp;·&nbsp;
  <a href="https://www.amazon.com/gp/mas/dl/android?p=com.archivewatch.app"><b>Amazon Appstore</b> (Fire TV)</a>
  &nbsp;·&nbsp;
  <a href="https://channelstore.roku.com/details/12a571a872732e40fe8d1d6c59f3849f:5ec8f46dcec2324229c8d096ea23c089/archive-watch"><b>Roku Channel Store</b></a>
  &nbsp;·&nbsp;
  <a href="https://archivewatch.org/"><b>Web</b></a>
</p>

---

**Archive Watch** turns the Internet Archive's vast public-domain library —
feature films, classic TV, silent cinema, animation, newsreels, and vintage
commercials — into a beautiful, focus-driven browsing and viewing experience.
Archival titles are enriched with posters, cast, synopses, and genres from TMDb
(with Wikidata, Wikimedia Commons, TVmaze, and the Library of Congress as
fallbacks), so a 1920s silent looks as considered as anything on a modern
streaming service.

The app is **free**, has **no ads, no subscriptions, and requires no account**,
and collects no personal data. It's built for the curious viewer who'd rather
wander a well-stocked repertory cinema than doomscroll a recommendation feed.

- **Platforms:** Apple TV (the original and primary platform, tvOS 17+, built
  against tvOS 26 / Liquid Glass), iPhone, iPad, Mac, Android, Google TV,
  Fire TV, Roku, and the web at [archivewatch.org](https://archivewatch.org/).
  Every platform is a native app over the SAME catalog (Decision 028); a Samsung
  TV build is submitted and an LG build is packaged.
- **Catalog:** ~32,000 visible public-domain titles, enriched, rights-audited
  and curated; ~26,700 in the public web index

## Features

- **Home** — a hero carousel plus curated and popularity-driven shelves
- **Live Channels** — a programmed, deterministic TV-guide grid (what's on now /
  next); tune in and it plays straight through, with vintage public-domain
  **commercials between programs** for the 1990s-broadcast feel
- **Movies / TV Shows / Collections** — browse by type, decade, genre, and
  curated collection; TV is a canonical series → season → episode spine
- **Search** — full-text search with type and era filters; Siri Remote
  dictation on Apple TV; **Roku Search** lists the pre-1930 films in the
  Roku home menu's own search and deep links into the channel
- **Surprise Me** — a dozen ways to wander (random film, decade, Public Domain
  Day, Cartoon Mode, Party Play, the cover-art screensaver, and more)
- **Library** — Favorites, playlists, and watch history, synced through your
  own cloud: **Sign in with Apple** (iCloud) on the Apple apps, **Sign in with
  Google** (Drive App Data) on Android, and **both** on the web — the one
  client that can merge the two (Decisions 022, 028, 102)
- **Watch Together** — SharePlay on Apple TV, iPhone, iPad and Mac
- **Offline** — download a film to iPhone, iPad or Mac and watch it on a plane
- **Captions** — published subtitles where they exist, live on-device
  captioning on Apple platforms where they don't
- **Clip Studio** (phones) and **Creation Studio** (Mac) — cut, caption and
  share public-domain clips, GIFs and supercuts
- **Resilient playback** — a custom streaming loader that survives Archive.org
  connection resets without buffer-flushing stalls, at full quality
- **Mature content off by default, everywhere** — one predicate decides it for
  every platform; the web and Roku, which have no setting, read an index that
  already IS the default-off state (Decision 105)

## Repository layout

```
/                                  ← repo root
├── ArchiveWatch/
│   └── ArchiveWatch.xcodeproj      ← the Apple apps (Swift 6 · SwiftUI · SwiftData):
│       └── ArchiveWatch/             tvOS, iOS, iPadOS, macOS from one project
├── android/                       ← Android · Google TV · Fire TV (Kotlin · Compose · Media3)
├── roku/                          ← the Roku channel (BrightScript · SceneGraph)
├── index.html, watch.js/.css     ← archivewatch.org — the web viewer (GitHub Pages root)
├── tv/, tv.js, tv.css             ← the web viewer's TV layer (Samsung Tizen · LG webOS)
├── cast/                          ← Chromecast receiver
├── curate/, css/, js/             ← public "Suggest & Curate" editorial tool (archivewatch.org/curate/)
├── pulse/                         ← the owner's dashboard (archivewatch.org/pulse/, unlisted)
├── featured.json                  ← curated home shelves + categories (editorial source)
├── catalog-index.json, details/   ← the web + Roku data plane (index + 256 detail shards)
├── series/*.json                  ← canonical TV spines (TVmaze-derived)
├── ops/                           ← measured state the pipeline keeps (image sizes, store facts, Pulse)
├── tools/                         ← Python content pipeline (discover, ingest, enrich, audit, build)
├── .github/workflows/             ← scheduled discovery / enrichment / DB publish / Pages deploy / store submission
├── docs/                          ← binding design docs per platform, decisions, runbooks, playbooks
├── AppVersion.xcconfig            ← single source of truth for version + build
└── Secrets.xcconfig               ← gitignored; TMDB_BEARER_TOKEN and other keys
```

The full `catalog.json` (~140 MB) and the prebuilt `catalog.sqlite` are **not in
git** — they're generated accumulators hosted as rolling **GitHub Release**
assets (`catalog-source`, `catalog-db`). The apps download the compressed
SQLite, cache it, and query it on-device; the web viewer and the Roku channel
read the committed `catalog-index.json` and `details/` shards. Generated
site content (share pages, the Roku Search feed, cover images) is built into
the Pages artifact at deploy time and never committed. See
`docs/CATALOG-CONTRACT.md` and Decisions 017–020, 029.

## Build & run

**Apple** (requires Xcode 26):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
echo 'TMDB_BEARER_TOKEN = <your v4 bearer token>' > Secrets.xcconfig   # optional
xcodebuild -project ArchiveWatch/ArchiveWatch.xcodeproj \
  -scheme ArchiveWatch -configuration Debug \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build
```

Version/build numbers live only in `AppVersion.xcconfig` (never the Xcode
identity panel — Decision 003). Store builds are made in CI: Apple by
`appstore-build.yml` + `appstore-submit.yml` (Decision 101), Play by
`play-release.yml` (Decision 110).

**Android**: `cd android && ./gradlew assembleGoogleDebug` (or `assembleAmazonDebug`
for Fire TV). **Roku**: `python tools/roku.py` sideloads to a developer-mode
device; `tools/roku_package.py` builds the store package. **Web**:
`python3 -m http.server 8080` from the repo root.

Real devices, never emulators, are the verification bar — `docs/DEVICE-TESTING.md`.

## The content pipeline

The catalog grows and self-heals automatically via scheduled GitHub Actions
(`.github/workflows/`): discovery (Wikidata public-domain feeds, Archive
collections, Library of Congress, TVmaze TV spines, a title-first public-domain
wants list), ingestion of playable derivatives, enrichment (TMDb / OMDb / TVDb /
Commons / Wikipedia), data-quality remediation, a **rights audit** that hides
anything not evidenced public domain behind a reversible flag (Decision 027),
byte-level playability verification, subtitle sourcing, and publishing the
apps' SQLite database plus the web index. The pipeline is stateful and
merge-guarded so a rebuild can never shrink or clobber the catalog (Decision
020), and a daily auditor names any workflow that went green while producing
nothing (Decisions 090, 107).

`archivewatch.org/pulse/` reads every channel the project has to its users —
store states, reviews, downloads, the social programme, mentions — and says so
when a reader cannot read rather than printing a zero (Decision 108).

## The Roku Search feed

`tools/build_roku_search_feed.py` publishes `archivewatch.org/roku-search/feed.json`
so Roku's own search lists the catalog's films and deep links into the channel.
It carries only films that are **public domain by age (pre-1930) with a designed
poster** — the owner's bar for what is advertised to a third party — and
everything Roku's validator taught us is encoded and tested: it follows no
redirect, accepts only 2:3 or 16:9 images, refuses anything under a minute or
before 1900, and counts lengths in UTF-16 units. `docs/ROKU-SUBMISSION.md`
carries the dashboard steps and every measurement; Decision 113 the rationale.

## The editorial web tool

The site root (https://archivewatch.org) is the **Archive Watch web viewer**; the public **Suggest & Curate** editorial tool lives at https://archivewatch.org/curate/ :

- **Anyone** can suggest a public-domain title to add (it emails the curator).
- The **curator** arranges the app's home-screen shelves and searches the full
  catalog to include titles, then emails / commits the updated `featured.json`.

Run it locally with `python3 -m http.server` from the repo root, or visit the
hosted version. Privacy, terms and support pages are served from the same site.

## Tech & conventions

- Apple: Swift 6, SwiftUI (`@Observable`, `@FocusState`, `TabView(.sidebarAdaptable)`),
  SwiftData, AVKit — **no third-party Swift packages**
- Android: Kotlin, Jetpack Compose (+ Compose for TV), bundled SQLite with
  FTS5, Media3
- Roku: BrightScript + SceneGraph; web: vanilla JS, no framework, no build step
- All networking through shared clients; never a raw request from a view
- Read-only on-device SQLite (FTS5) as the catalog source of truth
- Every platform has a binding design doc in `docs/` (`tvOS-DESIGN.md`,
  `iOS-DESIGN.md`, `IPAD-DESIGN.md`, `macOS-DESIGN.md`, `ANDROID-DESIGN.md`,
  `TV-DESIGN.md`, `ROKU-DESIGN.md`, `WEB-DESIGN.md`) and a parity ledger
  (`PARITY.md`); architecture rationale lives in `DECISIONS.md` and its
  archives; the ten engineering disciplines in `docs/ENGINEERING-PROCESS.md`

## Credits & attribution

Content is public domain via the [Internet Archive](https://archive.org).
Metadata and artwork from [TMDb](https://www.themoviedb.org) (this product uses
the TMDb API but is not endorsed or certified by TMDb), OMDb, TheTVDB, Wikidata,
Wikimedia Commons, TVmaze, and the Library of Congress. Archive Watch is a free,
non-commercial labor of love; the only suggested support is a
[donation to the Internet Archive](https://archive.org/donate).
