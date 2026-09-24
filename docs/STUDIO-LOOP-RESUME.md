# Resuming the Watch Together Studio loop

Written 2026-09-23 at v1.42.498 (1510), commit `c4e0968e4`, because the loop
was stopped mid-stride for a Claude update. Everything here is what a fresh
session needs and cannot get from the code.

---

## The prompt, verbatim

> Let's keep on polishing and iterating upon the Watch Together Studio. It
> still doesn't fulfill the promise of live streaming a public domain movie
> with your friends and having full control over the stream as you would on
> OBS. It also doesn't have the polish of the other surfaces within Archive
> Watch. It must also be designed well and create genuine opportunities for
> connection for all involved.

It ran as a five-minute cron (the owner's standing rule: every `/loop` is a
5-minute cron unless an interval is named). **Restart it with
`/loop 5m <the prompt above>`** — not dynamic pacing.

## Where the work stopped

`§D26`/`§D26a` landed complete: the AUDIENCE pane, the shout-out banner, the
chat-yield rule, `§8.48`, PARITY, the design doc. Nothing is half-built.

**The three complaints in the prompt, and how much of each is answered:**

| Complaint | State |
|---|---|
| *"full control over the stream as you would on OBS"* | Mostly answered — `docs/WATCH-TOGETHER-ROADMAP.md`'s macOS items are all closed. What OBS has and we do not: **scenes** (named, switchable arrangements of the same sources), **a transition** between them, **hotkeys**, and **a viewer count**. Scenes are the biggest honest gap: §D14a's framing is per-show, so a host cannot set up "intro" and "film" and flip between them |
| *"doesn't have the polish of the other surfaces"* | **Least addressed, and it is a real gap.** Home is a full-bleed cinematic hero with a scrim, real poster art and a clear type hierarchy; the Studio is four columns of small labels. This was captured and compared and then not acted on. The stage (FILM · STREAM · AUDIENCE) now carries the show and is the place to start |
| *"genuine opportunities for connection"* | Opened, not finished. §D26 is the first thing that lets a viewer reach the program. **Nothing in the Studio still knows WHO IS WATCHING** — there is no `concurrentViewers` anywhere, on any platform. YouTube's `liveBroadcasts.list` and Twitch's helix `streams` both return it, and the token to ask is already in the Keychain |

## The bench harness — the exact recipe

A real broadcast to a local server is the only way to see chat, the audience
pane or anything gated on `isOnAir`. Reproduce it like this:

```sh
B=<scratchdir>
cat > $B/mtx.yml <<'YML'
logLevel: info
record: no
paths:
  all:
    source: publisher
YML
mediamtx $B/mtx.yml &            # empty config REFUSES a two-segment path

APP=~/Library/Developer/Xcode/DerivedData/ArchiveWatch-*/Build/Products/Debug/Archive\ Watch.app
AW_START_ITEM=the-man-who-laughs-1928-1080p-blu-ray-x-265-ghost \
AW_GOLIVE_MAC=1 \                # opens the Studio window
AW_STUDIO_MAC_GOLIVE=1 \         # arms + publishes for real
AW_STUDIO_DEST=rtmp://127.0.0.1:1935/live \   # the APP PATH is required
AW_STUDIO_KEY=bench \
AW_STUDIO_CHAT_DEMO=1 \          # an INVENTED conversation (see below)
AW_STUDIO_LAYOUT=corner \
AW_STUDIO_MAC_SECONDS=420 \
# The camera and microphone are NOT attached under these doors (v1.42.602):
# this Mac's are the owner's. AW_STUDIO_CAPTURE=1 only for a run about capture,
# and the local-monitor mute also silences the FILM in the broadcast on macOS —
# AW_STUDIO_MAC_SOUND=1 (audible; ask the owner first) to measure film audio.
"$APP/Contents/MacOS/Archive Watch" > $B/app.log 2>&1 &
```

Then read `$B/app.log` for `AWMACDOOR`, `AWSTUDIOSTART`, `AWSTUDIOCHAT`,
`AWFILM`, `AWSURFACE`, and the server's log for `is publishing to path`.

**Screenshots**: `xcrun swift tools/mac_window_shot.swift "Archive Watch"
"Watch Together Studio" out.png` — window only, owning app matched exactly.
Never `screencapture -R`.

