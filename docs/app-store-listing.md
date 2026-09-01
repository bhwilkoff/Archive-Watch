# App Store + TestFlight submission copy — Archive Watch

Paste-ready. Character limits noted; drafts are within them. Tone: a repertory
cinema, not a streaming funnel. Part 1 = tvOS (submitted + approved 2026-06-11).
Part 2 (below the tvOS section) = **iOS/iPadOS** — added as a second platform on
the SAME App Store Connect app record.

## Required URLs (live on GitHub Pages)
- **Privacy Policy:** https://archivewatch.org/privacy.html
- **Support:** https://archivewatch.org/support.html
- **Marketing (optional):** https://archivewatch.org/ (the web viewer — every shared title is watchable here)

## Identifiers / basics
- Bundle ID `app.archivewatch.tvos` · Team `L2G756LY8N` · Platform **tvOS** · Min **tvOS 26.0**
- **Price: Free** (no IAP, no subscription, no ads — Decision 010)
- **Primary category:** Entertainment · Secondary: Education
- **Copyright:** `© 2026 Ben Wilkoff` (use the Apple Developer account holder's
  name — individual or org). Covers the APP only; the public-domain content is
  not owned. No URL, no "All Rights Reserved".

---

## Name (≤30)
`Archive Watch`

## Subtitle (≤30)
`A cinematheque for Apple TV`

## Promotional Text (≤170 — editable anytime, no review)
`Now with live Channels: a programmed TV guide of public-domain cinema with
vintage commercials between shows. Tune in and it just plays.`

## Keywords (≤100, comma-separated, no spaces)
`public domain,classic movies,silent film,old tv,cinema,documentary,free movies,retro,film noir,commercials`

## Description (≤4000)
```
Archive Watch turns the Internet Archive's vast public-domain moving-image
collection into a cinematheque you can wander from your couch — feature films,
classic television, silent cinema, animation, newsreels, and the strange,
wonderful world of vintage commercials and ephemeral film.

Every title is presented with the care of a great repertory house: real posters,
cast, synopses, and genres, so a 1920s silent and a 1950s sci-fi B-movie look as
considered as anything on a modern streaming service.

LIVE CHANNELS — A REAL TV GUIDE
- A programmed, scrolling channel guide: see what's on now and next
- Tune in and it plays straight through, one title rolling into the next
- Vintage public-domain commercials play between programs — the 1990s-TV feel
- Build your own channel from any mix of genre, type, and era

A REPERTORY HOUSE, NOT A FEED
- Hand-curated shelves alongside the most-watched titles from the Archive
- Browse by decade, genre, and collection
- Classic TV with real series, seasons, and episodes
- Surprise Me — for when you'd rather be delighted than decide

BUILT FOR THE LIVING ROOM
- Native Apple TV experience, full-screen and focus-driven
- Resume right where you left off
- Search with the Siri Remote or your voice
- Favorites and playlists in your Library
- Cartoon Mode, Party Play, and a cover-art screensaver

FREE, AND RESPECTFUL OF YOU
- No subscription, no in-app purchases, no ads
- No account required to watch
- No tracking, no analytics — nothing about you is collected
- Optional Sign in with Apple syncs your favorites and progress across your
  household's Apple TVs using your own iCloud

All content is sourced from the public domain via the Internet Archive. Metadata
and artwork come from TMDb, Wikidata, Wikimedia Commons, and the Library of
Congress. This product uses the TMDb API but is not endorsed or certified by TMDb.

If you'd rather wander a well-stocked repertory cinema than doomscroll a
recommendation feed, Archive Watch is for you.
```

## What's New / release notes (this version)
```
- New: Live Channels — a programmed TV guide with now/next, tune-in-and-it-plays,
  and vintage commercials between shows.
- New: build your own channel from genre / type / era filters (redesigned with
  large, easy pills).
- Vintage public-domain commercials added as a browsable collection + Surprise.
- Redesigned Add-to-Playlist for a native tvOS feel.
- Optional idle screensaver; modes surfaced on Home.
- Stability + metadata improvements.
```

---

## TestFlight — Beta App Information (for wider/external testing)

### Beta App Description (what testers see)
```
Archive Watch is a free Apple TV app for browsing and watching public-domain
films, classic TV, silent cinema, animation, and vintage commercials from the
Internet Archive — presented like a repertory cinema.

This beta is for trying the new Live Channels guide, building your own channels,
the vintage-commercial breaks, playlists, and Sign in with Apple sync. No account
is required to watch — sign-in is optional and only syncs favorites/progress.
```

