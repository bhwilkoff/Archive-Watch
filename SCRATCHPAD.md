# Project Scratchpad — Archive Watch

> **How this file works.** It is loaded into every session, so it stays
> small: a true Current State, the open owner decisions, and the two most
> recent session-log entries. When you add a session-log entry, MOVE the
> oldest one here into `docs/SESSION-LOG.md` (verbatim, newest first).
> Rewrite Current State when it is wrong rather than appending to it.
> Ship state (what is LIVE where) is read from Pulse, not from this file —
> a number written here rots; `ops/pulse.json` is refreshed daily.

## Current State (rewritten 2026-09-14)

**Archive Watch is live on every platform it targets.** One catalog, one
data plane (Decisions 017/018/028), five native fronts plus the web:

| Platform | Where | Ship route |
|---|---|---|
| tvOS / iOS / iPadOS / macOS | one universal Xcode project (`ArchiveWatch/ArchiveWatch.xcodeproj`), App Store record `app.archivewatch.tvos` | `appstore-build.yml` → `appstore-submit.yml` (fully API-driven, Decision 101). Repo is at **1.42.118 (1130)** — `AppVersion.xcconfig` is the ONE version number; bump both on every commit |
| Android phone + Google TV | `android/`, package `com.archivewatch.app`, Play | `play-release.yml` builds; `tools/play_promote.py` promotes the SAME artifact (Decision 110). Repo versionCode 60 |
| Fire TV | `amazon` flavor of the Android app (minSdk 23, Decision 100/115) | `tools/submit-amazon.py` over the Amazon Submission API (Decision 111/115) |
| Roku | `roku/`, channel 881015 | `tools/roku_package.py` + Dashboard; signing key must NEVER be regenerated. Search feed at `archivewatch.org/roku-search/` (Decision 113/117) |
| Web PWA | `archivewatch.org` (viewer at `/`, curator at `/curate/`, Pulse at `/pulse/`) | GitHub Pages via `deploy-pages.yml` |
| webOS / Tizen | packages build from the same web root | **NOT SUBMITTED** — owner steps (LG Seller Lounge; Samsung Public Seller is US-only, cert backed up, Decision 112) |

**The catalog** (~26–27k visible items after the rights audit, Decision
027/114) is built and enriched entirely in GitHub Actions — ~38 scheduled
workflows audited daily by `workflow-health.yml`; their discipline is
Decisions 057/066/089/093/094/107. `catalog.json` + `catalog.sqlite` live
on a GitHub Release, never in git.

**Reading how it is doing**: <https://archivewatch.org/pulse/> — seven
audience views, every store read by the route it actually offers, refreshed
daily ~07:00 MT — cron 08:17 UTC, because GitHub runs this repo's schedules 4–5 h late (Decisions 108/109/123, `docs/PULSE-ANALYTICS.md`). The
social programme posts daily to five platforms (`docs/SOCIAL-PROGRAM.md`,
Decision 120).

**Where the rules live** (read before changing the thing they govern):
`docs/ENGINEERING-PROCESS.md` (the eleven disciplines) · `PARITY.md` (what
ships where) · per-platform binding design docs `docs/tvOS-DESIGN.md`,
`docs/iOS-DESIGN.md`, `docs/IPAD-DESIGN.md`, `docs/macOS-DESIGN.md`,
`docs/ANDROID-DESIGN.md`, `docs/TV-DESIGN.md`, `docs/ROKU-DESIGN.md`,
`docs/WEB-DESIGN.md` · `docs/DEVICE-TESTING.md` (real hardware only, never
emulators) · `docs/CAPTIONS.md` · `docs/SHAREPLAY.md` ·
`docs/PLAYLIST-SHARING.md` · `docs/CATALOG-CONTRACT.md`.

### Open owner items (nothing else is blocked)

1. **Roku 1.0.65** was scheduled to go live 2026-09-14 5:00 PM PT. Pulse
   detects it (App Health crash logs carry an `App Version`); confirm and
   update `ops/stores-manual.json`.
