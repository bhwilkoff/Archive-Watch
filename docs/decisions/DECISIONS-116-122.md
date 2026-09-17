# Archive Watch — Decisions 116–122 (archived verbatim from DECISIONS.md, 2026-09-17)

Append-only binds here too (Decision 092). Newer entries: `DECISIONS.md`.

---

## 116 — A data contract is a test, not a docstring; and a client may not crash on a shape
*Date: 2026-09-11*

`tools/test_details_contract.py` asserts the shape of the detail shards, and
`build_web_details.py` emits exactly one cast shape: **always a list**,
`[name] | [name, path] | [name, path, id]`. The Roku Detail screen reads both
shapes anyway, and `PosterTile.onContent` returns unless its nodes exist.

**Why**: Roku's store analytics showed 16 crashes in two days at
`DetailScreen.brs:781` — `c.Count()` over the cast. The channel was correct
and the data was not. `build_web_details.py` documented the three-shape
contract in its own header and then wrote

    cast.append(entry[0] if len(entry) == 1 else entry)

so a cast member with no TMDb profile arrived as a **bare string**. A
BrightScript String has no `Count()`, so opening Detail crashed the channel
on any such film: **2,798 entries across 1,716 films**, 5.4% of the catalog.

The part worth keeping is why it survived so long. `watch.js` reads the same
field and happens to test `Array.isArray(c)`, handling both shapes without
comment. One client's tolerance made the defect invisible to every other
client — the web looked fine, so the data looked fine, and the only place the
truth appeared was a crash log from a platform that trusted the docstring. A
second reader coping is not evidence of a correct contract; it is what hides
an incorrect one.

**How to apply**: when a producer's docstring states a shape, a test asserts
it — over the real artifact, not only over unit fixtures (`--shards`). Fix the
PRODUCER first when the defect is in data: republishing the shards fixed the
**live, already-shipped** 1.0.51 channel with no store review, where the
client fix waits on certification. Then fix the client anyway, because a
client may not crash on a data shape. And note the SceneGraph trap the second
crash was: a field declared with `onChange=` in an XML `<interface>` can fire
while the component is still being built, BEFORE `init()` has assigned node
references — guard the handler and re-apply content at the end of `init()`,
or an early-arriving `itemContent` leaves the tile blank forever.

## 117 — Roku's ingestion scores the CHANNEL INDEX, not the file; a withheld asset freezes its last verdict, so fit the poster instead
*Date: 2026-09-11*

A film whose poster is the wrong SHAPE gets a fitted 2:3 rendition
(`tools/fit_roku_covers.py`) rather than being dropped from the Roku Search
feed. The rendition scales the original to fit INSIDE a 400x600 canvas and
fills the bars with a blurred copy of itself, so the artwork is never cropped
and never stretched (Decision 097 intact). The files ride the `roku-covers`
tarball that deploy-pages restores to `_site/roku-search/covers`, which is the
one host Roku's fetcher can read — archive.org refuses it.

**Why**: the owner reported the registered feed stuck at 98% while the
standalone validator scored the SAME URL at 100%. Both readings are correct
and they score different things. The validator scores the FILE. The registered
ingestion scores the CHANNEL INDEX — and it counts an asset it is RECONCILING
(removing, because our feed stopped listing it) as a rejection, reporting the
errors from when that asset was last present.

Measured across six ingestions of three different feeds:

    job 3   3,106 assets   passed 3,052   errors 54   reconciled  --
    job 4   2,903 assets   passed 2,849   errors 54   reconciled 249
    job 5   3,106 assets   passed 3,052   errors 54   reconciled  54
    job 6   3,106 assets   passed 3,052   errors 54   reconciled  54
    job 7   3,755 assets   passed 3,701   errors 54   reconciled   0
    job 8   3,755 assets   passed 3,702   errors 53   reconciled   0
    job 9   3,755 assets   passed 3,702   errors 53   reconciled   0

The id list is BYTE-IDENTICAL across a feed that changed size by 203 assets,
and while those ids were absent NONE of them was in the feed at all. Roku's
own report download named the cause in one line — `Invalid aspect ratio
ASPECT_RATIO_4_3 for main image ... Image will be removed`, then `All images
have been removed. An asset must have at least one image.` Every one was a
Wikimedia still our own gate had since dropped, and dropping them is what
made the records permanent.

