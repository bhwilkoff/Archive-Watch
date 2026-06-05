<p align="center">
  <img src="assets/app-icon/app-icon.png" alt="Archive Watch" width="300">
</p>

<h1 align="center">Archive Watch</h1>

<p align="center">
  A cinematheque for Apple&nbsp;TV — the Internet Archive's public-domain
  moving-image collection, presented with the care of a great repertory house.
</p>

---

**Archive Watch** turns the Internet Archive's vast public-domain library —
feature films, classic TV, silent cinema, animation, newsreels, and vintage
commercials — into a beautiful, focus-driven tvOS browsing and viewing
experience. Archival titles are enriched with posters, cast, synopses, and
genres from TMDb (with Wikidata, Wikimedia Commons, TVmaze, and the Library of
Congress as fallbacks), so a 1920s silent looks as considered as anything on a
modern streaming service.

The app is **free**, has **no ads, no subscriptions, and requires no account**,
and collects no personal data. It's built for the curious viewer who'd rather
wander a well-stocked repertory cinema than doomscroll a recommendation feed.

- **Primary platform:** tvOS 17+ (built against **tvOS 26 / Liquid Glass**)
- **Status:** in TestFlight; preparing for App Store submission
- **Catalog:** ~37,000 public-domain titles, enriched and curated

## Features

- **Home** — a hero carousel plus curated and popularity-driven shelves
- **Live Channels** — a programmed, deterministic TV-guide grid (what's on now /
  next); tune in and it plays straight through, with vintage public-domain
  **commercials between programs** for the 1990s-broadcast feel
- **Movies / TV Shows / Collections** — browse by type, decade, genre, and
  curated collection; TV is a canonical series → season → episode spine
- **Search** — Siri Remote keyboard + dictation, live results
- **Surprise Me** — a dozen ways to wander (random film, decade, Public Domain
  Day, Cartoon Mode, Party Play, the cover-art screensaver, and more)
- **Library** — Favorites, playlists, and watch history; optional **Sign in with
  Apple** syncs them across a household's Apple TVs via your own iCloud
- **Resilient playback** — a custom streaming loader that survives Archive.org
  connection resets without buffer-flushing stalls, at full quality

## Repository layout

```
/                                  ← repo root
├── ArchiveWatch/
│   └── ArchiveWatch.xcodeproj      ← the tvOS app (Swift 6 · SwiftUI · SwiftData)
│       └── ArchiveWatch/           ← App / Models / Views / Components /
│                                     Networking / Services / Store / Resources
├── index.html, css/, js/          ← public "Suggest & Curate" web tool (GitHub Pages)
├── whats-new.html                 ← recent-uploads ticker
├── privacy.html, support.html     ← App Store-required pages (hosted on Pages)
├── featured.json                  ← curated home shelves + categories (editorial source)
├── catalog-index.json             ← slim search index for the web tool
├── series/*.json                  ← canonical TV spines (TVmaze-derived)
├── tools/                         ← Python content pipeline (discover, ingest, enrich, build)
├── .github/workflows/             ← scheduled catalog discovery / enrichment / DB publish
├── docs/                          ← research, decisions, runbooks, the tvOS playbook
├── AppVersion.xcconfig            ← single source of truth for version + build
└── Secrets.xcconfig               ← gitignored; TMDB_BEARER_TOKEN
```

The full `catalog.json` (~90 MB) and the prebuilt `catalog.sqlite` are **not in
git** — they're generated accumulators hosted as rolling **GitHub Release**
assets (`catalog-source`, `catalog-db`). The app downloads the compressed SQLite,
caches it, and queries it on-device. See `docs/architecture/` and DECISIONS
017–020.

## Build & run (tvOS)

Requires Xcode 26 (tvOS 26 SDK).

```bash
# Point xcrun at Xcode (not CommandLineTools)
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# (optional) add your TMDb token for live enrichment
echo 'TMDB_BEARER_TOKEN = <your v4 bearer token>' > Secrets.xcconfig

xcodebuild -project ArchiveWatch/ArchiveWatch.xcodeproj \
  -scheme ArchiveWatch -configuration Debug \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build
```

Or open `ArchiveWatch/ArchiveWatch.xcodeproj` in Xcode and run on the Apple TV
simulator or a device. Version/build numbers live only in `AppVersion.xcconfig`
(never the Xcode identity panel — DECISION 003).

## The content pipeline

The catalog grows and self-heals automatically via scheduled GitHub Actions
(`.github/workflows/`): discovery (Wikidata public-domain feeds, Archive
collections, Library of Congress, TVmaze TV spines), ingestion of playable
derivatives, enrichment (TMDb / OMDb / Commons / Wikipedia), data-quality
remediation, and publishing the app's SQLite database. The pipeline is stateful
and merge-guarded so a rebuild can never shrink or clobber the catalog
(DECISION 020).

## The editorial web tool

The GitHub Pages root is a public **Suggest & Curate** tool:

- **Anyone** can suggest a public-domain title to add (it emails the curator).
- The **curator** arranges the app's home-screen shelves and searches the full
  catalog to include titles, then emails / commits the updated `featured.json`.

Run it locally with `python3 -m http.server` from the repo root, or visit the
hosted version. Privacy and support pages are served from the same site.

## Tech & conventions

- Swift 6, SwiftUI (`@Observable`, `@FocusState`, `TabView(.sidebarAdaptable)`),
  SwiftData, AVKit — **no third-party Swift packages**
- All networking through shared clients (Archive / TMDb / Wikidata); never
  `URLSession` directly from views
- Read-only on-device SQLite (libsqlite3 + FTS5) as the catalog source of truth
- tvOS-specific patterns (focus, sidebar, hero, the `@Query` cascade gotcha) live
  in `docs/tvos-playbook.md`; architecture rationale in `DECISIONS.md`

## Credits & attribution

Content is public domain via the [Internet Archive](https://archive.org).
Metadata and artwork from [TMDb](https://www.themoviedb.org) (this product uses
the TMDb API but is not endorsed or certified by TMDb), Wikidata, Wikimedia
Commons, TVmaze, and the Library of Congress. Archive Watch is a free,
non-commercial labor of love; the only suggested support is a
[donation to the Internet Archive](https://archive.org/donate).
