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
| Launches without error | Pass | Cold launch to Home |
| Full D-pad operability | Pass | 9 surfaces verified by automated focus trace |
| Focus always visible | Pass | Ring + scale + elevation, never colour alone |
| **Back / Return behaviour** | Pass | Layered — an open player closes before any navigation; exits at the root via `tizen.application…exit()` |
| Media keys | Pass | Registered through `tizen.tvinputdevice.registerKey()` — **Tizen does not deliver them otherwise** |
| Playback | Pass | Progressive H.264 MP4 over HTTPS; no DRM needed |
| Subtitles | Pass | WebVTT via `<track>`, user-selectable |
| Suspend / resume | Pass | `visibilitychange` pauses; focus re-claimed on return |
| Overscan | Pass | 5% safe insets; no text at the panel edge |
| Ten-foot legibility | Pass | 24px body minimum at 1080p |
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

## 4. Store listing

Same copy as `docs/webos-submission.md` §3. Samsung's screenshot dimensions
differ from LG's — check the current requirement in Seller Office at upload
time rather than trusting a cached number.

---

## 5. Owner steps

| # | Step |
|---|---|
| 1 | **Decide: US-only Public Seller, or pursue Partner for global** (§1) |
| 2 | Create a free **TV Seller Office** account |
| 3 | Install Tizen Studio CLI and create a signing certificate — **back it up** |
| 4 | `./tv/build-tv-packages.sh tizen`, then build + package (§3) |
| 5 | Enable Developer Mode on a Samsung TV (it is keyed to the TV's IP) and side-load |
| 6 | Submit through Seller Office; expect ~1–2 weeks and possibly several cycles |
