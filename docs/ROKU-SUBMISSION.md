# Submitting Archive Watch to the Roku Channel Store

## The headline: there is no submission API

Every other store in this project is scripted — `tools/asc_release.py` submits
to Apple over REST (Decision 101), `tools/submit-play.sh` uploads to Google
Play. **Roku has no equivalent.** App creation, the store listing, the package
upload, the self-serve tests and the publish schedule all happen by hand in the
Developer Dashboard. Roku's own publishing guide documents no programmatic
path, and there is no partner endpoint to fall back on.

What IS scriptable is producing the artifact, and `tools/roku_package.py` does
that end to end: check the key, sideload, ask the device to sign, download the
`.pkg`.

## The signing key — read this before running anything

The key lives **on the Roku device**, not in this repo. It is minted once:

    telnet 10.0.0.155 8080
    genkey

That prints a developer ID and a **password that must be kept forever**. Every
future update to the published channel must be signed with the same key. Lose
the password and the only recovery is *Rekey*: uploading an old package and its
password to re-key a device.

`roku_package.py` deliberately does NOT run `genkey`. Re-running it REPLACES
the existing key and orphans every package signed with the old one — a tool
that can silently make a shipped channel un-updatable is not worth having.

**Current state: `showkey` reports `Dev ID: <unkeyed>`.** Nothing has been
minted yet, so this is the one action waiting on the owner. Store the password
the way the Android upload keystore is stored — outside the repo, never in git.

## Where we stand against Roku's certification criteria

Measured on the Streaming Stick 4K, not estimated.

| Requirement | Threshold | Us | |
|---|---|---|---|
| Launch to a rendered home screen | ≤ 15 s | **2.5–3.0 s** | ✅ |
| Scene-to-scene transitions | ≤ 3 s | **0.09–0.20 s** | ✅ |
| Remote response / tile navigation | ≤ 250 ms | **median 70 ms, worst 132 ms** (2026-09-04, after §13: bundled fonts + a twelve-Poster frame on every tile) | ✅ |
| Video starts after initiation | ≤ 8 s | **2.2–6.4 s** across 24 films | ✅ |
| Package size | ≤ 4 MB | **1.43 MB zipped** (2.2 MB on disk; 516 KB of that is six bundled font faces) | ✅ |
| Design gate (ROKU-DESIGN §13.11) | our own | `tools/roku_design_lint.py` — 0 findings across 32 components | ✅ |
| Functional gate | our own | `tools/roku_audit.py` 34/34; both Select sweeps clean | ✅ |
| Back returns to the previous screen | required | every surface; Back at Home exits to Roku | ✅ |
| Instant Replay rewind | 10–25 s | **15 s** | ✅ |
| Does not override the system screensaver | required | draws none (ROKU-DESIGN §11) | ✅ |
| Deep linking, all media types | required | `contentId` + `mediaType`, cold and warm | ✅ |
| Direct to Play on a voice launch | required | `mediaType=movie` plays immediately | ✅ |
| Captions honour the device setting | required | device mode read, never overridden | ✅ |
| Loading indicator for waits > 3 s | required | catalog load only; other waits are sub-second | ✅ |
| **Trick-play thumbnails, VOD > 15 min** | **required** | 16,741 published on `archivewatch-bifs`; **16,460 of the served items now carry the schema-12 `bif` column the channel reads** (it had none until 2026-09-08, so not one BIF was ever offered) | ✅ **VERIFIED ON THE DEVICE** |

## The one blocker: BIF trick-play thumbnails — now MEASURED