2. **Roku Search feed** is registered and validates 100%, but publishing to
   end users — and clearing 53 phantom per-asset errors — is a Partner
   Success request (Decision 117).
3. **Content decisions reserved for the owner** (Decision 027 reserves
   hides of this kind): the television rights audit (below); the
   1,000–5,000-vote band of 1964–77 films (Hammer, Carry On, Gamera, gialli
   — Decision 114); the 313 visible `safe_pd_age` items whose archive id
   contradicts their pre-1930 year (Decision 113, fifth amendment).
4. **`editors-picks` never appears on Home** — 5 eligible items against
   `minPerShelf = 9`; needs more picks in `featured.json` (editorial, not
   code).
5. LG and Samsung store submissions (accounts + a device to test on).
6. **Roku 1.0.75 (deep-link fix + options panel, Decision 126)**: uploaded to
   the beta (published) and the store (App Behavior Analysis running; then
   **Schedule publishing** is the owner's press). Ticket 110523 needs a reply
   asking for the Search Beta re-test — the Dashboard's Submit for review is
   disabled while the feed is FEED VALIDATED (= in certification).
7-NEW. **WATCH TOGETHER HAS BROADCAST TO YOUTUBE** (2026-09-18 ~14:40). The
   first YouTube go-live went out from an Apple TV to the channel **Learning is
   Change** (UCI9L3u8Hf_zeotF9-Ec349w) — confirmed from YouTube's own side,
   `liveBroadcasts` totalResults 34 -> 35, newest id `H96F1xNoJRo`. Twitch has
   worked since 09-17. What that took, all fixed:
   - `liveStreams.insert` sent `part=snippet,cdn,status` while its BODY carried
     `contentDetails.isReusable`; YouTube requires `part` to name every property
     the write sets. One word, and it had blocked every attempt.
   - The go-live **channel** was the personal default because `prompt=consent`
     re-shows consent for the account Google has already chosen and never offers
     the Brand Account picker. `prompt=select_account consent` fixes it; the
     token is now on **Archive Watch** (UCGNBrxdpR4ujnMWO4_OQgyA).
   - **Archive Watch itself is still inside YouTube's 24-hour first activation**
     (owner confirmed, ~2026-09-18 14:20). Nothing further is needed from
     anyone: re-run the read-only probe (`AW_STUDIO_AUTH=probe-youtube`) after
     it clears. No re-auth, the token is already on the right channel.
   - The OAuth consent screen is still in **Testing**, so refresh tokens expire
     in 7 days and every host sees "Google hasn't verified this app". Publishing
     it and passing verification is the remaining SHIP blocker for YouTube
     (`…/auth/youtube` is a sensitive scope: needs homepage, privacy policy,
     domain verification and a demo video — not the security assessment).
   - **Continuity camera can now be paired FROM the go-live sheet**
     (`continuityDevicePicker`, tvOS 17+). Owner paired a phone successfully;
     the microphone needed the audio session raised BEFORE Continuity is asked,
     because the mic is a session PORT and a non-record session lists none.
   - **Bitrate is settled**: on an Apple TV 4K the encoder holds 1080p30 with
     ZERO dropped frames at 4 and 6 Mbps against a local server, 13 dropped at
     8 and 552 at 10. It delivers ~70-75% of the rate asked. The home uplink is
     68.3 Mbps but 854 ms responsiveness under load, so the Twitch drops at
     ~4.2 Mbps are bufferbloat on the local path, not the device and not
     Twitch. There is nothing above 6 Mbps worth asking for on this hardware.
   Original item follows, much of it now historical.

7. **Watch Together Studio — the PUBLIC half is blocked on the owner ON iOS;
   tvOS and macOS also need CODE.** The three one-time steps (a/b/c below) are
   what stands between the feature and a real broadcast **from an iPhone**.
   **macOS can now sign in and go live** (§9.ttt, 2026-09-18): the shared
   sign-in row moved into `Studio/`, Rule B13g's missing sheet content built,
   and macOS given a real `ASWebAuthenticationSession` anchor (it had been
   handed an empty `NSWindow`). **tvOS still cannot** — it has the engine, the
   gates and a verified hardware encoder, and no go-live surface, because Rule
   8.8a is PROPOSED with three questions reserved for the owner (§9.ooo).
   Everything else on them is real and measured — which is why it went
   unnoticed. **Android has no OAuth or platform client either** (zero Kotlin
   references to googleapis.com / api.twitch.tv), so the ids do nothing for it.
   macOS needs only a CALL SITE — the clients are shared Swift both Apple
   targets already compile — plus a go-live surface
   (`docs/macOS-DESIGN.md` governs that); tvOS needs the code and still carries
   Decision 128's unproven sign-in presentation. **This item used to say "and it is the only
   blocker — everything else is built and verified on real hardware", which
   the night of 2026-09-18 proved too confident**: the Android product path had
   never carried audio at all, its video and audio clocks were 19.6 s apart,
   the Mac bench door was publishing the room, and three §8 cases had not
   compiled for a session. All are fixed and measured
   (`docs/WATCH-TOGETHER.md` §9.mm-§9.aaa), and the lesson is kept here rather
   than smoothed over: *verified* means a measurement someone can point at, and
   several things carrying that word had never had one. What is genuinely NOT
   yet verified is named in items 8 (phone-class Android performance — the
   dongle has no hardware H.264 encoder, so its 13 fps says nothing about a
   phone) and 9a (the tvOS/iOS encoder reads). Owner steps:
   (a) **YOUTUBE_CLIENT_ID is DONE** (2026-09-18, registered in Chrome): a
   Google Cloud project "Archive Watch" with YouTube Data API v3, an OAuth
   client of type **iOS**, bundle id `app.archivewatch.tvos`, in the gitignored
   `Secrets.xcconfig`. Proved against the live endpoint with its own controls
   (`tools/test_studio_registered.swift`, §8.9, WATCH-TOGETHER §9.nnn).
   **TWITCH_CLIENT_ID is DONE too** (2026-09-18, after the owner cleared the
   email and 2FA gates): application "Archive Watch Studio", **public** client,
   Broadcaster Suite, redirect `https://archivewatch.org` (Twitch refuses
   `http://localhost`). §8.9 asserts both platforms — Twitch's device endpoint
   returns a real `device_code` and accepts the stream-key scope.
   **No client secret** is needed (neither flow uses one) and no derived
   redirect string (the scheme is the bundle id, already declared in
   `Info.plist`). **Both platforms are now configured**, so the go-live sheet's
   "not set up" state no longer appears on any Apple surface — and note that
   registering the FIRST id is what exposed the tvOS gate defect in §9.ooo;
   (a2-NEW) **THE CHANNEL IS NOW CORRECT; ONLY YOUTUBE'S ACTIVATION REMAINS.**
   2026-09-18 14:26 the television's token was moved to **"Archive Watch"
   (UCGNBrxdpR4ujnMWO4_OQgyA)** — it had been on the personal default
   "Ben Wilkoff". The blocker was ours: `prompt=consent` re-shows the consent
   screen for the account Google has ALREADY picked and never offers the Brand
   Account chooser, so "sign out and sign in again to choose another" could not
   work (a sign-out/sign-in returned the same channel in 42 seconds).
   `prompt=select_account consent` fixes it. YouTube STILL answers
   `liveStreamingNotEnabled` for Archive Watch, and with the channel question
   eliminated the remaining candidate is the documented **24-hour first
   activation**. Re-check with a read that creates nothing; no owner action is
   known to be outstanding. Original note follows.
   (a2) **MEASURED 2026-09-18 AND IT IS BLOCKED — DO THIS FIRST.** Asked of
   YouTube from the Apple TV with the owner's own token (`liveBroadcasts.list`,
   a READ that creates nothing): `liveStreamingNotEnabled`. **Live streaming has
   never been enabled on the channel "Ben Wilkoff"
   (UCtPDkIGiSWSb5N8hNdaPizg).** Turn it on at **youtube.com/features** from a
   phone or computer; the FIRST activation can take **up to 24 hours**, so this
   is the item to do today rather than on the evening of a broadcast. The
   go-live surface now asks this before the host presses anything and greys Go
   live with this sentence, instead of failing inside four write calls (§9.zzz).
   Original note follows.
   (a2-orig) **CHANNEL ELIGIBILITY, worth doing a day early.** YouTube's encoder
   path (ours) needs the channel VERIFIED and no live-streaming restrictions in
   the past 90 days; enabling live streaming for the first time can carry a
   **24-hour wait**, so switch it on the day before, not the hour before.
   **The 50-subscriber rule does NOT apply** — it is a MOBILE-app rule, and the
   Studio publishes as an encoder like OBS (§9.bbb). That was an open risk in
   Decision 127 and is now closed;
   (a3) **WITHDRAWN 2026-09-18, same day it was raised — no second Google client
   is needed.** It said the Apple TV required a client of type "TVs and Limited
   Input devices" with a secret. That was reasoning from Google's docs, not a
   measurement, and the measurement says otherwise: `ASWebAuthenticationSession`
   on tvOS presents **Apple's own hand-off** — *"Sign in with Apple Device ·
   You will get a notification on a nearby iPhone or iPad"* — so the phone does
   the Google sign-in and the token lands on the TELEVISION. Proved end to end
   on Ben Bedroom with the EXISTING `YOUTUBE_CLIENT_ID`: the owner approved on
   their phone, the TV showed "Signed in to YouTube", and a read-only
   `channels.list` returned their own channel. The device-flow code stays as a
   fallback for platforms with no such hand-off (Android TV later);
   (a4) **REAL and NEW: the OAuth consent screen is in TESTING.** The owner had
   to click through *"Google hasn't verified this app … currently being tested"*
   on their phone. Google's own documentation: a project whose consent screen is
   external and "Testing" is **"issued a refresh token expiring in 7 days"**. So
   as it stands the host is signed out of YouTube WEEKLY on every device, and
   anyone who is not a listed test user cannot sign in at all. To ship this:
   publish the consent screen and pass OAuth verification. `…/auth/youtube` is a
   SENSITIVE scope, so that needs an app homepage, a privacy-policy URL (both
   exist: archivewatch.org and its privacy page), domain-ownership verification
   and a demo video — but NOT the third-party security assessment, which applies
   only to restricted scopes. Twitch has no equivalent gate;
   (b) **pair an iPhone** on the Apple TV via the system Continuity picker
   (once — a paired phone is found automatically after);
   (c) **allow camera + mic** on the iPhone (Settings ▸ Archive Watch) — there
   is no supported way to pre-grant on a device, and the harness refuses
   rather than hanging on a prompt.
   **Read §3.4a before registering anything**: an automated matcher does not
   read our rights audit, and YouTube can interrupt or END a live stream and
   strike the channel even when the rights are clear — it happened to someone
   streaming *His Girl Friday*. A silent film's modern score can also still be
   under copyright when the film is not. The app now warns the host; the risk
   is real and is yours to accept.
   Also open, for the owner: widening the rights tier from `guaranteed`
   (4,210 films) to `strict` (7,517) is a Decision-027 content call.