**Clicks**: `cliclick m:X,Y w:500 dc:X,Y` — **move first**, or Chrome and
some SwiftUI targets do not register the click. The Studio window sits at
`(0, 33) 1512x884`; screenshots come back at 2x, so window points are
`(pixel / 2)` and screen y is `window y + 33`.

## Things that will waste an hour if you do not know them

- **Every film the Studio may broadcast is pre-1930.** `StudioRights.tier` is
  `guaranteed` = `safe_pd_age` AND `year <= 1929`. So the standing "vary the
  test content" rule and the owner's "stop picking films with no audio"
  collide by construction. **The Man Who Laughs (1928)** carries a real
  soundtrack (`filmHasAudio=true sourceAudioTracks=1`) and is the current
  pick; Safety Last! (1923) is the previous one. Widening to `strict` is an
  owner content call, already listed in SCRATCHPAD.
- **`AW_STUDIO_CHAT` names a REAL Twitch channel** and is how strangers'
  messages landed over the owner's film on 09-22. Use
  **`AW_STUDIO_CHAT_DEMO=1`** — `StudioSession.demoConversation`, invented,
  deliberately containing an event line and one message past the ceiling.
- **Never kill the app to free the machine** (owner rule, 09-22). Check
  whether it is in use; a graceful `osascript -e 'tell application "Archive
  Watch" to quit'` is the difference from a SIGTERM that reads as a crash.
- **Check what else is running before believing a red suite line.** Three red
  lines in this project's history meant "somebody is using this Mac".
- The catalog SQLite for looking up ids:
  `~/Library/Containers/app.archivewatch.tvos/Data/Library/Caches/catalog-*.sqlite`,
  table `items`, key column `archiveID` (not `id`), and there is no
  `excluded` column in the client DB.
- Build schemes are **`Archive Watch Mac`** and **`ArchiveWatch`** (iOS/tvOS
  by destination). There is no "ArchiveWatch (macOS)".
- `tools/test_studio_all.sh` is not executable — run it as `bash tools/...`.
  `timeout` does not exist on this Mac.

## Open threads, in the order they are worth picking up

1. **The Studio's visual polish** — the prompt's second clause, least
   addressed. Compare against Home before designing.
2. **A viewer count — BUILT, not yet read live** (§D27, v1.42.499).
   `StudioSession.audienceCount`, polled every 30 s from `armBroadcast` to
   `completeArmedBroadcast`, drawn as "N watching" in the macOS AUDIENCE pane.
   Verify with `AW_STUDIO_AUTH=audience:youtube:<liveVideoID>` (or
   `audience:twitch:<login>`) once a platform is signed in on the Mac — the
   Debug build was signed out of both on 09-23, so the probe could only report
   that. iOS/tvOS have the value and no badge.
3. **Scenes** — the largest remaining OBS gap. A design question first
   (`binding-design-doc-discipline`): our arrangements are presets and
   framing is per-show, so "scenes" would change both.
4. **Item 17's second cause is FOUND AND FIXED** (v1.42.500). The Mac
   player swaps its `AVPlayerItem` ~10 s into a show, and the engine's video
   output and audio tap stayed on the discarded item: measured as
   `AWFILM player item changed ... output on=<old>` then `outputOnItem=n`.
   `StudioEngine.noteFilmItemChanged` now re-adds both to the new item, and
   `stop()` invalidates the observer so a stopped rehearsal engine cannot
   overwrite the live engine's `audioMix`. Verified from the server's own
   frames: centre YAVG 36-60 across 45 s after the swap, no stall line (the
   unfixed run stalled 13 s after go-live). §8.50 pins it. **And the swap itself is gone** (v1.42.501): it was
   `AWPLAYER swapping to the resilient loader reason=stall` — the projection
   window started on Decision 067's plain-URL path (kept so the SYSTEM can
   caption the film, which never reaches the program) and stalled. A player
   with `feedsProgram` (the Studio pane; the projection window when live OR
   armed) now starts on the loader. Re-measured: one attach, no swap, film on
   the wire. §8.50 covers both halves.
5. **Ending a show now ends the YouTube broadcast — in source, not yet on
   YouTube** (v1.42.499). `StudioSession.completeArmedBroadcast()` runs
   BEFORE each platform's `engine.stop()`, and iOS and tvOS call it too — they
   had armed the id and never completed it at all (Decision 133 again). §8.49
   pins the ordering. A refused transition now logs the broadcast's
   `lifeCycleStatus`, so the next real YouTube End either prints
   `marked complete` or names the state it met. The owner's channel may still
   hold an older unlisted broadcast in "Live now".
