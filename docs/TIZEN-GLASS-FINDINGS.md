# What the TV actually shows — 2026-09-10

The owner tested the side-loaded build on a QN65S90CDFXZA and reported that a
lot of it is broken. They are right, and the reason it took a person to find it
is recorded here so it does not happen again.

## The methodology failure

Everything before this was measured in a desktop Chrome window **at 1456×770,
with a mouse**, and called TV testing. Two things were wrong with that:

* This Mac's display is 1512 CSS px wide at `devicePixelRatio` 2, so a true
  1920×1080 CSS viewport **cannot be opened on it at all**. Every layout reading
  all session was taken at three-quarters of TV width.
* A mouse can reach anything. A remote reaches only what the focus engine finds,
  in the order it finds it, by pressing a direction. That is why a hero with no
  focusable child and four dead filters both passed a "check" and failed on the
  owner's television.

`tools/tv_glass.mjs` replaces it: headless Chrome has no physical display, so it
renders a real 1920×1080, and input goes through `Input.dispatchKeyEvent` — a
genuine key event, not `el.focus()` and not a synthetic click, both of which lie
about reachability. It screenshots after every press and prints where focus went
and whether it was **on screen**.

## Reproduced and FIXED

**The page did not follow the highlight on Home.** `body` is a flex column with
`overflow:hidden`, so `<main>` scrolls and the footer is a sibling pinned below
it, permanently visible. Geometrically the footer is therefore the nearest thing
below *every* row, so Down from the category tiles jumped to "About &
attribution" and the page never scrolled. Not a Home bug — what a pinned element
does to a spatial engine on any surface. A move now prefers a target in the same
scroll container and only leaves it when that direction is genuinely exhausted.

Measured before: Down → footer at step 4, one press off screen. After: twelve
presses walk shelf to shelf, `scrollTop` 0 → 4182, focus held at a steady y=616,
every element visible.

## Reproduced and NOT fixed — the player needs rebuilding, not patching

Captured at 1920×1080 (`/tmp/aw-player2/05-Enter.png`):

* **`<video controls>` renders the BROWSER's control bar** — pause, `0:00`,
  volume, fullscreen, a ⋮ menu. That is the owner's "controls that only work for
  a desktop web browser", and it is literally true: those are Chrome's widgets.
  A TV needs its own transport, driven by the D-pad.
* **The player is a `<dialog>` with desktop chrome** — a title bar carrying a
  PiP button, "Cast" and an ✕. None of those belong on a television.
* **The synopsis is painted permanently over the top quarter of the picture.**
* **The video frame is not sized to the screen.**
* Pressing OK on Play focused the **PiP button**.

## Reproduced and NOT fixed — Detail

* **Down from the nav lands on Share, not Play.** The primary action must be
  where the remote arrives, not wherever geometry puts it.
* **The synopsis runs off the right edge** at 1920 — no max width.
* Poster, cast chips and body text are desktop-sized at ten feet.

## HOW TO READ THE PLAYBACK FAILURE ON THE TELEVISION

Press **Up Up Down Down** on the remote, within five seconds, at any time. An
overlay appears in the top-left and prints the media pipeline's own events. The
same sequence hides it.

While a film plays it logs every media event plus a five-second heartbeat:

    16:17:20.342  play     t=0.0  buf=75.7 rdy=METADATA net=IDLE
    16:17:25.361  tick     t=4.9  buf=75.7 rdy=ENOUGH   net=IDLE
    16:17:30.402  stalled  t=9.8  buf=9.9  rdy=CURRENT  net=LOADING

`rdy` is readyState, `net` is networkState, `buf` is the end of the buffered
range, and an `ERR=` appears with the code and message if the element errors.

**What to look for when it stops after a few seconds** — these are different
bugs and the readout separates them:

| What the last lines show | What it means |
|---|---|
| `ERR=4` / `net=NO_SOURCE` | the TV refused the file — codec or container |
| `stalled`/`waiting`, `buf` stops growing | the network died or archive.org cut it |
| `buf` large, `rdy` drops, no event | the TV's decoder gave up — a platform fault |
| silence: no tick at all | the app or the page was killed (memory) |

The sequence needs a reversal on the same axis, so it cannot be entered by
accident while browsing, and it needs no extra keys registered.

## Cannot be investigated from here

**"Videos play for a few seconds and stop."** This is Tizen-specific: playback
is fine in Chrome. Retail Samsung TVs close `sdb shell` entirely — no console,
no screenshot, no dlog (see `docs/tizen-signing.md`) — so there is no way to
observe the failure on the device. Options, in order of cost: an on-screen debug
overlay built into the app itself (the shape `FunctionalAudit.swift` uses on
tvOS); a developer/UD unit, which does expose the Web Inspector; or Samsung's
own remote-test service.

