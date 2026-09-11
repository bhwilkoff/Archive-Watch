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
commercials — into a browsing and viewing experience with the dignity of a
modern streaming service and none of its machinery. Around 32,000 titles,
each enriched with posters, cast, synopses and genres from TMDb, Wikidata,
Wikimedia Commons, TVmaze and the Library of Congress, so a 1920s silent
looks as considered as anything released this year.

It is **free**, with **no ads, no subscriptions, no account, and no tracking**.
It is built for the curious viewer who would rather wander a well-stocked
repertory cinema than doomscroll a recommendation feed.

## Why we build it this way

Every feature exists in service of human curiosity, not in place of it. Before
anything is built, it has to answer four questions: does it deepen the viewer's
understanding of the archive, does it invite them to participate, does it leave
them more capable rather than more dependent, and is it the clearest thing that
could work. That test is why the app looks the way it does:

- **The archive's own structure is the interface.** Decades, genres, curated
  collections, directors, the Public Domain Day shelf — you browse by the
  categories that actually organise the material, not a "for you" row that
  hides them. A film ends with a *choice* of what to watch next, never an
  autoplay decision made for you.
- **Wandering is a feature.** A dozen Surprise doors — a random film, a random
  decade, Cartoon Mode, Party Play, a cover-art screensaver — because the joy
  of a repertory house is finding what you did not know to look for.
- **You own what you keep.** Favorites, playlists and watch history live on
  your device and sync only through your own cloud: iCloud on Apple, Google
  Drive on Android, and both on the web. There is no Archive Watch server and
  nothing to sign up for.
- **Nothing is hidden about where a film comes from.** Every title shows its
  Internet Archive provenance, its metadata sources are credited on screen, and
  a film's other release title is shown rather than silently reconciled.
- **Rights are evidence, not a label.** A title is public domain in the app
  because the pipeline can say why — published before 1930, a government work,
  a real licence — and anything it cannot evidence is hidden, reversibly, until
  it can. Mature material is off by default on every platform, decided by one
  shared rule, so a viewer never meets it by accident.
- **Phones create, TVs watch.** The living-room apps are lean-back; the phone
  apps add Clip Studio and the Mac adds Creation Studio, because a public-domain
  archive is something you should be able to make with, not only consume.

## Features

**Discover**
- Home — a hero carousel plus curated and popularity-driven shelves, Hidden
  Gems, director shelves, Continue Watching
- Live Channels — a programmed, deterministic TV-guide grid (what's on now and
  next); tune in and it plays straight through, with vintage public-domain
  commercials between programs
- Movies, TV Shows and Collections — browse by type, decade, genre and curated
  collection; television is a real series → season → episode spine
- Search — full-text search with type and era filters, cast and director
  lookups, Siri dictation on Apple TV, and Roku Search integration so the
  Roku home menu finds the films too
- Surprise — random film, random decade, Public Domain Day, Cartoon Mode,
  Party Play, the screensaver, and more

**Watch**
- Resilient streaming that survives archive.org connection resets without a
  stall, with automatic failover between storage nodes
- Subtitles wherever they exist, live on-device captioning on Apple platforms
  where they do not, playback speed, picture-in-picture
- Watch Together over SharePlay on Apple TV, iPhone, iPad and Mac
- AirPlay and Google Cast to the television you already own
- Offline downloads on iPhone, iPad and Mac, with the film's real file choices
  shown rather than "standard" and "high"

**Keep**
- Favorites, playlists, user-made channels and a durable watch history, synced
  through your own cloud and never through ours
- Share links that open the film in whichever app you have, or on the web

**Create**
- Clip Studio on iPhone and Android: trim, reframe, caption, colour-grade,
  speed-change and export clips and GIFs with automatic provenance credits
- Creation Studio on the Mac: a multi-clip editor and supercut engine that
  searches every subtitle line in the archive and cuts the moments you name

## Parity across platforms

Same features, native idioms. Every platform is a native app over the same
catalog and the same rules; the differences below are platform facts, not
neglect. `PARITY.md` is the exhaustive ledger, kept in the same change set as
every feature.

| | Apple TV | iPhone / iPad | Mac | Android / Google TV / Fire TV | Roku | Web |
|---|:-:|:-:|:-:|:-:|:-:|:-:|
| Home, Browse, Collections, Search | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Live Channels (TV-guide grid) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Surprise, Cartoon Mode, Party Play | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Favorites, playlists, watch history | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Sync through your own cloud | iCloud | iCloud | iCloud | Google Drive | — | iCloud + Google |
| Subtitles and speed | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Live on-device captions | ✅ | ✅ | ✅ | — | — | — |
| Watch Together (SharePlay) | ✅ | ✅ | ✅ | — | — | — |
| AirPlay / Google Cast | receiver | AirPlay | AirPlay | Cast | receiver | Cast |
| Offline downloads | no storage | ✅ | ✅ | planned | no storage | — |
| Clip Studio | — | ✅ | — | ✅ | — | — |
| Creation Studio | — | — | ✅ | — | — | — |
| Home-screen surface | Top Shelf | widgets | — | shortcuts | — | PWA |
| Mature content off by default | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

A dash means the platform cannot do it or it does not apply: Apple TV and Roku
have no durable storage for a downloaded film, SharePlay and live captioning are
Apple frameworks, and a television is a Cast receiver rather than a sender.

## How it is built

- **One catalog, many apps.** A Python pipeline discovers titles, ingests
  playable derivatives, enriches metadata, audits rights, verifies that every
  file actually plays, and publishes one SQLite database that the Apple and
  Android apps download and one static index that the web viewer and the Roku
  channel read. Nothing user-facing has a server of ours behind it.
- **Measured, not assumed.** Features ship when they have been seen working on
  real hardware — an Apple TV, a Pixel, a Fire TV, a Roku — never a simulator.
  Every store's own validators are treated as the specification when the
  written one disagrees.
- **Native everywhere.** Swift and SwiftUI on Apple, Kotlin and Compose on
  Android, BrightScript on Roku, plain HTML and JavaScript on the web. No
  third-party frameworks, no analytics, no build steps the platform does not
  require.
- **The vetting is published, with numbers.** What is hidden and why — modern
  copyright, live advertising, wrong matches, trailers, files that do not
  decode — is at [archivewatch.org/vetting](https://archivewatch.org/vetting/),
  computed from the same catalog the apps ship, and it names the known gaps as
  well as the checks.
- **The reasoning is written down.** `DECISIONS.md` records why each choice was
  made and what the next person would get wrong without knowing it; each
  platform has a binding design document in `docs/`; the ten engineering
  disciplines this project learned the hard way are in
  `docs/ENGINEERING-PROCESS.md`.

## Credits & attribution

Content is public domain via the [Internet Archive](https://archive.org).
Metadata and artwork from [TMDb](https://www.themoviedb.org) (this product uses
the TMDb API but is not endorsed or certified by TMDb), OMDb, TheTVDB, Wikidata,
Wikimedia Commons, TVmaze, and the Library of Congress. Archive Watch is a free,
non-commercial labor of love; the only suggested support is a
[donation to the Internet Archive](https://archive.org/donate). Know a
public-domain film we are missing? Suggest it at
[archivewatch.org/curate](https://archivewatch.org/curate/).
