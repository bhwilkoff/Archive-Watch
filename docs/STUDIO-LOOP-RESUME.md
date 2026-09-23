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
2. **A viewer count.** Nothing knows who is watching. Both platforms return
   it and the token is already held. This is the cheapest real answer left to
   "genuine opportunities for connection".
3. **Scenes** — the largest remaining OBS gap. A design question first
   (`binding-design-doc-discipline`): our arrangements are presets and
   framing is per-show, so "scenes" would change both.
4. **Item 17 is NOT closed, and there is new evidence.** Two of three bench
   runs on The Man Who Laughs showed a BLACK program. §D21's diagnostic named
   it correctly — *"the film is playing but no frames are reaching the program
   (rate=1.00 item=present player=30de07361c7ba51)"* — with `AWSURFACE forget
   ... engineHolds=no`, i.e. §D12a's guard behaved and the torn-down surface
   was not the engine's. **So this is a DIFFERENT cause from the one closed on
   09-22**: the engine holds a live player with an item, playing audio, and
   receives no video. The film is a 1080p **HEVC** Blu-ray rip and
   `attachFilm` requests no pixel format — that is the next suspect and it is
   unmeasured.
5. **Ending a show does not end the YouTube broadcast** — 403
   `invalidTransition`, because the RTMP publisher is torn down before
   `complete()` is called. An ordering fix, not yet done. The owner's channel
   may still hold an unlisted broadcast in "Live now".
6. **tvOS and iOS have the engine half of §D26 and no surface.** `showShoutOut`
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