Roku certification requires trick-play thumbnails for VOD over fifteen
minutes; nothing in the catalog has one. The earlier estimate ("~200 GB
across 26,960 items, a real pipeline programme") was reasoning, not
measurement. On 2026-09-04 one real BIF was generated and measured:

    film        El Candidato (1959), 94 min, archive.org progressive MP4
    method      ffmpeg -skip_frame nokey, streamed over HTTP (no download),
                fps=1/10, scale=320:-2, JPEG q=6; packed per the BIF spec
                (magic, v0, N, 10 000 ms multiplier, N+1 index, frames)
    frames      560 at 320 x 252
    time        21 s wall clock on the dev Mac, network-bound
    size        2.55 MB

Extrapolated honestly (a 94-minute feature is on the long side of this
catalog; shorts and newsreels are far cheaper):

    storage     ~2.5 MB x 26,960 = ~69 GB for HD (320 px); ~35 GB at SD
                (240 px). Hosted the way the frame covers are — one
                archive.org item, `archivewatch-bifs/<id>.bif` — that is
                free and on-brand (Decision 023).
    compute     ~21 s x 26,960 = ~157 machine-hours, network-bound and
                embarrassingly parallel: 26 six-hour GitHub Actions jobs, or
                a weekend on one Mac. Resumable via a manifest like
                batch_covers.py.

**And it works on the device.** The same file, served from the dev Mac and
attached through the harness door, was fetched by the Stick (`GET
/el-candidato-1959.bif 200`) and rendered by the Video node as the native
trick-play strip: five frames across the foot of the screen, the centre one
framed, the fast-forward chevrons over it, at 0:40 and again at 04:00 — real
frames of the film at those positions. No code in the player beyond setting
`HDBifUrl`. Screenshots `v29_trick_fwd*.jpg`.

So this is a pipeline job of the same shape as cover generation, not a
programme. The Video node takes `content.HDBifUrl` / `SDBifUrl`; a harness
door (`selftest:bif=<url>`) attaches a file to the next play so it can be
measured on the glass, and the player prints `AWBIF offering …`.

**Owner decision reduced to**: run it or not. Running it is ~70 GB on an
archive.org item you already own and a batch job you already have the shape
of. Not running it keeps the channel off the public store (a beta channel
does not need it).

## A measurement that lied, and how

The first attempt at the 250 ms requirement read **545 ms median** and looked
like a certification failure. It was measuring the wrong event: `rowItemFocused`
fires when the focus ANIMATION settles, not when the key arrives. The tell was
that whole scene transitions measured 0.09–0.20 s through the same console
path — a screen change cannot be four times faster than moving one tile.

Measured at key RECEIPT instead, on a surface that prints the moment its own
`onKeyEvent` runs: **median 65 ms, worst 185 ms**, and the ECP round trip is
~99 ms of that. Comfortably inside the bar.

## What is still unmeasured

Nothing on the certification list. The last item closed 2026-09-08:

* **A real trick-play session — DONE.** Deep-linked into
  `contentId=TheGeneral720p1926&mediaType=movie`, which went **direct to play**
  (the voice-launch requirement, verified in the same shot). The console
  printed `AWBIF offering https://archive.org/download/archivewatch-bifs/
  el-candidato-1959.bif`, and a screenshot of the transport bar shows five
  real thumbnails from the film's own credits with the focused frame boxed, at
  02:00 of 1:31:17. This path had NEVER been exercised before, for the simple
  reason that until that afternoon no film carried a BIF the channel could
  see.

## Assets the Dashboard will ask for

| Asset | Spec | Status |
|---|---|---|
| Signed `.pkg` | ≤ 4 MB | `tools/roku_package.py`, blocked on the key |
| App poster | 540 × 405 | **`build/roku-store/channel_poster_540x405.png`** — already designed and correct; this row said "still wanted" and, like the privacy row above it, was simply out of date. `tools/roku_store_poster.py` offers an alternative that keeps the still at full contrast and bands the type instead of dimming the photograph |
| Screenshots | up to 6, 1920 × 1080 | the QA captures are the right size already |
| Short description | 300 chars | written — `docs/roku-store-listing.md` (268 used) |
| Long description | 1,500 chars | written — `docs/roku-store-listing.md` (1,459 used) |
| Privacy policy URL | required | **https://archivewatch.org/privacy.html** — live since 2026-06-19 (`privacy.html`); this table said "needs one" for months and was simply wrong |
| Deep link test parameters | one per media type | `contentId=TheGeneral720p1926&mediaType=movie` |
| Category / age rating | required | owner |

## Choosing the deep-link test film

A certification reviewer's FIRST experience of this channel is the deep link
they are handed, so it is chosen on three axes, not one:

* **Rights that cannot be argued.** `TheGeneral720p1926` carries
  `rightsEvidence: pre_1930` — published before 1930, US copyright expired by
  age. Night of the Living Dead is famously public domain too, but by a
  NOTICE DEFECT, and its catalog row says `source_unverified`; a reviewer
  should never have to take our word for anything.
* **Plays, measured.** livingDead_4k was tried first and the device answered
  `state=stop error=true ... STALLED` — a 3840x2560 mpeg4 upscale. The
  General plays at 720x480 with the position advancing and its BIF offered.
* **Recognisable, in English.** El Candidato (1959) was the recorded
  parameter and had been verified to play, but it is an Argentine film with
  Spanish titles, and it is a poor first frame for a US store reviewer.

## Dashboard state, 2026-09-08

The app record exists: **Channel ID 881015**, access code `PMPJCTH`, type SDK,
US only, English, Video, domestic region US.

| Section | State |
|---|---|
| Store assets | ✅ name, both descriptions (268/300 and 1441/1500), poster, six screenshots |
| Listing setup | countries + domestic region set |
| App profile | every field filled EXCEPT the two required **Phone** numbers — owner |
| App package | blocked: **"Verify developer account email"** is unticked (device linking is ✅) |
| Deep linking | blocked behind the package |
| Content rating | not selected — owner |

**Two screenshots were recaptured** after the owner's note that one was a
Spanish-language film and Home showed no backdrop. The channel was DELETED and
re-sideloaded first, because a sideload alone keeps the registry and the store
shot was showing the tester's own Continue Watching row. Home now leads with
the full-bleed hero (From Soup to Nuts, 1928) over the Public-Domain Canon
shelf, and Detail is Fritz Lang's Dr. Mabuse, the Gambler — English interface,
★7.8, Play · 155m, More Like This.

## The sequence

1. Owner runs `genkey` and stores the password outside the repo.
2. `python3 tools/roku_package.py --password '…'` → a signed `.pkg`.
3. Dashboard → Beta Apps → create, fill the listing, upload the package.
4. Publish (beta deploys immediately) and test with real accounts.
5. For the public store: run Static Analysis and App Behavior Analysis in the
   Dashboard, resolve everything they flag, and raise the BIF question with
   Roku before scheduling a publish date.
