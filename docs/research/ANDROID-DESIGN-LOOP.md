# Android design loop — phone and Google TV (2026-09-29)

Owner: *"Let's do a full audit of the android surfaces and app as well. This
includes both a full rundown of all features that show on Android Phone as well
as all features and interface elements on the Android/Google TV implementation
as well."*

Binding docs: `docs/ANDROID-DESIGN.md` (phone), `docs/TV-DESIGN.md` (Android TV
+ web-TV). Parity: `PARITY.md`. Method as in the tvOS, Mac and iPad loops:
inventory from the code, then every surface on the glass, one commit a tick.

## Devices

- **Pixel 8a**, Android 17 beta, `10.0.0.175` over TLS ADB. Kept losing its
  pairing: `adb_allowed_connection_time` was 604800000 ms (7 days), which
  revokes a computer's wireless-debugging trust; set to 0 on 2026-09-29.
- **Google TV Streamer** (SEI Dongle R 4K), Android 14, `10.0.0.55:5555`. Drops
  its ADB connection when it wakes from the screensaver; reconnect.
- Debug build `com.archivewatch.app.debug`, flavor `google`, versionCode 65.
- Use only `~/Library/Android/sdk/platform-tools/adb` (a second adb binary
  restarts the server).

## First look (tick 1)

- **Google TV Home**: TONIGHT · The Farmer's Wife (1928) leads the hero, with a
  three-line synopsis; the rail is icons only and holds Cartoons (palette) and
  Party Play (confetti) as their own entries.
- **Phone Home**: the hero showed Tanned Legs (1929), not the Tonight film;
  Continue Watching shows the year under each poster, not the time left, and
  no progress bar.

## Inventory (tick 1, from the code)

**Shell.** One activity; `isTelevision()` picks `TvAppRoot` or `AppRoot`;
navigation is plain state (`Nav`: a tab + one route stack, 14 route cases).
- Phone: `NavigationSuiteScaffold` — Home, Browse, Channels, Search, Library;
  Settings and Surprise from Home's top bar.
- TV: `TvNavRail` (icons, expands on focus) — Home, Browse, Channels, Search,
  Library, then Collections, Cartoons, Party, Surprise, Settings.

**Phone surfaces**: Home (hero + Tonight eyebrow, category tiles, Continue,
featured, Top Rated, Watching Now, Community, Most Discussed, Hidden Gems,
director shelves, PD Day, eras) · Browse (scope chips, decade/length/facet/
sort menus) · Search · Channels (proportional guide, create channel) · Library
(Favorites, Continue, Playlists, History, Clips; Join a room) · Detail (action
row: Play, Favorite, Playlist, Watched, Choose a copy, Get subtitles, Clip,
Share; ⋮ Watch Together / View on archive.org / Something wrong) · Series ·
Player (options sheet: next episode, speed, subtitles, copies, autoplay; PiP;
Cast) · Filtered/PD explorer · Surprise · Playlist · Collections · Person ·
Cartoons · Shared list · Clip Studio · Settings · 3 widgets, 2 shortcuts.

**TV surfaces**: Home (TvHero, left/right cycles) · Browse · Channels (shared) ·
Search (keycaps, browse-without-typing doors) · Library (Favorites, Continue,
History, Playlists, Watch Together join keypad) · Detail (Play, Favorite,
Watched, Playlist, Share QR + report toggle, Watch Together, Version, Part of
series; Cast & Crew, reviews, Scenes, More Like This) · Series · Collections ·
Cartoons · Party · Surprise · Settings · Player (options panel on Up/Menu) ·
Google TV Watch Next.

## Findings (tick 1)

Parity gaps (another platform has it, Android does not):
- A. Channel up/down surfing, phone and TV (PARITY ⏳); on TV, D-pad Up opens
  the player's options panel today.
- B. Commercial Breaks on/off: no setting on Android (PARITY ⏳).
- C. Continue Watching time left + progress: to check on the glass (phone
  showed the year).
- D. Phone Series page: no Share or Favorite (the TV one has both; Apple's
  has Play-with-episode + Favorite).
- E. Cartoons and Party Play are TV rail entries; the owner's 2026-09-28
  answer puts the modes in Surprise on every platform.
- F. Downloads (PARITY ⏳, six rows) — the largest gap.
- G. TV Detail: "Something wrong with this film?" is a toggle inside Share,
  where Apple TV gives it its own action.

Stale records:
- H. PARITY cells say ⏳ for things in code: PiP, background play, autoplay,
  category toggles, widgets; §8b sync.
- I. ANDROID-DESIGN §3.2 (routes), §4.2b (TV Scenes "not built"), §4.5
  (Library), §7 (out-of-scope list contradicts the code); TV-DESIGN §2
  (Movies/TV rail entries that do not exist).

Harness:
- J. `aw_start_tab` / `aw_start_route` are collected only by `TvAppRoot`; the
  phone can be driven only by `archivewatch://` hosts and taps.

- K. **TV Search: the keyboard's sixth column is cut off** — F, L, R, X, 3
  and 9 sit half under the "Or browse without typing" panel (1920-wide
  capture, so not a crop).

## Queue

1. ✅ J — phone launch doors: one shared `Nav.collectStartDoors()` in both roots (v1.42.933); the Pixel opened Library, the TV Search
2. Walk every surface on both devices; the glass decides C, E and the hero
3. ✅ Kotlin warnings: 8 distinct (16 across both flavors) -> 0, both compile tasks re-run (v1.42.932)
4. D, E, G, A, B; then H and I with each change; F is its own project
