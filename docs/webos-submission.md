# LG webOS — submission pack

Everything LG Seller Lounge asks for, drafted so submission is paperwork rather
than authoring. **LG rejects submissions whose self-checklist is missing or
thin**, and that is the single most common avoidable rejection, so §2 is written
to be pasted as-is.

Backlog: `docs/TV-PLATFORM-BACKLOG.md` L1–L8. Strategy: Decision 047.
**LG is the first web-TV store to target** because an individual can publish
globally there, whereas Samsung's default Public Seller tier is US-only.

---

## 1. UX scenario

*LG asks for a narrative walkthrough of the app driven by the remote. This is
that document.*

**App:** Archive Watch — a cinematheque for the Internet Archive.
**Content:** public-domain and Creative-Commons film and television, streamed
directly from archive.org. No account, no advertising, no purchases.

### Launch

The app opens on **Home**. Focus lands on the featured title's hero, which shows
its backdrop, title, year, genre and a short synopsis. Pressing **OK** on the
hero opens that film. Pressing **Down** moves into the shelves.

### Browsing by remote

- **Down / Up** move between shelves (Continue Watching, editorial shelves such
  as "Popular Feature Films" and "Public-Domain Canon", then community-signal
  shelves and director collections).
- **Left / Right** move along a shelf. The focused poster scales, gains a
  coloured ring in its category accent, and lifts; the shelf scrolls to keep one
  poster of context visible.
- **Left** from the leftmost poster moves to the **navigation rail** (Home,
  Browse, Channels, Search, Library, Surprise, Settings).
- **Back** from Home exits the app. Back anywhere else returns to the previous
  surface.

### Finding something specific

**Search** offers an on-screen keyboard operated with the D-pad; results appear
as a grid as characters are entered. Because typing with a remote is slow,
Search also offers **browse-without-typing** shortcuts — every decade from the
1890s to the 2020s, plus themes — each of which opens a filtered grid. A viewer
can find something without entering a single character.

### Watching

Selecting a title opens its page: backdrop, title, year, runtime, synopsis, a
**Play** button (focused by default, so one press starts the film), a Favorite
toggle, and a "More Like This" shelf.

During playback:

- **OK** toggles play/pause.
- **Left / Right** rewind and fast-forward ten seconds.
- The dedicated **Play, Pause, Play/Pause, Rewind and Fast-Forward** keys work.
- The title and synopsis appear with the transport controls and fade with them.
- Subtitles, where the archive provides them, are selectable in the player.
- **Back** closes the player and returns to the title's page; playback stops.

### Channels

**Channels** presents a broadcast-style guide: a channel rail down the left, a
time ruler across the top, and programme blocks sized to their runtime. Focus
moves through the blocks with the D-pad; **OK** tunes in, joining the programme
in progress as a real channel would.

### Library and Settings

**Library** holds Favorites, Continue Watching and Playlists. **Settings**
carries a mature-content toggle (filtered by default), attribution for the
metadata sources, and a link to donate to the Internet Archive.

---

## 2. Self-checklist

*Paste into the Seller Lounge form. Every line has been exercised on a
1920×1080 TV surface.*

| # | Item | Result | Notes |
|---|---|---|---|
| 1 | App launches without error | Pass | Cold launch to Home |
| 2 | Every function reachable with the D-pad alone | Pass | 9 surfaces verified by an automated focus trace |
| 3 | Focus always visible | Pass | Ring + scale + elevation; never colour alone |
| 4 | Something is always focused | Pass | Claimed on entry to every surface, including loading states |
| 5 | Back returns to the previous screen | Pass | Layered: an open player closes before any navigation |
| 6 | Back at the root exits the app | Pass | `webOS.platformBack()` |
| 7 | Magic Remote pointer works | Pass | Hover moves focus; D-pad continues from there — one focus state |
| 8 | Media keys operate playback | Pass | Play, Pause, Play/Pause, Rewind, Fast-Forward |
| 9 | Playback starts and completes | Pass | Progressive H.264 MP4 over HTTPS from archive.org |
| 10 | Subtitles selectable where present | Pass | WebVTT via `<track>` |
| 11 | App pauses on suspend | Pass | `visibilitychange` |
| 12 | Relaunch restores usable state | Pass | `webOSRelaunch` re-claims focus |
| 13 | No text cut off at screen edges | Pass | 5% overscan-safe insets throughout |
| 14 | Legible at 10 feet | Pass | 24px body minimum at 1080p |
| 15 | No horizontal overflow | Pass | Asserted in the automated browser suite |
| 16 | No account or payment required | Pass | No sign-in, no advertising, no purchases |
| 17 | Content rights | Pass | Public-domain / CC only; see §4 |
| 18 | No third-party trackers | Pass | No analytics SDKs |

---

## 3. Store listing

- **Name:** Archive Watch
- **Category:** Video / Entertainment
- **Short description:** Watch the public domain — classic films, silent
  cinema, animation and vintage television, streamed free from the Internet
  Archive.
- **Screenshots:** 1280×720. Home, Browse, a title page, Channels, and
  playback.
- **Content rating:** general audiences; mature collections are filtered by
  default and gated behind a Settings toggle.
- **Support / privacy:** archivewatch.org/support · archivewatch.org/privacy

---

## 4. Rights position (for the content review)

Archive Watch streams only titles the pipeline has cleared as public domain or
Creative Commons. A rights audit runs on **every** published build and hides
anything that fails (Decisions 027 / 044): modern works without a genuine
free-culture licence are excluded, and a bogus "public domain" tag on a
commercial release does not rescue a title. Video is streamed from archive.org;
the app hosts no content.

---

## 5. Owner steps — nothing here is engineering

| # | Step |
|---|---|
| 1 | Create an **LG Seller Lounge** account (free; individuals may publish globally) |
| 2 | Create an **LG Developer** account and enable **Developer Mode** on an LG TV |
| 3 | Install the webOS TV CLI, then `./tv/build-tv-packages.sh webos` to produce the `.ipk` |
| 4 | Side-load and spot-check on the TV: `ares-install`, then `ares-launch` |
| 5 | Capture five 1280×720 screenshots |
| 6 | Submit the `.ipk`, this UX scenario (§1) and this self-checklist (§2) |
| 7 | Expect 5–10 business days, and possibly 2–3 review cycles |

Verify the CLI version at install time — published sources disagree (1.12.x vs
3.2.x), and the older CLI and VS Code extension were deprecated in 2024.
