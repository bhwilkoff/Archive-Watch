# Sharing a playlist by URL — the investigation

*2026-09-12. Owner: "letting our users share their playlists via URL … they
would get published on the web app for anyone to browse and potentially add to
their account and view them on native apps as well."*

## The constraint that shapes everything

This project has **no backend and no user accounts** (Decisions 009 and 028).
Library state lives on the device and syncs through the viewer's OWN cloud —
CloudKit for Apple, Google Drive appData for Android and web (Decision 102).
There is nowhere to PUT a playlist that we host, and standing one up would
undo an architectural decision the whole project rests on.

So the first question is not how to build a sharing service. It is whether one
is needed at all.

## It is not: the playlist fits in the link

A playlist is `{id, name, archiveIDs[]}` — ordered archive ids and a name. Those
ids are short: median 23 characters across the 31,832 visible items. Deflated
and base64url'd, the whole playlist travels inside the URL.

MEASURED (300 random draws per size, against the live catalog):

| Titles | median URL | p95 | max | verdict |
|---|---|---|---|---|
| 10 | 372 | 444 | 538 | fits easily |
| 25 | 756 | 887 | 970 | fits |
| 50 | 1,368 | 1,542 | 1,699 | fits |
| 75 | 1,948 | 2,163 | 2,268 | tight |
| 100 | 2,535 | 2,759 | 3,022 | over |

A realistic 25-title playlist drawn from POPULAR films — what people actually
make — is **655 characters**, because well-known titles have shorter ids.

~2,000 characters is the practical ceiling (IE's old 2,083 limit is long gone,
but chat apps, QR codes and email clients all start mangling links past about
that). **So a self-contained link works to about 50 titles**, which covers the
overwhelming majority of real playlists, and the app can say plainly when a
playlist is too long to share rather than silently truncating it.

## What that buys, beyond costing nothing

* **No server, no database, no account** — nothing to run, nothing to bill.
* **No moderation surface.** We never host user content, so we are never asked
  to police it. For an app whose whole claim is careful curation of public
  domain film, that is worth more than the feature.
* **No link rot.** The link keeps working as long as archive.org has the films;
  it cannot be switched off, and it survives this project entirely.
* **No privacy exposure.** A shared playlist reveals nothing about who made it,
  because there is no account behind it.

## What it does NOT buy, and this is the real gap

The owner asked for playlists "published on the web app for anyone to
**browse**". A link is not a directory: you can only open one if somebody sent
it to you. Discovery needs a published list, and a published list needs either a
backend or a curation step.

The curation step already exists in this project's shape. `featured.json` is
hand-curated and baked into the static site; the editorial tool at `/curate/`
edits it. A viewer who wants their playlist PUBLISHED submits it, and a workflow
bakes it into the site as a static page. That keeps the no-backend rule, keeps a
human between a stranger and our front page, and makes publication an editorial
act rather than an upload.

## Suggested staging

1. **Share by link** (web only). A `#/list/<blob>` route that decodes and
   renders, and a "Share playlist" action that produces the URL. No app release
   needed; works for everyone the day it deploys, including on the TV browsers.
2. **Import on native.** The apps already hold `applinks:archivewatch.org`, and
   the AASA file is served by us — adding `/list/*` to it needs no app release,
   but HANDLING the URL does. So this rides the next natural submission.
   Android needs a manifest intent-filter path, which is also an app release.
3. **Publish, opt-in.** A submission that a workflow bakes into the site, giving
   a browsable directory without hosting anything user-writable.

## What is NOT decided

Whether step 3 is wanted at all. It is the only part that needs ongoing human
attention, and the first two steps deliver "share my playlist with someone"
completely on their own.

---

## Handing the link over on a television (2026-09-12)

A TV has neither route the phone and desktop builds use. `navigator.share`
does not exist on Tizen or webOS, and `navigator.clipboard` is worse than
useless there — the viewer has nothing to paste into and no way to get a link
off the set. Until this landed, pressing Share on a television either copied
to a clipboard nobody could read or fell through to "Could not make a link".

