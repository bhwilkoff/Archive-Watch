# Samsung Tizen — submission pack

Companion to `docs/webos-submission.md`. The **app is identical** — same web
build, same TV layer, differing only in key codes, lifecycle events and
packaging (Decision 047 §7.3). What differs is Samsung's process, and one
business decision that is genuinely yours.

Backlog: `docs/TV-PLATFORM-BACKLOG.md` S1–S6.

---

## ⚠️ 1. Read this before creating the account

**Samsung's default "Public Seller" tier can only launch apps in the United
States.** Publishing anywhere else requires **Partner Seller**, which requires
signing an offline contract with Samsung HQ or a local subsidiary — i.e. a
business entity.

That is why the recommended order is **LG first, Samsung second**: LG lets an
individual publish globally with no equivalent gate, so it buys real reach while
this decision stays open.

**DECIDED 2026-09-10 (owner): Public Seller, US-only.** Global reach is not
worth signing an offline contract with Samsung HQ and standing up a business
entity for a free, ad-free app. Partner remains open later — the `.wgt` is
identical either way, so this decision costs nothing but reach and can be
revisited without rebuilding anything.

Your options:

| Option | Reach | Cost |
|---|---|---|
| **Public Seller** | US only | Free, immediate |
| **Partner Seller** | Global | Free, but needs a signed contract + a business entity |

Neither blocks engineering — the `.wgt` is the same either way. This only
decides where it can be listed.

---

## 2. Samsung's review is a manual QA pass

Unlike LG's document-driven review, Samsung runs the app against their Launch
and Development checklists by hand. The items that matter for this app:

