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
| **Trick-play thumbnails, VOD > 15 min** | **required** | **none** | ❌ |

## The one blocker: BIF trick-play thumbnails

> "Apps must display thumbnails during trick play for VOD content longer than
> 15 minutes."

Almost every feature film in this catalog is longer than 15 minutes, and we
ship no BIF files. This is not a Roku-code problem — it is a pipeline and
storage problem, and it needs an owner decision.

The scale, from Roku's own example (915 thumbnails ≈ 14 MB at FHD): a 90-minute
film at 10-second intervals is ~540 images, call it 4–8 MB. Across **26,960
items that is on the order of 200 GB**, plus decoding every film to generate
them. The existing frame-cover pipeline (Decision 023) already showed what a
full-catalog decode costs: a ~1.5-day unattended run for ONE frame per item.

Three routes, in the order I would try them:

1. **Ask Roku for an exemption.** A 27,000-title public-domain archive is not
   the catalogue this rule was written for, and the submission notes are the
   place to say so. Costs one round trip and may end it.
2. **Publish as a Beta app first.** Beta channels deploy immediately to up to
   20 testers for 120 days with no certification review. That gets a real build
   in front of real people while the thumbnail question is settled, and it is
   the obvious first submission regardless.
3. **Generate BIF for a subset.** The ~1,500 curated and Home-facing titles are
   a few GB rather than 200, and could be hosted the way frame covers already
   are (Decision 023, an archive.org item). This only helps if Roku accepts
   partial coverage — worth asking in the same round trip as (1).

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

* **A real trick-play session.** Instant Replay is verified; fast-forward and
  rewind through the transport bar are not.

## Assets the Dashboard will ask for

| Asset | Spec | Status |
|---|---|---|
| Signed `.pkg` | ≤ 4 MB | `tools/roku_package.py`, blocked on the key |
| App poster | 540 × 405 | `images/icon_focus_fhd.png` is that size and is what the manifest ships; a designed store poster is still wanted |
| Screenshots | up to 6, 1920 × 1080 | the QA captures are the right size already |
| Short description | 300 chars | written — `docs/roku-store-listing.md` (268 used) |
| Long description | 1,500 chars | written — `docs/roku-store-listing.md` (1,459 used) |
| Privacy policy URL | required | archivewatch.org needs one |
| Deep link test parameters | one per media type | `contentId=el-candidato-1959&mediaType=movie` |
| Category / age rating | required | owner |

## The sequence

1. Owner runs `genkey` and stores the password outside the repo.
2. `python3 tools/roku_package.py --password '…'` → a signed `.pkg`.
3. Dashboard → Beta Apps → create, fill the listing, upload the package.
4. Publish (beta deploys immediately) and test with real accounts.
5. For the public store: run Static Analysis and App Behavior Analysis in the
   Dashboard, resolve everything they flag, and raise the BIF question with
   Roku before scheduling a publish date.