8a. **The Local Network prompt is ON THE PHONE NOW, unanswered.** A 2026-09-18
   run of the iOS Studio door raised it — *"Allow ArchiveWatch to find devices
   on local networks?"* — and it was deliberately NOT answered: a privacy grant
   on the owner's phone is the owner's decision, and the prompt shows the
   home's network name and an area map. The screenshot was deleted rather than
   kept. Answering it either way is one tap, and until then the iOS encoder
   read (item 9a) cannot complete, because the prompt sits in front of the app.

8a-orig. **Optional, one tap**: the iOS bench door (`AW_STUDIO_IOS` +
   `AW_STUDIO_DEST`) reaches a mediamtx on the Mac only if iOS's **Local
   Network** prompt is allowed on the iPhone. It was left UNANSWERED on
   purpose — a privacy grant on the owner's phone is the owner's call. One tap
   of *Allow* would let §6.2's iOS `.playAndRecord` outcome be measured on the
   product path (`docs/WATCH-TOGETHER.md` §9.dd); the real client ids would
   also remove the need, since a public host triggers no such prompt.
   `NSLocalNetworkUsageDescription` was deliberately NOT added to the shipping
   Info.plist — the product does no local networking.

8. **Pair the Pixel 8a for wireless debugging** — one step on the phone
   (Settings ▸ System ▸ Developer options ▸ Wireless debugging ▸ Pair device
   with pairing code), then `adb pair <ip:port> <code>`. Its adb-over-TLS
   pairing expired and **three Android items wait on it together**: a
   phone-class render measurement (a Google TV dongle needs 37.4 ms a frame
   against a 33.3 ms budget, so the architecture is proved and its speed is
   not), a real camera tile (no television has a camera), and eyes on the
   phone Detail entry, whose DECISION is tested but whose appearance has never
   been seen.