| Area | Status | Notes |
|---|---|---|
| **Tested on the TV, 2026-10-03** | **v1.45.10, QN65S90C (Tizen 9.0)** | Driven over a remote inspector (`docs/tizen-signing.md`, 2026-10-03), with the owner reading the glass. Rows below marked 10-03 were measured there, not argued |
| Launch time (10 s required, 5 s ideal) | **6.9 s, 10-03** | Cold launch to Home's cards: first paint 1.6 s, `catalog-index.json` (2 MB gzip) in by 2.3 s, cards at 6.9 s. Inside the requirement, short of the ideal |
| Return on the home screen | **Pass, 10-03** | Asks "Exit Archive Watch?" (Exit / Stay), as the Return policy requires; everywhere else Return steps back one layer |
| Screensaver during playback | **Pass, 10-03** | `webapis.appcommon.setScreenSaver` off while a film plays, back on at pause/end |
| Playback resumes after the app returns (CO-MT-01) | **Pass, 10-03** | A film the app paused on going to the background resumes on return |
| Network lost (CO-CN-02) | **Pass, 10-03** | An offline banner, also inside the player |
| Long playback | **Pass, 10-03** | 351 s continuous with no stall; Tizen's end-of-file error is read as the film's end; Speed is not offered (Tizen's player breaks on a rate change) |
| Launches without error | **Verified — the owner has used several builds on the QN65S90C** | Retail Tizen closes `sdb shell` entirely — no console, no screenshot, no dlog — so no TOOL here can see Home render. A person can: the owner has used 1.42.72, .78, .90, .99 and .100 on the panel and returned specific feedback on navigation, type size and the EPG, which is only possible if films are on screen. (This row read 'Not verified' until 2026-09-14, long after that stopped being true.) `tools/test_packaged_origin.mjs` (23) guards the known cause of an empty Home, including that every script index.html loads is actually in the package. **Owner: confirm films appear before submitting** |
| Full D-pad operability | Pass, **re-verified 2026-09-10** | The August claim of "9 surfaces verified" was **wrong** and this is what it cost: the Home HERO had no focusable element at all (the marquee, unreachable), and Browse's four filters were focusable but DEAD because tv.js ran spatial navigation on every arrow without checking what had focus. Both measured on the live site, both fixed, both now covered by `tools/test_tv_focus.mjs` (32 cases) with controls |
| Focus always visible | Pass | Ring + scale + elevation, never colour alone |
| **Back / Return behaviour** | Pass | Layered — an open player closes before any navigation; exits at the root via `tizen.application…exit()` |
| Media keys | Pass | Registered through `tizen.tvinputdevice.registerKey()` — **Tizen does not deliver them otherwise** |
| Playback | Pass | Progressive H.264 MP4 over HTTPS; no DRM needed |
| Subtitles | **Pass, 10-03** | WebVTT, chosen in Player Options and drawn by the app at ten-foot size (the system renderer's size could not be set) |
| Suspend / resume | Pass | `visibilitychange` pauses; focus re-claimed on return |
| Overscan | Pass | 5% safe insets; no text at the panel edge |
| Ten-foot legibility | Pass | 24px body, 20px for a card's year caption, 32-64px headings — all tokens in `tv.css`, none a loose literal |
| No account / payment | Pass | No sign-in, advertising, or purchases |
| Content rights | Pass | Public-domain / CC only — see `docs/webos-submission.md` §4 |

The remote-driven walkthrough Samsung may ask for is the same as
`docs/webos-submission.md` §1; the app behaves identically.

---

## 2b. Older Samsung TVs — the floor is 2022 (Tizen 6.5, Chromium 85)

Owner, 2026-10-03: *"I'd like to be able to support everything from 2022
onward."* Samsung's browser engine by model year: 2022 Tizen 6.5 = Chromium 85,
2023 Tizen 7.0 = 94, 2024 Tizen 8.0 = 108, 2025 Tizen 9.0 = 120. The test set
(QN65S90C) has been updated to Tizen 9, so it says nothing about a 2022 set.

**Rendered in a real Chromium 85 build before it was fixed, Home was EMPTY**:
`replaceChildren` (86) threw while drawing it, and `AbortSignal.timeout` (103)
threw on every bounded fetch. Behind those, the CSS: `inset` and the
`padding-inline`/`margin-inline` shorthands (87) dropped the overscan padding
and un-centered every sheet; a rule list holding `:focus-visible` (86) is
dropped whole, hiding the picker's focused option; `color-mix()` (111) inside
a declaration with `var()` voids its own fallback, so the category tiles drew
with no color on every 2022-24 set.

Fixed by `js/compat.js` (loaded first; fills only what 85 lacks), longhand
CSS, `:focus` on TV, and `@supports` around `color-mix()` and the guide's
`overflow: clip` sticky titles. `tools/test_tv_compat.py` holds the CSS rules
with planted controls, and `tv/build-tv-packages.sh` refuses to package when it
fails. `config.xml` declares `required_version="6.5"`.

**To check a change on a 2022 engine** (no 2022 TV exists here): Google's
Chromium 85 snapshot (`chromium-browser-snapshots/Mac/782078`, Intel, runs
under Rosetta), headless at 1920x1080 against `?tv=1` with a FRESH profile each
run (a reused one serves the old stylesheet from the service worker), reading
`Runtime.exceptionThrown`. Every route should draw with no exceptions.

## 3. Packaging

```bash
./tv/build-tv-packages.sh tizen     # stages the shared app + config.xml + icon
# then, with Tizen Studio CLI installed:
tizen build-web   -- tv/tizen/app
tizen package -t wgt -o tv/dist -- tv/tizen/app/.buildResult
```

**⚠️ Keep the signing certificate.** Samsung requires every future update to be
signed with the *same* certificate. Losing it means the app cannot be updated —
back it up somewhere durable, outside the repo.

`tv/tizen/config.xml` already declares the TV profile, landscape orientation,
`hwkey-event` handling, and the `tv.inputdevice` privilege the media keys need.

---

## 3b. What a TV build must NOT carry

The shared web app advertises the other platforms — a "Get the app: Apple TV ·
Android & Google TV · Fire TV" footer on every screen, and App Store / Play /
Amazon buttons on About. On the website that is the point; inside the `.wgt` it
is two problems: every TV store's guidelines object to an app linking to a
COMPETING store, and the links cannot work anyway, because a packaged TV app has
no browser to hand off to. `tv.css` hides them on TV only (measured: three
focusable controls removed from the D-pad's path). About & attribution, Privacy,
Terms and the archive.org donate link all stay — the first is required by TMDb's
terms and the last is not a store.

## 4. Store listing

Paste-ready. Every number here is MEASURED against the published catalog
(`ops/pulse.json` → `health.catalog`, and the live `catalog-index.json`) as of
2026-10-03 — re-check before submitting rather than trusting these:
**24,274 items, 24,018 playable, 284 television series** (the rights audits
of Decisions 140/151/157/159 removed ~2,400 since 2026-09-10).

**Name:** Archive Watch

**Category:** Video / Entertainment

**Short description** (one line)
> Watch the public domain — classic films, silent cinema, animation and
> vintage television, free from the Internet Archive.

**Long description**
> Archive Watch turns the Internet Archive's moving-image collection into
> something you can actually browse from the couch: more than 24,000 films and
> television episodes, free to watch, with no account and no advertising.
>
> Feature films, silent cinema, classic television, animation, newsreels and
> the strange world of ephemeral and educational film — presented with posters,
> cast, synopses and genres, so a 1920s serial is as easy to find as a
> well-known title.
>
> • Browse by category, decade, genre, studio or keyword
> • 284 classic television series, with seasons and episodes
> • Channels — a continuous TV-style guide you can tune into
> • Surprise Me, for when you would rather be shown something
> • Pick up where you left off, and keep a library of favorites
> • Subtitles where they exist
>
> Every title is public domain or otherwise free to share. Archive Watch is
> free, has no ads, no
> subscription and no account, and it does not collect anything about you.

**Keywords:** public domain, classic film, silent film, old movies, classic TV,
free movies, cinema, film noir, animation, documentary, Internet Archive

**Age rating:** general audiences. Mature collections are filtered out of the
served catalog entirely on this platform — the index a TV reads never contains
them (Decision 105), so there is nothing to un-hide.

**Support:** archivewatch.org/support · **Privacy:** archivewatch.org/privacy ·
**Terms:** archivewatch.org/terms

**Screenshots:** Home, Browse, a title page, Channels, and playback. Samsung's
required dimensions differ from LG's and change — read the current requirement
in Seller Office at upload time rather than trusting a cached number here.

**What is NOT claimed, deliberately:** no "thousands of HD titles" (much of this
catalog is a 16 mm scan and looks it), no "new releases", and no count that
rounds up. The archive's appeal is that it is an archive.

---

## 5. Owner steps

| # | Step |
|---|---|
| 1 | ~~Decide: US-only Public Seller, or pursue Partner~~ **DECIDED 2026-09-10 — Public Seller, US-only** (§1) |
| 2 | Create a free **TV Seller Office** account |
| 3 | ~~Install Tizen Studio CLI and create a signing certificate~~ **DONE 2026-09-09** — see `docs/tizen-signing.md`. The certificates are at `~/SamsungCertificate/archivewatchSamsung/` and **must be backed up somewhere durable**: Samsung requires every future update to be signed with the same one, and the distributor cert is tied to the DUIDs listed in it (a second test TV means re-issuing) |
| 4 | ~~build + package~~ **DONE** — `TIZEN_PROFILE=archivewatchSamsung bash tv/build-tv-packages.sh tizen` produces a signed `tv/dist/ArchiveWatch.wgt` |
| 5 | ~~Enable Developer Mode and side-load~~ **DONE** — verified installed and launched on a QN65S90CDFXZA (2023 S90C, Tizen 9.0) at 10.0.0.203 |
| 5b | **Confirm the side-loaded app actually shows films before submitting.** A packaged app runs from `file://`, where a relative data URL resolves inside the package instead of to the server — fixed 2026-08-05, but invisible in the browser build. An empty Home means the data plane regressed; `node tools/test_packaged_origin.mjs` guards it |
| 6 | ~~Submit through Seller Office~~ **SUBMITTED 2026-10-03**: v1.45.10, app id 3202610049114, 45 model groups 2022-2026 (incl. 4 licensed `_LIC`), 12+, free. Expect ~1–2 weeks and possibly several cycles |

**Seller Office traps met on the first submission** (2026-10-03): the pre-test
refuses a package naming no screen size (`config.xml` now declares
`screen.size.normal.1080.1920`); tags take single words only; every section's
Save must be left to finish (navigating away mid-upload silently dropped the
screenshots); the screenshot slots share ONE file input, chosen by the slot's
edit icon; the App Description File is Samsung's PowerPoint template, filled
copy at `tv/dist/store/ArchiveWatch_App_Description_v1.45.8.pptx` (regenerate
it for the next version).
