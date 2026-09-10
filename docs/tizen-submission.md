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
| Launches without error | **Not verified on the panel** | It installs and launches (`tizen run` reports the pid), but retail Tizen closes `sdb shell` entirely — no console, no screenshot, no dlog — so nothing here has SEEN Home render on the TV. `tools/test_packaged_origin.mjs` (23) guards the known cause of an empty Home, including that every script index.html loads is actually in the package. **Owner: confirm films appear before submitting** |
| Full D-pad operability | Pass, **re-verified 2026-09-10** | The August claim of "9 surfaces verified" was **wrong** and this is what it cost: the Home HERO had no focusable element at all (the marquee, unreachable), and Browse's four filters were focusable but DEAD because tv.js ran spatial navigation on every arrow without checking what had focus. Both measured on the live site, both fixed, both now covered by `tools/test_tv_focus.mjs` (32 cases) with controls |
| Focus always visible | Pass | Ring + scale + elevation, never colour alone |
| **Back / Return behaviour** | Pass | Layered — an open player closes before any navigation; exits at the root via `tizen.application…exit()` |
| Media keys | Pass | Registered through `tizen.tvinputdevice.registerKey()` — **Tizen does not deliver them otherwise** |
| Playback | Pass | Progressive H.264 MP4 over HTTPS; no DRM needed |
| Subtitles | Pass | WebVTT via `<track>`, user-selectable |
| Suspend / resume | Pass | `visibilitychange` pauses; focus re-claimed on return |
| Overscan | Pass | 5% safe insets; no text at the panel edge |
| Ten-foot legibility | Pass | 24px body, 20px for a card's year caption, 32-64px headings — all tokens in `tv.css`, none a loose literal |
| No account / payment | Pass | No sign-in, advertising, or purchases |
| Content rights | Pass | Public-domain / CC only — see `docs/webos-submission.md` §4 |

The remote-driven walkthrough Samsung may ask for is the same as
`docs/webos-submission.md` §1; the app behaves identically.

---

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
2026-09-10 — re-check before submitting rather than trusting these:
**26,711 items, 26,423 playable, 285 television series.**

**Name:** Archive Watch

**Category:** Video / Entertainment

**Short description** (one line)
> Watch the public domain — classic films, silent cinema, animation and
> vintage television, free from the Internet Archive.

**Long description**
> Archive Watch turns the Internet Archive's moving-image collection into
> something you can actually browse from the sofa: more than 26,000 films and
> television episodes, free to watch, with no account and no advertising.
>
> Feature films, silent cinema, classic television, animation, newsreels and
> the strange world of ephemeral and educational film — presented with posters,
> cast, synopses and genres, so a 1920s serial is as easy to find as a
> well-known title.
>
> • Browse by category, decade, genre, studio or keyword
> • 285 classic television series, with seasons and episodes
> • Channels — a continuous TV-style guide you can tune into
> • Surprise Me, for when you would rather be shown something
> • Pick up where you left off, and keep a library of favourites
> • Subtitles where they exist, and automatic captions on supported devices
>
> Everything here is in the public domain in the United States or released
> under a Creative Commons licence. Archive Watch is free, has no adverts, no
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
| 6 | Submit through Seller Office; expect ~1–2 weeks and possibly several cycles |