So the web-TV build draws the link as a **QR code** (the owner: share
playlists "from all native apps and have them publish to a archivewatch.org
link that can be shared (QR codes for TV-based native apps)").

**The encoder lives in `tv.js`, not a new file.** A root file has to be listed
in `index.html`, the `sw.js` shell, and both TV packagers — four places to
forget, and forgetting one is exactly how `cast-sender.js` shipped unstaged.
`tv.js` is already in all of them and already returns immediately on a phone.

**It is a port of `roku/components/QR.brs`, extended from versions 1-10 to
1-40.** Ten was nowhere near enough, and the measurement is the argument —
against REAL catalogue ids rather than synthetic ones:

| films | share URL | QR version |
|---|---|---|
| 1 | 116 chars | v6 |
| 5 | 219 | v9 |
| 10 | 348 | v12 |
| 20 | 548 | v16 |
| 35 | 846 | v20 |
| 50 (the cap) | 1,048–1,328 | v23–v27 |

v10 tops out at 271 bytes, so the original encoder could only ever have drawn
a **one-to-three film** playlist. Everything else would have hit the "too long
to encode" path.

**The version and alignment tables are machine-generated** from an independent
reference, not transcribed — because transcription is how the bug below got
in. Version-info bits are computed (BCH(18,6)) rather than tabulated.

### The bug this found in shipped code

`QR.brs` listed v10's alignment centres as `[6, 28, 52]`. The spec says
**50** — the third centre advances by exactly 4 per version (38/42/46/50).
Every version-10 code the Roku channel ever drew was malformed: the pattern
landed two modules off and no scanner could read it. It went unnoticed because
v10 needs 232+ bytes and the only thing that encoder draws is an `/item/`
share URL of about 50. Fixed in both encoders.

### How it is proven

Two independent ways, because a broken QR code looks exactly like a working
one — every failure mode produces a clean square of noise.

1. **Structure** (`tools/test_tv_qr.mjs`, 84 assertions). For each of 40 golden
   vectors, exactly ONE of the eight masks must reproduce the reference matrix.
   That proves the bit stream, Reed-Solomon ECC, block interleave, function
   patterns, data placement, format info and every mask — *independently of
   which mask the penalty picks*, which is a heuristic no two implementations
   agree on. Each vector is sized to its version's exact EC-L capacity, so the
   version chosen must be the version expected, which is what catches a wrong
   row in the table. Checked to FAIL against three planted bugs: the v10
   alignment typo (1 failure), a format-info axis swap (40), a wrong ECC count
   (1).
2. **Decode.** The rendered sheet is screenshotted at 1920x1080 and the code
   read back out of the screenshot with Vision — the same bar the BrightScript
   encoder was held to. A 50-film link round-tripped exactly: real catalogue
   ids → share encode → URL → QR → canvas → screen → camera → the identical
   1,048 characters.

### Two things only the glass showed

- **A 1,048-character URL printed in full overflowed the panel and pushed the
  only button off the bottom of the screen.** Nobody types a thousand-character
  URL, so the link is now shown in words only when it is short enough to key in
  with a remote (120 chars); past that the sheet says the code carries it.
- **A flex column with a `max-height` SHRINKS its children**, which clipped the
  remaining copy to half a line — the panel fitted and its contents did not.
  Nothing in the sheet may shrink; the code is sized to the room that is left
  instead, measured from the viewport. The panel caps at **86vh, not 92**,
  because a television overscans ~5% a side and that last row is the button.

Cost is not a concern: 2.6 ms to encode the realistic worst case and 4.8 ms for
a v40, on a button press rather than at boot.

### Still open

**Roku cannot share a playlist at all yet.** Its QR encoder is now correct but
still v1-10, and BrightScript has no deflate — the share format carries an
uncompressed `0`-prefixed variant precisely so a Roku can encode one, which
makes its links *longer* than everyone else's. Playlist sharing from Roku needs
the same v11-40 extension ported back, and that is a separate piece of work.

---

## Roku shares playlists too (2026-09-12)

Library → `*` on a playlist row → **Share this playlist** draws the code, with
the same 50-title cap as every other platform and a header that says so when
the list was clipped ("Sharing the first 50 of 70") — a viewer must learn that
here, not on their phone.

**BrightScript cannot deflate**, which is exactly why the format defines the
`0`-prefixed UNCOMPRESSED variant. The consequence is real: Roku's link is the
longest any platform emits, roughly 2.5x the deflated one, which is what made
extending the encoder past v10 a prerequisite rather than a nicety.

**Proven end to end on the glass** (Streaming Stick 4K, 15.3.4), 10 real films:

| step | evidence |
|---|---|
| device builds the link | `AWSHARE playlist shown=10 total=10 len=449` |
| device encodes it | `AWQR v14 size=73 mask=4` |
| the JS encoder agrees | v14, 73x73, **mask 4** — independently chosen |
| the code is readable | decoded from the device SCREENSHOT: 449 chars, exact |
| the web can read it | `watch.js` ShareList.decode → "creature feature", 10 ids |

The mask agreement is the strong part: mask selection scores all eight
candidates over the whole matrix, so two implementations landing on the same
one is evidence the matrices are identical — and v14 is the first time
BrightScript has ever run the 16-bit character count, the two-block-group
interleave, or the computed BCH version info.

### Cost, measured, because the Roku 2 XD is a supported device

`AWQRPng` now reports `encodeMs` and `totalMs`. First measurement at v14 was
**594 ms encode + 2,048 ms PNG = 2,642 ms** — visible as a hang. Two fixes:

- **One scanline per MODULE row, repeated `scale` times.** The pixel rows
  inside a module row are byte-identical, so building each separately did the
  same work `scale` times over.
- **The scale is DERIVED from the display box** (`AWQRBox()` = 520), not passed.
  It was generating 648 px to display 392. Deriving it also makes the cost FALL
  as the version rises — more modules pack into the same box at a smaller scale
  — which is what keeps a 50-film code drawable on an old player.

Result at v14: **2,642 ms → 1,131 ms**, and the code now arrives at very close
to its display size, so Roku's bilinear scaler has almost nothing to blur.

**Still a risk, not yet addressed**: a full 50-film playlist is v23–v27, where
the mask penalty alone should run ~1.7 s on this Stick and several times that on
a Roku 2 XD. The real fix is to move the encode off the render thread into a
Task node with a "preparing" state; it is a bigger change than this pass and is
the next thing to do if anyone reports a slow card.

### A BrightScript trap worth the line

`box = AWQRBox()` is a **compile error**: `Box()` is a BrightScript builtin (it
boxes an intrinsic), so a local of that name is refused. Same family as `rem`
being the comment keyword, already recorded in `QR.brs`. It fails at compile
time, which is the good case.

---

## The link shape, settled (2026-09-12)

A share link is now:

    https://archivewatch.org/list/#<blob>

not `archivewatch.org/#/list/<blob>`. Three requirements pull in different
directions and only this shape satisfies all of them.

**The playlist must not reach a server.** A browser never sends a fragment, so
`#<blob>` keeps the list on the device — the same property the whole no-backend
design rests on (Decisions 009/028), and the reason the first version put it
there.

**A native app must be able to match it.** This is what the fragment alone
cannot do. An **Android intent filter matches the PATH** and cannot see a
fragment at all, so `/#/list/<blob>` could never open the Android app — its
path is just `/`. Apple is more capable: AASA gained a `#` component key in
iOS 13, so Apple could match either. A single link has to serve both, so the
path is where the routing information has to live.

**It must preview.** GitHub Pages serves `404.html` with an HTTP **404**, and
several crawlers decline to preview a 404 outright — which is the entire reason
26,000 per-item share pages exist (see the top of `tools/build_share_pages.py`).
A playlist link is made to be posted to Reddit and to social, so it cannot be a
404. `/list/` is now a real generated page: one static file, generic preview
copy, and a script that reads the fragment and hands it to the viewer's router.
The copy is generic **on purpose** — the contents are in a fragment the
generator never sees, which is exactly the property being preserved.

`404.html` handles `/list/` as well, as the safety net for the window before
the page deploys and for a link written with the blob in the path instead. The
deploy refuses to ship without `_site/list/index.html`.

**Old links keep working.** `#/list/<blob>` still decodes and routes on every
platform; links are permanent and some are already in the wild.

### Verified, end to end, on the device

Roku 1.0.71 on a Streaming Stick 4K, a ten-film playlist:

    AWSHARE open len=448  https://archivewatch.org/list/#0eyJpIjpb...
    AWQR v14 size=73 mask=2  encodeMs=616 totalMs=1173

decoded out of a photograph of the TV screen to the exact 448 characters, and
that string fed to `watch.js`'s own `ShareList.decode` returned "creature
feature" and all ten ids. The web forward was measured too: `/list/#<blob>`
lands on `#/list/<blob>` with ten cards and the right title, and the old shape
still does the same.

### What is NOT done, and the order it has to happen in

**The AASA and the Android manifest are deliberately unchanged.** Adding
`/list/*` to them today would make iOS and Android intercept a shared playlist
and open an app that does not know the route — landing the viewer on Home with
their link gone, which is strictly worse than the web page they get now. The
order is: teach the apps the route, ship them, *then* declare the path. The
link shape is the part that had to come first, because links are permanent and
every one shared from today is already the right shape.

---

## All three Apple platforms open a shared link (2026-09-12)

`SharedListView` exists for tvOS, iOS and macOS. Each renders the collection
the link carries, with the same two rules the owner set for the web:

* **Browse and play for anyone.** Signed in or not, the films are there and
  they play. Nothing is withheld from a stranger, because nothing here is ours
  to withhold.
* **Adding it is a choice**, never a side effect of opening a link. The app
  could copy the playlist into the library and land the viewer in it — fewer
  taps, and wrong: a link tapped out of curiosity would have edited their
  library. "Already in your library" is matched on CONTENTS rather than name,
  so the same collection sent under two names does not become two copies.

A title the link names that this catalogue no longer serves is STATED
("8 of 10 titles — 2 are no longer in the catalogue"), never silently dropped,
or the sharer and the viewer are looking at different collections and neither
can tell.

**Verified on the glass, all three**, each with a link produced by `watch.js`'s
own encoder and opened through the platform's real URL entry point:

| Platform | Device | What it showed |
|---|---|---|
| tvOS | Bedroom Apple TV | SHARED PLAYLIST · creature feature · Play All · Add to my library · 3 titles |
| iOS | iPhone 12 | creature feature · Shared playlist · 3 titles · ＋ in the toolbar |
| macOS | this Mac | creature feature · Shared playlist · 3 titles · Add to my library |

The parse happens BEFORE each platform's `archivewatch://` scheme check, on
purpose: a share link is an ordinary https url, because the whole point is that
it opens for somebody with no app at all.

### A correction

An earlier note here said macOS could not be built on this Mac because its beta
OS did not match the app's supported platforms. That was wrong — it was the
wrong SCHEME. The Mac app is a separate target with its own scheme,
**`Archive Watch Mac`**; `ArchiveWatch` is tvOS and iOS only, which is exactly
what its `SUPPORTED_PLATFORMS` says. All three build here.

### THE AASA IS STILL NOT DECLARED, and this is the last gate

`/list/*` must be added to `.well-known/apple-app-site-association` and to the
Android manifest ONLY AFTER the apps that handle it are in people's hands. The
file is served by us and takes effect the moment it deploys — so declaring it
while the shipped app is the current one would intercept every shared playlist
and open an app that does not know the route, landing the viewer on Home with
their link gone. That is strictly worse than the web page they get today.

The order is: ship the apps, confirm the release is live, then declare the
path. Until then a shared link opens the web viewer on every device, which
works.