### What to Test (this build)
```
- Channels: open the Channels tab, scan the guide (what's on now/next), tune a
  cell, confirm it plays straight through with a commercial between programs.
- Create Channel: tap Create Channel, pick any mix of Genre / Type / Era pills,
  confirm the channel appears in the guide and plays.
- Settings > Playback: toggle "Commercial Breaks on Channels" and "Idle
  Screensaver"; confirm behavior.
- Browse / Search / Collections / TV Shows: scroll, open a title, play it,
  confirm resume-on-reopen.
- Library: favorite a few titles (heart on a Detail page), build a playlist,
  confirm they appear.
- Sign in with Apple (optional, Settings > Account): confirm sign-in works and
  the screen shows "Signed in"; Delete Account removes synced data.
- Report any title that won't play, looks mismatched, or any focus/navigation
  snag.
```

### Beta App Review Information
- **Sign-in required to review?** No. Browsing + playback work fully signed-out.
- **Demo account:** Not needed (no accounts; Sign in with Apple is optional and
  uses the reviewer's own Apple ID).
- **Contact:** Ben Wilkoff · ben@learningischange.com
- **Notes:**
```
All content is public domain, streamed directly from the Internet Archive
(archive.org). The app has no backend and collects no user data. Sign in with
Apple is optional and only syncs the user's own favorites/watch-progress to their
private iCloud (we have no access). Some archival streams can be slow or briefly
unavailable on the source side — retry or pick another title.
```

---

## App Review (App Store) notes — when promoting beyond TestFlight
```
Archive Watch surfaces public-domain moving images from the Internet Archive
(feature films, classic TV, silent cinema, animation, newsreels, and vintage
commercials). Content is public domain; metadata/artwork from TMDb (attributed
on the Settings screen), Wikidata, Wikimedia Commons, and the Library of Congress.
No account is required. Sign in with Apple is optional and only enables iCloud
sync of the user's own favorites/progress; account deletion is provided in
Settings (Guideline 5.1.1(v)). No data is collected by the developer (see the
PrivacyInfo manifest + Privacy Policy). Export compliance is declared in-binary
(ITSAppUsesNonExemptEncryption = false; HTTPS/TLS + Apple frameworks only).
```

## App Privacy questionnaire
**Answer: Data Not Collected.** No backend, no analytics; sign-in/sync data lives
in the user's own iCloud private database (developer can't read it) and the
submitted build keeps CloudKit gated off. If asked: declare only the Apple User ID
as used for app functionality, not linked to identity, not used for tracking.

