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