9a. **An Apple TV that is ASLEEP is not woken.** The tvOS encoder read
   (§9.vv) was attempted at 03:30 and `devicectl` refused: *"System is asleep -
   foreground app launch forbidden"*. Waking it would switch on a television in
   the owner's bedroom in the middle of the night, which is the same intrusion
   the Fireplace instruction is about; Movie Room would light another room in a
   sleeping house. **tvOS is DONE** (2026-09-18 06:04, owner said "you can wake the bedroom tv"): the readout on an Apple TV 4K 3rd gen says `encoder: hardware`, matching the Mac, and the same run photographed the configuration refusal ("Streaming is not set up yet") for the first time. **iOS still waits** —
   they need no bench destination, only a screenshot of the DEBUG readout, so
   they are a two-minute job whenever the televisions are awake.

9. **Fireplace TV is off limits for testing** (owner 2026-09-17, mid-run: "I'm
   actively watching on it now"). Bedroom and Movie Room are fine — but both
   are Apple TV 4K **3rd** gen, and Fireplace is the only **2nd** gen, i.e.
   the Studio's hardware floor. The §8.3 ten-minute soak passes on the 3rd gen
   (`docs/WATCH-TOGETHER.md` §9); the 2nd-gen repeat needs a window the owner
   offers, and **no window is currently agreed** — ask before touching
   Fireplace. Movie Room is NOT in the tvOS provisioning profile — it fails to
   install; Bedroom works.

---

## OPEN — OWNER DECISION: television has never passed the rights audit

Found 2026-09-06 from the owner's question "2 Stupid Dogs is a show from the
1990s, so how is it public domain?" It is not. The gates are working — on
FILMS. Television was built on a parallel path that never had them.

**Why.** `audit_rights.py` (Decision 027) runs over `catalog.json`. Episodes
are NOT catalog items: they live only in `series/*.json`, put there by
`backfill_tv_episodes.py`, which searches archive.org by show title and
applies no rights test of any kind. So **all 4,702 episodes across all 489
spines have never been seen by the rights audit.** `2-stupid-dogs-season-1`
is not in `catalog.json` at all — a 2024 user upload of a 1993 Hanna-Barbera
show, no `licenseurl`, no `rights` statement.

**Scope, measured.** 202 of the 489 spines have `yearStart >= 1978`, carrying
1,949 episodes. Fed through the FILM audit's own `bucket()`, all 202 come out
`modern_copyright_unconfirmed` — the audit wants a licence check before
hiding, by design (it never hides on a failed fetch). A 24-show sample of
that confirm step: **23 have no licence at all**; one (The Man from Snowy
River, 1994) carries a genuine CC public-domain dedication and would be
correctly rescued. Names in the hide set include Murphy Brown, Knight Rider,
The Dukes of Hazzard, Freddy's Nightmares, Designing Women, Minder, Count
Duckula, Honey I Shrunk the Kids, and a 2025 documentary.

**The fix is understood but NOT applied**, because hiding ~194 shows and
~1,870 episodes is a content decision of the same kind Decision 027 reserved
for the owner (who set the 1964-77 keep and the 1995 commercials cutoff):
  1. run `audit_rights`'s confirm pass over the spine items,
  2. carry `excluded` into the spine build so a hidden item cannot be served,
  3. gate `backfill_tv_episodes` at ingest so this cannot refill.
Step 2 matters on its own: `gather_raw_targets` re-pools existing spine files
with NO `excluded` check, so even once an item IS judged, the spine would
keep serving it.

---

## Session Log

### 2026-09-19 (Watch Together loop) — the Continuity camera crash and the camera tile, both fixed on the glass; the audio artifacts survive four hypotheses
Owner /loop: "get Apple TV streaming working end to end ... close all
documentation and testing gaps ... until all aspects of streaming to YouTube
and twitch work from Apple TV using continuity camera (with audio and videos
working)."

**THE CONTINUITY CAMERA WORKS END TO END ON THE APPLE TV.** Two bugs, both
found on the first runs that ever had a phone attached, both verified from the
server's own recording rather than the app's claims.

- **The crash**: `-[AVCaptureDevice _setActiveFormat:...sessionPreset:]
  Unsupported format ((null))`, signal 6, reproduced three times. A Continuity
  Camera will not let the SESSION drive its format from a preset. `.inputPriority`
  removes the call entirely. The first fix was WRONG and the device said so —
  it chose the preset with `canSetSessionPreset`, which answered TRUE for
  1280x720 and crashed anyway; logging `cam.formats` showed the camera HAS
  1280x720 twice, so the format was never missing.
- **The missing tile**: nothing retained the `AVCaptureSession`. It was a local
  inside an `if` block; ARC freed it, capture stopped, and every log line still
  said success because `startRunning()` had succeeded a moment earlier.
  `AWCAM frames=0` for a whole run, then `frames=4482 (+30/s)` after the tap
  took ownership. The tile is now in the program frame, bottom-right, measured.

**Both platforms are READY from the television** — YouTube (Learning is Change,
the `liveStreamingNotEnabled` block gone) and Twitch (licbhwilkoff) — and real
broadcasts were created from the Apple TV with the camera attached.

**THE AUDIO ARTIFACTS ARE NOT SOLVED, and four hypotheses died measured:**
congestion (throttled bench at 2.0 Mbps against a 3.85 Mbps program: 1 click in
50 s, control 1 in 60 s); pipeline state (both runs identical counters, both
resumed mid-film); timestamp drift (8,117 packets, 0 deltas >2 ms off nominal,
0 ms drift over 188 s); and TLS (the owner heard the SAME artifacts on a
plaintext-ingest broadcast). What we SEND decodes clean; what YouTube DELIVERS
does not, over both transports. Remaining lead, suggestive only: audio runs a
median +0.38 s ahead of video in mux order, p95 +0.96, worst +2.95.

**Three observability gaps closed on the way**, each one having cost a wrong
inference: `AWCAM` (a camera counter — `filmFramesPulled` existed for the same
reason and the camera had none); `AWGATE` (a rights refusal set an on-screen
sentence and returned, so a refused run and a door that never fired were
identical in a log); and `AWPUB` — `grep -c awdiag RTMPPublisher.swift` returned
**0**, so a publish that never connected left no trace, and I wrongly inferred
exactly that before the owner said the page simply had not refreshed.

**`docs/TVOS-STUDIO-RUNBOOK.md` is new** — the run recipe that existed only as
scattered facts and cost an hour: waking via `atv_scenario.wake_tv()`, the two
devices both called "Ben Bedroom", choosing a film by `rightsBucket='safe_pd_age'`
(4,210 rows) rather than `rightsStatus`, `--console` and screenshots being
mutually exclusive, and `DiagFile` truncating on every launch.

**Still open**: the artifacts; the Continuity MICROPHONE (`micPort=none` every
run — the SDK offers no way to enumerate a paired device, so `audioSessionInputs`
only exists on one the picker handed over); and the camera dropping repeatedly
(observed four times), for which detection now exists but recovery does not.

### 2026-09-18 (Watch Together loop, daytime) — the first YouTube broadcast, the television's 75-second audio lead, and a macOS studio that had never been run
Owner /loop, same prompt: stream PD films to YouTube and Twitch as "Watch
Together" / "Watch Together Studio", Apple first, research hard, test on real
devices. Mid-session the owner left home and redirected to macOS: "all of my
devices are now at your disposal ... fully build out the macOS app for live
streaming to both YouTube and twitch."

**WATCH TOGETHER NOW BROADCASTS TO BOTH PLATFORMS FROM AN APPLE TV.** The first
YouTube go-live went out to "Learning is Change", confirmed from YouTube's side
(`liveBroadcasts` 34 -> 35, id `H96F1xNoJRo`). Twitch has worked since 09-17.

- **The television's audio ran 75 SECONDS ahead of its picture**, on every
  broadcast the feature had ever made. The 8m16s soak's "15 ms" was a DRIFT
  proxy and blind to a constant offset, which is what it said it was. Cause: the
  tee was fed by the player's BUFFERING, so the first packet it ever saw came
  from the buffer head. Now +0.20 s and flat, via an architecture that DELETES
  the tee - the Studio PULLS audio by film position, so sync is a property of
  the request rather than a correction applied afterwards (§9.rrrr-§9.tttt).
- **YouTube was blocked by one undeclared `part`**: `liveStreams.insert` set
  `contentDetails.isReusable` in its body while declaring only
  `snippet,cdn,status`. And the go-live CHANNEL was the personal default because
  `prompt=consent` never offers Google's Brand Account chooser -
  `prompt=select_account consent` does (§9.vvvv).
- **macOS went from never-tested to a working studio.** It had a go-live sheet,
  platform picker and sign-in since §9.ttt and no way to reach any of it without
  a human clicking, so a bench run recorded zero bytes. `AW_STUDIO_MAC_GOLIVE`
  drives the same commit chain; camera, microphone, five layouts and three
  overlay cards are all verified from the server's own recording (§9.xxxx).
- **A crash that killed the app at the END of every macOS broadcast**: the
  `MTAudioProcessingTap` held an UNRETAINED reference, and its real-time
  callback outlives the mixer. Fixes iOS too - same tap path; tvOS is unaffected
  because it pulls instead.
- **Bitrate is settled**: 1080p30 with ZERO dropped frames at 4 and 6 Mbps
  locally, 13 at 8 and 552 at 10, and VideoToolbox delivers ~70-75% of whatever
  is asked. The uplink is 68.3 Mbps with 854 ms responsiveness under load, so
  the Twitch drops at ~4.2 Mbps are bufferbloat, not the device and not Twitch.

**THE RECURRING FAULT, named because it appeared six times in one day**: a
readout that describes the MECHANISM rather than the OUTCOME. The tvOS warning
asked "did the tap attach" - permanently false there - while the owner listened
to audio it said was absent. Three go-live gates, a camera path and a Continuity
attach all refused in SILENCE, making four different causes produce identical
evidence. A door logged "live" from intent it had just recorded. And the A/V
tool keyed on a burst's PEAK, putting half a marker of bias in every absolute
number - caught only because the bias scaled with the stimulus, which a real
offset cannot do.

**Two corrections owed and recorded rather than smoothed over**: a SKIPPED test
was reported as a passing one (the app never entered the code under test), and a
"fix" for the Continuity crash addressed the microphone when the crash was in
the camera path.

**For the owner**: sign-in on the Mac (Twitch is a phone-approvable device code;
YouTube needs the browser sheet on that machine), and one Apple TV run with the
phone attached to locate the Continuity crash - it is instrumented to name the
failing call on the first attempt. Archive Watch's own YouTube channel is inside
its 24-hour activation and needs nothing further; the token is already on it.

Older entries: `docs/SESSION-LOG.md` (verbatim, back to 2026-04-17).