## The conclusion the owner already reached

This is a web page shown on a television, not a television interface. The web
app was the right way to REACH the platform and is the wrong thing to ship
unchanged. What is needed is a TV-first pass over the player and the Detail
surface, not more patches to a browser layout.

---

## The .wgt actually built and run (2026-09-12)

Everything before this was measured in desktop Chrome at 1920x1080 with
`?tv=1`. That is the right harness for layout, and it is not the deliverable.
The deliverable is a signed `.wgt` running at a `file://` origin.

**Built and signed**: `tizen build-web` + `tizen package -t wgt`, profile
`archivewatchSamsung`, → `tv/dist/ArchiveWatch.wgt` (3.2 MB, 20 files). Version
stamped **1.42.65** from AppVersion.xcconfig by the build script — the
`config.xml` in the repo still reads 1.3.284 and is a template, not the
shipped value. The filename has no space, which the script enforces.

**Booted at `file://` with a Tizen user agent** (the origin and UA a widget
actually runs at, not a localhost server):

    html classes      tv tv-tizen        <- the TV layer detected the platform
    cards rendered    348
    blank tiles       0                  <- the placeholder fix, in the package
    AWTV.shareQR      true               <- the QR seam is in the package

### What that found: the Cast SDK fetches itself protocol-relative

    net::ERR_INVALID_URL  <-  file://www.gstatic.com/cast/sdk/libs/sender/1.0/cast_framework.js

Our own tag was always absolute https, and the comment beside it said so and
was right. The failing request is **Google's**: once `cast_sender.js` is
running it fetches its own framework with a protocol-relative `//www.gstatic.com/...`,
which at a `file://` origin resolves to `file://www.gstatic.com/...` and fails
on every launch. It is inside their script and cannot be corrected from here.

The fix costs nothing: **a television is never a Cast SENDER.** Senders are
Chrome and Android, casting *to* a receiver. So the sdk is injected rather than
`<script>`-tagged, and the injector returns early on a `file://` origin or a
Tizen/webOS/VIDAA user agent. Verified both directions — the failed request is
gone from the package, and on the web `cast.framework` is still present.
`tools/test_packaged_origin.mjs` guards it (checked to FAIL against the static
tag restored).

### The one remaining console line, and why it is not a defect

    401  <-  api.apple-cloudkit.com/.../public/users/caller

CloudKit JS asking "is anyone signed in?" for an anonymous caller. A 401 is the
answer to that question, not an error. It fires once per launch.

### Still not done on the glass

This is a packaged app booted in Chrome at the right origin with the right user
agent — it is not a Samsung TV. What it cannot tell us: real remote key codes
from the platform, Tizen's own media pipeline, memory under a long session, and
how the panel actually renders overscan. Those need the set.

---

## What a RETAIL Samsung set actually exposes (2026-09-12)

Measured against the owner's QN65S90CDFXZA (2023 S90C, Tizen 9.0) at
10.0.0.203, connected over `sdb`:

| | |
|---|---|
| `sdb connect` | ✅ |
| `sdb capability` | ✅ (31 fields — profile `tv`, platform 9.0) |
| `tizen install` | ✅ (7.8 s for the 3.2 MB .wgt) |
| `tizen run` | ✅ (returns a pid) |
| `sdb shell` | ❌ silent |
| `dlog` | ❌ silent |
| `sdb pull` | ❌ "You cannot pull files from this path" |
| screenshot | ❌ (needs shell) |
| web inspector | ❌ — see below |

**There is no web inspector, and that is the one worth writing down.** The
inspector needs the app launched under `sdb shell 0 debug <appid>`; `tizen run`
launches with `debug 0` and the CLI has no `debug` subcommand at all
(`tizen --help` lists 19 commands; none of them is one). So the DOM-measurement
route — the thing that makes headless Chrome such a good instrument for this
app — is closed on the television itself.

### What that means for how this app is verified

A build can be **deployed and launched** from here, and cannot be **observed**.
So the division of labour is:

* `?tv=1` in a 1920x1080 headless Chrome is the INSTRUMENT —
  `tools/tv_audit_sizes.mjs` (type floors, overlapping and squeezed text),
  `tools/tv_follow_focus.mjs` (the selection inside the overscan-safe band),
  and the packaged `file://` run above (the origin and user agent a widget
  really has).
* The television is where a PERSON looks.

`tools/tizen_deploy.sh` does the deploy half in one command, and carries this
table in its header so the next session does not spend twenty minutes
rediscovering it.

**The set is running 1.42.72** — every fix from today: the six kinds of
web-sized type, the EPG rebuilt for TV type, the typographic placeholder that
45% of the catalogue needed, the footer and brand overscan insets, and the QR
share sheet.