**The cost was never 54 films.** 835 of 3,972 eligible titles were being
withheld for the proportions of their poster alone — rights-evidenced,
playable, professionally illustrated films kept out of Roku Search because a
1918 press still is 4:3. Fitting them took the feed from 3,106 to 3,755 and
approved titles from 3,052 to 3,702.

**How to apply**: prefer a conformant rendition to withholding an asset, and
keep the negative controls — a 16x16 favicon and a non-image are REFUSED
rather than letterboxed in, and a map entry whose file did not reach the
tarball still withholds the film, because a 404 to Roku is worse than the
off-aspect image it replaces. Do NOT tighten the aspect tolerance to chase a
percentage: that experiment was run (1% both ways, 2026-09-11) and DISPROVED
its own premise — removing all 203 assets outside 1% changed the error count
by exactly zero, because the real failures were far outside any plausible
band and already excluded. Tolerances stay at the values measured from Roku's
own approvals (2:3 4%, 16:9 1.5%).

**Consequences**: **the fix worked completely, and the 53 are phantoms.**
Job 9's report download settles it three ways at once. The fitted covers were
all accepted — the feed grew by exactly 649 assets and APPROVED TITLES GREW BY
EXACTLY 649 (3,052 -> 3,701), with `reconciledCount` 0. The error count did not
move. And every remaining error cites
`https://thumb.wikimedia.org/.../500px-To_the_Highest_Bidder_(1918)_-_1.jpg`
for an asset the live feed serves a 400x600 cover for — a URL that appears
NOWHERE in the current file, which was re-fetched and confirmed at 3,755 assets
with all 53 ids present and all 53 carrying an archivewatch.org cover. Roku
parsed that file (`parsedCount` 3,755) and still replayed a stored verdict and
a stored URL. The error object is persisted per asset, not regenerated, and a
changed image does not invalidate it. The file itself validates at **100%**
(2026-09-11 15:44 UTC, 3,755 assets). Clearing a stale per-asset record is a
Partner Success request, and Partner Success is the required next step anyway
to publish the feed to end users. Two report traps worth keeping: `issuesList`
and the summary panel LAG one job behind the job API, and the asset-id search
box filters that stale list client-side with no network request.


## 118 — A captioned film streams like any other and draws its cues in the overlay; a whole-film HLS segment ignores every buffer ceiling
*Date: 2026-09-11*

On iOS and macOS a film with subtitles now plays through
`ResilientStreamLoader` — the same asset every other film uses — and its
WebVTT is rendered by the caption overlay. The HLS wrappers that carried the
track as a native rendition (`CaptionedHLSLoader` for a published track,
`LocalSubtitleHLSLoader` for one fetched on device) are referenced by nothing.
This is Decision 070, which tvOS has run since August, finally carried to the
other two platforms.

**Why**: a viewer on a phone reported *The Grapes of Wrath* playing "about five
minutes and then stops". The wrapper's playlist declares the whole MP4 as ONE
segment, and a segment is AVFoundation's atomic buffering unit, so
`preferredForwardBufferDuration` is ignored and the entire film is pulled into
memory. Measured on that exact film (2.19 GB),
`tools/test_captioned_buffer_growth.swift`, one shape per process:

    wrapper            4,195s buffered vs 300s asked (14x)   1,368 MB, climbing
    resilient loader     193s buffered vs 300s asked            55 MB, flat

A phone's media pipeline is jetsammed long before a 129-minute feature ends,
and ~5 minutes is where a mobile link reaches that ceiling. Decision 070
measured the same thing on a 3 GB Apple TV (`-11819` at ~100s) and fixed tvOS;
the memory note recording why iOS and macOS were scoped out said in as many
words that "low-RAM iPhones plausibly have the same bomb."

**Three things this turned out to reach that the tvOS fix did not.** The iOS 27
branch played the PUBLISHED master directly — ordinary https, so the system
could offer a generated track beside the authored one — and that playlist is
the same single segment (`#EXT-X-TARGETDURATION:7740`, one `EXTINF`). The
on-device-subtitles path writes the identical shape one directory over, so a
viewer who FETCHED subtitles for an uncaptioned film armed the same bomb.
And `makeLocalItem` rebuilt the wrapper on every AirPlay return and every
caption-type switch, so a fix confined to the start path would have been undone
by the first route change.