6. **iOS now has §D26's surface (v1.42.512, unseen on a phone); tvOS has the engine half and no surface** (Rule 8.8c makes that an owner question). `showShoutOut`
   / `expireShoutOutIfDue` are on the shared `StudioEngine` and every Apple
   composite would draw a banner; neither surface offers a list to pick from.
   Decision 133's rule applies — a shared type is not a shared path.

## The OAuth recording (the other open thread, not part of this loop)

Deferred by the owner on 09-22 to *"tomorrow morning"* = **2026-09-23**,
gated on live streaming being enabled for `benwilkoff@gmail.com`. Everything
else is staged:

- `docs/oauth/VERIFICATION-REPLY.md` — the item-by-item reply, awaiting a
  `[VIDEO URL]`.
- `privacy.html` carries the data-protection disclosures Google asked for.
- The shot list is rewritten against the Studio as it now is (13 beats, four
  columns, the checklist in Output); a signed Release build and an ordered
  checklist are on the Desktop.
- **The step that sank the first video**: a REVOKE must happen before the
  camera rolls and cannot be repaired in the edit — and the app's own
  **Sign out** has to happen first, because revoking at Google does not clear
  the local Keychain token. `StudioPlatforms.signOut` now revokes at the
  platform as well.
- Brand Account grants are held separately, are invisible on the owning
  account's Linked apps page, and `myaccount.google.com/u/N/b/<brandID>/connections`
  does not render. **The only handle on one is the refresh token via the
  revoke endpoint.**

## The platform APIs — what we do not use yet (researched 2026-09-23)

The owner asked whether we get the most out of YouTube's and Twitch's live
APIs. Ranked by connection value per effort. **Every YouTube item fits the
`auth/youtube` scope under verification — do NOT add a Google scope while it
is pending** (a new scope means a new demo video and a new review).

1. DONE — YouTube `contentDetails.latencyPreference: low` (+ `enableDvr`,
   `recordFromStart`, `enableEmbed` stated rather than defaulted).
2. DONE (unverified live) — viewer count, above.
3. BUILT (v1.42.505, §D30, §8.51) — Twitch stream markers from card
   changes. Not yet placed on a real channel: watch for `AWMARKER placed`.
4. YouTube **`liveChatMessages.insert`** (held scope, 50 units each): a
   `textMessageEvent` with the film's archive.org link when a film starts, and
   `pollEvent` polls ("keep watching or intermission?"). Needs a quota budget.
5. YouTube **captions via `liveStreams.cdn.ingestionInfo`'s
   `closedCaptionsIngestionUrl`** (`closedCaptionsHttpPost`, 0 units) — the
   film's own subtitle cues plus the host's speech as real toggleable
   captions. Largest accessibility gain.
6. YouTube `liveStreams.list?part=status` `healthStatus` into the health line
   (§4: health is never hidden).
7. Twitch EventSub WebSocket: `channel.chat.message` (held `user:read:chat`),
   `channel.raid` (no scope) → §D26 acknowledgments.
8. Host posting to Twitch chat / announcements — NEW scopes
   (`user:write:chat`, `moderator:manage:announcements`), every host
   re-consents. Twitch polls/predictions are Affiliate-only.

**Owner calls, not built**: Twitch `tags` (a PATCH REPLACES the host's own
channel tags every go-live — rejected for that reason), a default Twitch
category and YouTube `categoryId` (editorial). Rights: Twitch retired Watch
Parties 2024-04-02; public domain is the only route there.

## The iPhone §D26 run (2026-09-23, v1.42.514) — where it stopped