## Age rating
Run the questionnaire honestly. With the default mature-content filter ON, expect
~**12+** (infrequent/mild mature themes possible in archival content; "Unrestricted
Web Access" = No — browsing is confined to the curated catalog).

---

## Screenshots (Apple TV — 3840×2160, captured from the tvOS 26 simulator)
The final, App-Store-ready set lives **outside the repo** (they're upload assets,
not source — ~40 MB of 4K PNGs would bloat git, and they're regenerable):

    ~/Desktop/ArchiveWatch-AppStore-Screenshots/

Upload them to App Store Connect in this order (App Store allows up to 10):
1. `01-Home.png`               — hero + Browse by Category
2. `02-Channels-Guide.png`     — the EPG with now/next + ratings
3. `03-Detail-HisGirlFriday.png`
4. `04-Detail-Metropolis.png`
5. `05-Detail-NightOfTheLivingDead.png`
6. `06-Movies.png`
7. `07-Collections.png`
8. `08-TVShows.png`
9. `09-Surprise.png`
10. `10-CreateChannel.png`

(Skip Library — empty state on a fresh install. NOTLD's synopsis is a junk
uploader note; remediate or swap that Detail if it bothers.)

To regenerate any screen: launch the Debug build with
`SIMCTL_CHILD_AW_START_TAB=<home|channels|browse|tvShows|collections|surprise|favorites>`
or `SIMCTL_CHILD_AW_START_ITEM=<archiveID>` (env hooks in Router/RootView, no-ops
in production).

---
---

# Part 2 — iOS / iPadOS (added 2026-06-11, app version 1.2.24 build 37)

The iPhone/iPad version ships from the SAME universal target and bundle ID
(`app.archivewatch.tvos`), so in App Store Connect it is **a new platform on the
existing app record**, not a new app:

ASC → Archive Watch → **+ Add Platform → iOS** → a new "1.2.24 Prepare for
Submission" page appears with its own description / keywords / screenshots /
review fields (everything below). Archive from Xcode with **Any iOS Device
(arm64)** selected and upload — same scheme, same signing team `L2G756LY8N`.

## Identifiers / basics (iOS)
- Same bundle ID `app.archivewatch.tvos` · Team `L2G756LY8N` · Min **iOS 26.0**
- Devices: iPhone + iPad (TARGETED_DEVICE_FAMILY 1,2)
- Price/category/copyright: unchanged (Free, Entertainment + Education,
  `© 2026 Ben Wilkoff`)
- Export compliance auto-answered in-binary (`ITSAppUsesNonExemptEncryption=false`)

## ⚠️ App-level fields shared with the tvOS listing
**Name** and **Subtitle** live on the App Information page and are shared across
platforms — the current subtitle `A cinematheque for Apple TV` would be wrong on
an iPhone product page. Change it (takes effect with this submission, also shown
on the tvOS listing):

### Subtitle (≤30, app-level — replaces the tvOS-only one)
`A public-domain cinematheque`

(28 chars. Alternatives if it reads stiff: `Watch the public domain` (23),
`Classic film, free forever` (26).)

## Promotional Text (≤170 — iOS version, editable anytime)
`Now on iPhone and iPad — the whole cinematheque in your pocket, with Live
Channels, Picture in Picture, background audio, and sync with your Apple TV.`

## Keywords (≤100, comma-separated, no spaces — iOS version)
`public domain,classic movies,silent film,old tv,cinema,documentary,free movies,retro,film noir,commercials`

(Same proven set as tvOS; "iphone/ipad" are never useful as keywords.)

## Description (≤4000 — iOS version)
```
Archive Watch turns the Internet Archive's vast public-domain moving-image
collection into a cinematheque you can carry — feature films, classic
television, silent cinema, animation, newsreels, and the strange, wonderful
world of vintage commercials and ephemeral film.

Every title is presented with the care of a great repertory house: real posters,
cast, synopses, and genres, so a 1920s silent and a 1950s sci-fi B-movie look as
considered as anything on a modern streaming service.

LIVE CHANNELS — A REAL TV GUIDE
- A programmed channel guide, laid out like a true TV listing: see what's on
  now and next, scroll the broadcast day
- Tune in and it plays straight through, one title rolling into the next
- Vintage public-domain commercials play between programs — the 1990s-TV feel
- Build your own channel from any mix of genre, type, and era

A REPERTORY HOUSE, NOT A FEED
- Hand-curated shelves alongside the most-watched titles from the Archive
- Browse by decade, genre, and collection
- Classic TV with real series, seasons, and episodes — binge straight through
- Tap any actor or director to wander their whole filmography
- Surprise Me — for when you'd rather be delighted than decide

MADE FOR IPHONE AND IPAD
- Picture in Picture — keep watching while you do anything else
- Background play — lock the screen and the audio keeps going, with full
  lock-screen controls
- AirPlay to any TV
- Continue Watching and Editor's Picks widgets on your Home Screen
- Cartoon Mode, playlists, search filters, and resume everywhere

YOUR APPLE TV, IN SYNC
- Optional Sign in with Apple syncs favorites, playlists, progress, and your
  custom channels between iPhone, iPad, and Apple TV — through your own
  iCloud, never our servers

FREE, AND RESPECTFUL OF YOU
- No subscription, no in-app purchases, no ads
- No account required to watch
- No tracking, no analytics — nothing about you is collected

All content is sourced from the public domain via the Internet Archive. Metadata
and artwork come from TMDb, Wikidata, Wikimedia Commons, and the Library of
Congress. This product uses the TMDb API but is not endorsed or certified by TMDb.

If you'd rather wander a well-stocked repertory cinema than doomscroll a
recommendation feed, Archive Watch is for you.
```

## What's New / release notes (iOS 1.2.24 — first iPhone/iPad release)
```
Archive Watch arrives on iPhone and iPad — the same cinematheque as the Apple
TV app, rebuilt touch-first:

- Live Channels as a real TV-listing guide: scroll the broadcast day, tune in,
  and it just plays (vintage commercials included).
- Picture in Picture and background play with lock-screen controls.
- Home Screen widgets: Continue Watching and Editor's Picks.
- Tap any cast or crew name to browse their filmography.
- Optional Sign in with Apple keeps favorites, playlists, progress, and your
  custom channels in sync with your Apple TV — via your own iCloud.
```

## App Review notes (iOS — paste into the version's Review Information)
```
Archive Watch surfaces public-domain moving images from the Internet Archive
(feature films, classic TV, silent cinema, animation, newsreels, and vintage
commercials). Content is public domain; metadata/artwork from TMDb (attributed
on the Settings screen), Wikidata, Wikimedia Commons, and the Library of
Congress.

No account is required. Sign in with Apple is optional and only enables iCloud
sync of the user's own favorites/progress to their private database; account
deletion is provided in Settings (Guideline 5.1.1(v)). No data is collected by
the developer (see the PrivacyInfo manifest + Privacy Policy).

UIBackgroundModes `audio` is used for continued playback of the film's audio
when the app is backgrounded (with lock-screen Now Playing controls) and for
Picture in Picture — both are user-facing playback features, reachable by
playing any title and pressing the side button or swiping Home.

Export compliance is declared in-binary (ITSAppUsesNonExemptEncryption = false;
HTTPS/TLS + Apple frameworks only). Some archival streams can be slow or
briefly unavailable on the source side — retry or pick another title.
```

- **Sign-in required to review?** No. Demo account: not needed.
- **Contact:** Ben Wilkoff · ben@learningischange.com

## App Privacy (unchanged answer, updated rationale)
**Data Not Collected** still holds: no backend, no analytics. CloudKit sync is
NOW ENABLED in this build (unlike the first tvOS submission), but synced
favorites/progress live in the user's private iCloud database, which the
developer cannot read — under Apple's definitions ("collected" = transmitted off
device AND accessible to the developer) that is not collection. If a reviewer
pushes back, the fallback declaration is: Identifiers → User ID (the Sign in
with Apple identifier), App Functionality only, not linked to identity, not
used for tracking.

## Age rating
Same questionnaire, same answers as tvOS → expect the same ~12+ (mature filter
defaults ON; no unrestricted web access).

## URLs (unchanged, already live)
- Privacy `https://archivewatch.org/privacy.html` · Support
  `https://archivewatch.org/support.html` · Marketing `https://archivewatch.org/`

---

## Screenshots (iOS — captured from the iOS 26 simulators)

Live OUTSIDE the repo (upload assets, regenerable):

    ~/Desktop/ArchiveWatch-AppStore-Screenshots-iOS/
        iphone-6.9/   — 1320×2868 portrait (iPhone 17 Pro Max sim)
        ipad-13/      — 2064×2752 portrait (iPad Pro 13-inch M5 sim)

ASC requires ONE iPhone size (6.9" or 6.5") and ONE iPad size (13") for an app
that runs on iPad — both sets below. Upload order (up to 10 each):
1. `01-Home.png`        — hero + shelves
2. `02-Channels.png`    — the touch EPG (now-line + ruler)
3. `03-Detail-HisGirlFriday.png`
4. `04-Detail-Metropolis.png`
5. `05-Detail-NightOfTheLivingDead.png`
6. `06-Browse.png`
7. `07-Detail-Superman.png` — color Fleischer cartoon (shows range + cast row)

(Search/Library are empty states on a fresh install — skipped.)

To regenerate: install the Debug build on the sim and launch with
`SIMCTL_CHILD_AW_START_TAB=<home|browse|channels|search|library>` (the iOS tab
raw values) or `SIMCTL_CHILD_AW_START_ITEM=<archiveID>`; wait ~25–30 s on cold
start (seed DB load) before `xcrun simctl io <udid> screenshot`. Boot ONE sim
at a time (two iOS 26 sims booting together can wedge "Waiting on System App").

---

## Owner submission checklist (iOS)
1. ASC → My Apps → Archive Watch → **+ → Add Platform → iOS**.
2. App Information: change **Subtitle** to the platform-neutral one above.
3. On the iOS 1.2.24 version page: paste Promotional Text, Description,
   Keywords, What's New, Review notes; URLs carry over.
4. Upload both screenshot sets from `~/Desktop/ArchiveWatch-AppStore-Screenshots-iOS/`.
5. Age rating: re-run questionnaire (same answers as tvOS).
6. App Privacy: confirm **Data Not Collected** (see note above).
7. Xcode: destination **Any iOS Device (arm64)** → Product → Archive →
   Distribute → App Store Connect. (Version/build 1.2.24/37 come from
   AppVersion.xcconfig; build 37 is shared with the tvOS track — fine, build
   numbers are per-platform in ASC.)
8. Select the build on the version page → Add for Review → Submit.

---

# 1.3.491 (build 1009) — submission copy

Written against the actual diff from build **991** (the last approved
version) to **1009**: 79 commits, of which the user-facing ones are
SharePlay, the iPhone 12 + iPad Pro audits, the poster-proportion work
(Decision 097), the tvOS Play-label truncation, review/description
reachability, and pipeline data-quality corrections.

Each Apple platform has its own Promotional Text and What's New field in
App Store Connect — they are NOT shared, even though the three platforms
share one app record.

**Accuracy notes for whoever edits this:** Watch Together attaches to FILM
playback, not to Channels — do not imply a channel or its commercials sync.
tvOS cannot PLACE a FaceTime call (`GroupActivitySharingController` does not
exist there, see `docs/SHAREPLAY.md`), so tvOS copy must not promise
starting a call from the Apple TV with no call already live.

## tvOS

### Promotional Text (133/170)
```
Watch Together is here: play any film in sync with friends over FaceTime. Pause, seek, or resume and everyone's screen follows along.
```

### What's New (1017/4000)
```
Watch Together — SharePlay comes to Archive Watch

Watch any film in perfect sync with friends and family over FaceTime. Pause,
seek, or resume and everyone's screen follows along. If someone's connection
slows down, the group waits for them instead of drifting apart.

Start a session on your Apple TV while a FaceTime call is going, join one
someone else started, or begin on your iPhone or Mac and move the call to the
big screen.

Also in this release:

- The Play button now always shows the full runtime, or exactly where you left
  off. No more cut-off times.
- Artwork is never stretched or cropped to fit. Every poster is shown at its
  own proportions over an ambient backdrop, and the Home screen features
  professionally designed posters.
- Film descriptions, reviews, and source attribution can now be reached and
  read in full — nothing is clipped or left off-screen.
- Hundreds of titles corrected behind the scenes: better cast lists, accurate
  ratings, and films sorted into the right categories.
```

## iOS / iPadOS

### Promotional Text (138/170)
```
Watch Together is here: pick a film, start the FaceTime call right from the app, and watch in sync on iPhone, iPad, Mac, or your Apple TV.
```

### What's New (1479/4000)
```
Watch Together — SharePlay comes to Archive Watch

Watch any film in perfect sync with friends and family. Pick a title, tap
Watch Together, and start the FaceTime call right from the app — no need to
set the call up first. Pause, seek, or resume and everyone follows along, and
if someone's connection slows down the group waits for them.

Sessions move between devices: start on your iPhone and carry the call to your
iPad, your Mac, or your Apple TV.

iPad is now its own experience:

- A genuine two-column layout, not a stretched-up phone screen.
- Reading measures are capped so synopses and reviews stay comfortable instead
  of running the full width of the display.
- Controls and selectors are sized for the iPad rather than blown up.

iPhone fixes from a full pass over every screen:

- Search filters can now actually be reached and used.
- The Play button offers Resume when you're partway through a film.
- Text no longer loses its first character on Detail screens.
- Settings stays where you are when you flip a toggle, instead of jumping back
  to the top.
- More controls are properly labelled for VoiceOver.

Everywhere:

- Artwork is never stretched or cropped to fit — posters are shown at their own
  proportions, and Home features professionally designed artwork.
- Reviews and descriptions are readable in full, no longer clipped mid-word.
- Hundreds of titles corrected: better cast lists, accurate ratings, and films
  sorted into the right categories.
```

## macOS

### Promotional Text (143/170)
```
Watch Together is here: start a FaceTime call from the app and watch public-domain classics in sync with friends on any of their Apple devices.
```

### What's New (843/4000)
```
Watch Together — SharePlay comes to Archive Watch

Watch any film in perfect sync with friends and family. Choose a title, pick
Watch Together from the Share menu, and start the FaceTime call right from the
app. Pause, seek, or resume and everyone follows along; if someone's connection
slows down, the group waits for them rather than drifting apart.

Sessions move between devices, so a film you start on the Mac can carry over to
an iPhone, iPad, or Apple TV.

Also in this release:

- Artwork is never stretched or cropped to fit. Posters are shown at their own
  proportions, and the Home screen features professionally designed artwork.
- Long reviews and descriptions expand properly instead of being cut off
  mid-word.
- Hundreds of titles corrected: better cast lists, accurate ratings, and films
  sorted into the right categories.
```

## Review notes (paste into App Review Information)

```
Watch Together uses SharePlay (GroupActivities) to play the same public-domain
film in sync for everyone in a FaceTime call. To test it: start a FaceTime call
between two devices, open any film's detail screen, and choose Watch Together.
On iPhone, iPad and Mac the app can also place the call itself — choose Watch
Together with no call active and the system sharing sheet appears.

All content is public domain, streamed from the Internet Archive. No account is
required and no user data is collected.
```