**How to apply**: never hand AVFoundation a playlist whose segment is longer
than the buffer you intend it to keep — the ceiling is advisory against a
segment boundary and absolute within one. Judge the shape by MEASURING
`loadedTimeRanges` against what was asked, not by reading the property back.
Run each shape in its OWN PROCESS: the first run of the harness played both in
sequence and the control's opening footprint — 1079, 541, 147 MB, falling —
was the wrapper's memory still being reclaimed, which is Decision 065's trap
one instrument over. And keep the two renderers' gates separate: the file
renderer and the caption engine used to share one flag because they never ran
together, and a captioned film now draws its published file WHILE the engine
listens to judge it (Decisions 062 / 073), so one flag would be two writers
fighting over one label.

**Consequences**: the native CC menu is gone for these films on iOS and macOS,
as it has been on tvOS since Decision 070 — the transport menu's caption-type
control covers the switch. Restoring it means SEGMENTING the playlist, which
needs fMP4; Decision 106 already built exactly that for tvOS 27 (`MP4Fragmenter`
+ `LocalMediaServer`) and it is the follow-up, not a rewrite. The subtitle
review keeps its job under a new verdict: it no longer decides whether to
deselect a native track, it decides which of the two renderers keeps the line.
`tools/test_captioned_asset_shape.py` is the cheap guard that stops the wrapper
coming back, negative-controlled both ways (it fires on a planted use, and a
comment naming the loader does not trip it — the branches that replaced these
loaders name them on purpose).

## 119 — A television hands over a link as a CODE; the encoder is proven against an independent reference at every version, never against itself
*Date: 2026-09-12*

The web-TV build draws a playlist's share URL as a QR code (`tv.js`, ported
from `roku/components/QR.brs` and extended from versions 1-10 to **1-40**).
`watch.js` feature-detects `window.AWTV.shareQR` and defers to it, so the
phone and desktop paths are untouched. The version and alignment tables are
MACHINE-GENERATED from an independent reference; version-info bits are
computed. `tools/test_tv_qr.mjs` proves the encoder two ways.

**Why**: a television has neither route the other platforms use.
`navigator.share` does not exist on Tizen or webOS, and a clipboard the viewer
cannot paste out of is not a way to share anything — so Share on a TV either
copied to nowhere or reported "Could not make a link". The owner asked for
exactly this: share playlists "from all native apps and have them publish to a
archivewatch.org link that can be shared (QR codes for TV-based native apps)".

**v10 was nowhere near enough, and the measurement is the argument.** Against
REAL catalogue ids — synthetic ids flattered an earlier version of this same
measurement fivefold — a share link runs 116 characters for one film and
1,048-1,328 for fifty, which is v23-v27. Version 10 holds 271 bytes, so the
encoder as it stood could only ever have drawn a one-to-three film playlist.