Doors added to `StudioPlayerContainer_iOS`: `AW_STUDIO_CHAT_DEMO=1` (the
invented conversation into the iOS engine), `AW_STUDIO_IOS_SHOW="N@T"` (T s on
air: open the controls sheet and press Show on chat line N through
`showShoutOut`), and the iOS door now MUTES its player (`AW_STUDIO_IOS_SOUND=1`
to hear it). Test phone: iPhone 12 `B4E756E2-…` — NEVER the 15 Pro (owner's).

**Proven, all of it** (v1.42.515): the banner reached the wire from the
iPhone 12 and expired on time. Two things that cost the first attempts: Two instrument faults
of mine, both to avoid next time:
- `: > mtx.log` on a RUNNING mediamtx does not reset its write offset; later
  lines land past the old end and a grep misses them. Restart the server with
  a new log file instead.
- `devicectl ... launch --terminate-existing` over a LIVE instance left the new
  one on a black screen, twice. Terminate by `--pid`, confirm zero processes,
  THEN launch. And the publisher's `redactingKey` labels the app path `live`
  as `<key>` when the key is passed separately — the path WAS `live/bench`
  (mediamtx says so). Previously noted:
- A relaunch's publisher logged `rtmp://10.0.0.90:1935/%3Ckey%3E` — no `/live`
  — while the first run of the day published to `live/bench`. Either a real
  path difference between launches or the key redaction eating the app path;
  unmeasured. Read `mediamtx`'s `paths/list` API (or `record: yes`) rather than
  assuming the path.

## Autonomous platform proof (2026-09-23) — use this, not hand-typed devicectl

`bash tools/studio_platform_proof.sh youtube|twitch|bench|state [seconds] [film]`
runs a whole proof on the TEST iPhone 12 and cleans up after itself; a
project-local permission rule (`.claude/settings.local.json`, gitignored)
allows exactly this script, at the owner's request ("You really should be able
to run commands yourself or create structures that allow you to do fully
autonomous testing"). YouTube runs are UNLISTED on Learning is Change and end
themselves. Twitch needs a one-time sign-in on the phone first.

**Proved on YouTube so far** (GYAQsLMDwho, 7uM5LtZ-1A8): latency=low + DVR +
recordFromStart + embed held; iOS reads YouTube chat; Share the film in chat
lands under the host's handle; End marks the broadcast complete; the Audience
section with the Share button renders during a real broadcast.

**OPEN — the viewer count.** The READ is proved (791 from a live public
stream), and every read during our own broadcasts returned `absent` for 4+
minutes. The instrument is the suspect, not the app: the "viewer" was a Chrome
tab whose player never left its spinner (`currentTime` 0), so YouTube's API had
no real viewer to count. Next: a viewer that actually plays (a foreground
window, or a second device), then re-read.

**Found by the autonomous run (yY2hfXeb5fE, 2026-09-23):** the iPhone 12 hit
`.serious` thermal ~130 s into a 1080p HEVC film and §6.5 stepped the video to
3600 kbps (60%), with 0 queued and 0 dropped — correct behavior, surfaced as the
capsule's ⚠︎. But two minutes is short: a two-hour watch-along on this phone
spends most of the film at reduced quality. Unmeasured: whether a smaller
source copy (720p H.264) avoids it — the decode, not the encode, is the
suspect. The health line now carries `thermal=`.
**The viewer count remains open**: a hidden Chrome tab never loads media
(`document.hidden`, readyState 0), so it cannot be the viewer; a person on a
visible screen, or a second device playing the stream, is the instrument.

**CLOSED the same day — the viewer count works on both platforms.** The
instrument is the TEST iPhone 12 opening the stream in Safari:
`xcrun devicectl device process launch --device <phone> --payload-url <watch URL> com.apple.mobilesafari`.
Both Mac accounts are signed in (YouTube = Learning is Change, Twitch =
licbhwilkoff; `AW_STUDIO_SIGNIN=youtube,twitch` re-runs the Studio's own
sign-in flows). The owner approved public Twitch test broadcasts on licbhwilkoff
("No one is following that twitch stream").

**CORRECTION to the thermal note above (2026-09-23):** the app plays the
`.mp4`, and The Man Who Laughs' `.mp4` is an **H.264 480p** derivative (681 MB),
not the 1080p HEVC `.mkv` — so "the HEVC decode is the suspect" was wrong and
the heat is our own pipeline (1080p30 encode, composite, camera). A 300 s bench
run on The General (also 480p H.264) went nominal -> fair at 195 s and never
reached `.serious`, at full 6000 kbps. The `.serious` run differed in two ways,
both unmeasured: RTMPS/TLS to YouTube (bench is plaintext), and a phone already
warm from back-to-back runs. Next measurement: the same film, TLS vs plaintext,
from a cold phone.
