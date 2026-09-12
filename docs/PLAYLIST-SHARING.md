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