**How to apply**: never verify a QR encoder against itself. Every failure mode
here — a mistranscribed alignment centre, a format-info axis swap, a shifted
data bit — produces a clean-looking square of noise, so a golden file generated
from the code it tests asserts nothing. Compare against an INDEPENDENT
implementation, and compare on STRUCTURE rather than output: assert that
exactly one of the eight masks reproduces the reference, which proves the bit
stream, ECC, interleave, function patterns, placement and format info while
staying agnostic about mask selection — a penalty heuristic no two
implementations agree on (adding the spec's penalty rule 3 made agreement
WORSE here, 4/8 to 3/8, which is why the port keeps the Roku file's rule set).
Size each vector to its version's exact capacity so a wrong table row cannot
hide. Then decode the RENDERED screenshot, which is the only check that covers
the canvas, the scaling and the screen.

**What that found**: `QR.brs` listed v10's alignment centres as `[6, 28, 52]`
where the spec says **50** — the third centre advances by exactly 4 a version.
Every version-10 code the shipped Roku channel ever drew was malformed and
unreadable. It survived because v10 needs 232+ bytes and that encoder only ever
draws a ~50-character `/item/` URL. This is the fourth time in this project a
transcribed table has been wrong and the reason the new tables are generated.

**And two defects only the glass showed**, neither visible to any unit test: a
1,048-character URL printed in full overflowed the panel and pushed the only
button off the bottom of the screen (the link is now written out only when it
is short enough to key in with a remote), and a flex column with a `max-height`
SHRINKS its children, clipping the remaining copy to half a line — the panel
fitted and its contents did not. The panel caps at 86vh rather than 92 because
a television overscans about 5% a side and that last row is the button.

**Consequences**: **Roku still cannot share a playlist.** Its encoder is now
correct but remains v1-10, and BrightScript has no deflate — the share format
carries an uncompressed `0`-prefixed variant precisely so a Roku can encode
one, which makes its links longer than every other platform's. Porting the
v11-40 extension back is a separate piece of work.

## 120 — Social media is hosted where there is no ingest delay; a platform that could not post FAILS, and archive.org keeps only the video
*Date: 2026-09-13*

The daily post's CARDS are published to a `social-media` branch and handed to
Meta as `raw.githubusercontent.com` URLs. The teaser clip stays on archive.org.
And a platform that was scheduled, connected, and could not post now FAILS the
run instead of printing `(skipped — ...)`: only two reasons pass quietly, no
credential and no teaser for a platform that needs one.

**Why**: the owner, three days in — *"I still only see two posts on Instagram
and Threads."* Both Meta platforms had last posted on 2026-09-10, under six
consecutive GREEN runs, and the reason was printed in plain sight every time:

    posted: bsky...   posted: mastodon...   posted: youtube...
    (skipped — no public media URL (set SOCIAL_MEDIA_BASE_URL))  x2

Meta FETCHES media by URL rather than accepting bytes, so a card must be
servable before it is offered. archive.org is an ARCHIVE: a freshly PUT object
is not servable until its task queue catches up, and that queue's latency is
not a number you can wait out. Measured with `social_post.py --probe-media`,
which was built for exactly this question because the IAS3 keys live only in
CI and the latency could not be read from anyone's machine:

    0/3 media served after 604s      (all three served by 16 minutes)
    under 30s on the 8th and the 10th

A deadline cannot cover a variable that ranges from half a minute to a third
of an hour. So the host is the thing to change, not the number.

**How to apply**: the split is measured, not preferred. `raw.githubusercontent`
has no ingest step and returns `image/jpeg` for a `.jpg` — and
`application/octet-stream` for a `.mp4`, which Meta refuses. A GitHub Release
asset is no better: GitHub stores `video/mp4` on the asset and still serves
`application/octet-stream` from the download URL (checked, not inherited — the
existing note in `social_post.py` saying Release assets cannot work is
correct). So images go to the branch, video stays on archive.org, and a day
whose clip is not ready posts the CARD instead of a Reel, which the Instagram
adapter already did. A slow archive.org day now costs the video, never the
post.

**NOT YET PROVEN: that Meta will fetch from `raw.githubusercontent` at all.**
The first live run after this change posted an Instagram REEL
(`/reel/DdO8opgjxa_/`), and a REELS container carries only `video_url` — so
the card URL was never offered. That path is exercised the first day the clip
is not ready, and the loud-failure rule below is what makes it safe to find
out that way rather than by another three silent days.

**The classification is the part that matters most.** A platform returning
`(None, reason)` took the quiet skip branch and could never reach `failures`;
only an exception could. The comment above `failures` already stated the
intended rule — "scheduled AND connected AND then refused" — and an
unfetchable media URL satisfies all three while being filed as a cadence skip.
A new skip reason must now be declared benign deliberately; a bare literal
that is not in `BENIGN_SKIPS` fails the test that guards this.

**Consequences**: `tools/test_social_media_gate.py` was written on 2026-09-11
for this same incident and stayed GREEN through all six failures, because it
asserted the CONSEQUENCE (`if failures: return 1`) and never the
classification that decides what enters `failures` — so the list it reasoned
about simply stayed empty. A guard that checks the downstream effect of a rule
is not a guard on the rule. It now tests the rule itself, controlled both
ways. Related: Decision 107 (a red X means THIS run could not do its job) and
108 (a reader that cannot read says so, and never a zero).

## 121 — Correction to 119: Roku DOES share playlists, and a decision's closing paragraph outlives the hour it was true for
*Date: 2026-09-13*

Decision 119 ends: *"**Roku still cannot share a playlist.** Its encoder is
now correct but remains v1-10 ... Porting the v11-40 extension back to Roku is
a separate piece of work."* That is false, and was false within the same
session it was written — the extension landed, and `roku/components/QR.brs`
carries all 40 versions today.

**Why this needs its own entry**: DECISIONS.md is append-only, so 119 cannot be
edited, and a reader who stops at its Consequences paragraph concludes that a
shipped, working feature does not exist and may rebuild it.

**The evidence, taken independently a day later** on a Streaming Stick 4K
(15.3.4), after a week of unrelated TV work: Library -> `*` on the playlist row
-> Share this playlist draws a code; a screenshot of the TELEVISION decodes to
**448 characters** — the exact share URL, carrying `creature feature` and its
10 archive ids. 448 bytes at EC level L is **version 15**, five past the
claimed ceiling.

**How to apply**: when a decision's body and its Consequences paragraph are
written at different moments, the Consequences are the part that rots — they
are where "still open" and "a separate piece of work" live, and they are
written last, before the work they describe as remaining sometimes gets done in
the same sitting. Before repeating a "cannot" from an entry, check the code.
`docs/PLAYLIST-SHARING.md` had the same stale paragraph sitting directly above
its own refutation; it is now marked rather than deleted, because a wrong claim
that was read and believed is worth seeing.

**A device note worth more than the correction**: the Roku Options panel is
ROW-CONTEXTUAL. Opened over Continue Watching it offers only "Play all in this
row" and "App settings" — "Share this playlist" is absent, which reads exactly
like the feature not being there. Focus must be on the playlist row first. That
is how an hour could have been spent confirming the stale claim instead of
disproving it.

## 122 — Roku never RECEIVES a shared playlist, and the legacy tier never sends one; both are closed, not deferred
*Date: 2026-09-14*

Two owner rulings, recorded so neither is re-litigated. (1) **Roku receiving a
shared playlist is refused permanently** — not "deferred", not "pending a
server". (2) **Playlist sharing is switched OFF on the legacy Roku tier**
(`AWCan("shareList")`), while ITEM sharing stays on every tier.

**Why (1)**: a channel's only inbound route is a deep link carrying
`contentId` + `mediaType`, delivered by Roku's own surfaces — the Channel
Store, Roku Search, or ECP on the local network. A person holding a link on
their phone has no way to hand it to the box: no share target, and the Roku
mobile app cannot send an arbitrary URL to a channel. The channel COULD parse
`contentId=list:<blob>` — it already treats contentId as a command channel for
the `selftest:` verbs — so this is a DELIVERY limit and no channel code fixes
it. The only workaround is a short code the viewer types, which needs a server
to expand it, and that trades away the property the whole design rests on: the
playlist rides INSIDE the link, we host nothing, and there is no account at
either end. Asked directly, the owner: **"Roku receiving is not worth a
server."** Do not cost this out again; a future session that thinks it has
found a clever route should check whether the route requires us to store a
playlist, and stop there if it does.

**Why (2)**: a playlist link is 1,048-1,328 characters, which is a **v23-v27**
QR code. Measured in `docs/PLAYLIST-SHARING.md`: v14 cost 2,642 ms before two
fixes (one scanline per MODULE row; deriving scale from the display box) took
it to 1,131 ms, and the mask penalty alone should run ~1.7 s at full size on a
Streaming Stick 4K — several times that on a Roku 2 XD's 600 MHz ARM11, with
nothing on screen to say the box is working. The file already recorded the fix
— move the encode into a Task node behind a "preparing" state — as "the next
thing to do if anyone reports a slow card".

It will not be done. The owner: **"Old devices do not need full playlist
sharing support."** That is Decision-era capability policy working in the
direction it was written for — *legacy never sets the ceiling*, and a feature a
current Roku does well is switched off below rather than degraded for
everyone. The legacy viewer keeps every other route into a playlist: building
one, playing one, and opening one shared FROM another device.

**How to apply**: gate at the AFFORDANCE, not inside the encoder — the row
simply is not offered in Library Options on that tier, so nothing draws a
control that then apologises. Keep item sharing untouched: a `/item/` link is
~50 characters, a v4 code, which is what the Roku encoder drew for its entire
life before playlists existed and has never been slow. And note what this does
NOT change: `QR.brs` still carries all 40 versions (Decision 121), because the
tier gate is a product decision and a correct encoder is not conditional on
one.

**Consequences**: the sharing matrix's Roku row is final — **sends on modern,
never receives, does not send on legacy** — and the docs should stop carrying
it as an open item.
