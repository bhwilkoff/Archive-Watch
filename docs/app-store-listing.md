# App Store + TestFlight submission copy — Archive Watch (tvOS)

Paste-ready. Character limits noted; drafts are within them. Tone: a repertory
cinema, not a streaming funnel. Updated 2026-06-05 for the Channels TV-guide +
vintage-commercials + native create flows.

## Required URLs (live on GitHub Pages)
- **Privacy Policy:** https://bhwilkoff.github.io/Archive-Watch/privacy.html
- **Support:** https://bhwilkoff.github.io/Archive-Watch/support.html
- **Marketing (optional):** https://bhwilkoff.github.io/Archive-Watch/

## Identifiers / basics
- Bundle ID `app.archivewatch.tvos` · Team `L2G756LY8N` · Platform **tvOS** · Min **tvOS 26.0**
- **Price: Free** (no IAP, no subscription, no ads — Decision 010)
- **Primary category:** Entertainment · Secondary: Education

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
Generated this session in `/tmp/appstore_shots/` (App Store allows up to 10).
Recommended order:
1. **Home** — hero + Browse by Category (`01-home.png`)
2. **Channels guide** — the EPG with now/next + ratings (`02-channels.png`)
3. **Detail — His Girl Friday** (`d2-his-girl-friday.png`)
4. **Detail — Metropolis** (`d4-metropolis.png`)
5. **Detail — Night of the Living Dead** (`d1-living-dead.png`)
6. **Movies grid** (`03-movies.png`)
7. **Collections** (`05-collections.png`)
8. **TV Shows** (`04-tvshows.png`)
9. **Surprise** (`06-surprise.png`)
10. **Create Channel** (`/tmp/create_channel.png`)

(Skip Library — empty state on a fresh install. NOTLD's synopsis is a junk
uploader note; remediate or swap that Detail if it bothers.)

To regenerate any screen: launch the Debug build with
`SIMCTL_CHILD_AW_START_TAB=<home|channels|browse|tvShows|collections|surprise|favorites>`
or `SIMCTL_CHILD_AW_START_ITEM=<archiveID>` (env hooks in Router/RootView, no-ops
in production).
