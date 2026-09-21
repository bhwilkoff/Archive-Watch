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

7-DONE. **THE iPHONE HAS BROADCAST TO YOUTUBE, END TO END** (2026-09-20 16:44,
   iPhone 12). The owner enabled YouTube sign-in and granted camera + microphone,
   and the run went through the product's own chain:
   `AWCAM attached camera=Front Camera mic=iPhone Microphone` ·
   `AWCAM frame shape 1280x720 (landscape)` ·
   `AWPUB connecting rtmps://a.rtmps.youtube.com/... transport=rtmps/tls` ·
   `AWPUB publishing — the server accepted the stream` ·
   `AWPROV provenance cleared 20s after going live`.
   **Confirmed from YOUTUBE's own side**, not ours: the channel's
   `liveBroadcasts` totalResults went **59 -> 61** across the session.
   Channel "Learning is Change" (UCI9L3u8Hf_zeotF9-Ec349w), readiness `.ready`.
   Twitch on this phone is configured but NOT signed in, so the Twitch half of
   iOS is still unproven.
   **ONE PIECE OF LITTER TO KNOW ABOUT**: two broadcasts were created, not one.
   The first door I wrote resolved a YouTube destination and armed
   `StudioSession` — correct on macOS, wrong on iOS, where the Studio is
   presented as a `fullScreenCover(item:)` bound to a `GoLiveRequest` and the
   container resolves the destination itself. So a real unlisted broadcast was
   created and abandoned. It is unlisted and was never published to; delete it
   at leisure.

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
   unnoticed. **CORRECTED 2026-09-20: Android DOES have Twitch OAuth and it IS
   configured.** This line read "Android has no OAuth or platform client either
   (zero Kotlin references to googleapis.com / api.twitch.tv)" and was simply
   out of date: `TwitchLive.kt` speaks helix and reads the live ingest-PoP
   list, `StudioPlatformAuth` runs the device flow, `StudioTokenStore` keeps
   the token, `StudioSignIn.kt` renders twitch.tv/activate with the user code,
   and `awTwitchClientId` is set in ~/.gradle/gradle.properties so the build
   carries a real client id. The ONLY thing missing is that nobody has ever
   signed in on the Pixel — a device code was raised 2026-09-20 18:04 and
   lapsed unapproved. YouTube on Android is still genuinely absent. **This
   stale note cost real time**: it is why Android platform testing kept being
   deprioritised across sessions, including by me today.
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
8a. **CLOSED 2026-09-20 — a bench destination needs no Local Network grant.**
   This item assumed since 09-18 that the iOS (and tvOS) bench door was blocked
   behind an unanswered "Allow ArchiveWatch to find devices on local networks?"
   prompt, and that assumption is why the PRODUCT path on those two platforms
   was never measured against a local server. It is wrong: an iPhone 12 and an
   Apple TV 4K both published to `rtmp://10.0.0.90:19360` on the first attempt,
   no prompt, no refusal — verified from the server's own recording on each.
   Whatever the state of that grant, it is not what was standing in the way.
   Original note follows.

8a-orig. **Optional, one tap**: the iOS bench door (`AW_STUDIO_IOS` +
   `AW_STUDIO_DEST`) reaches a mediamtx on the Mac only if iOS's **Local
   Network** prompt is allowed on the iPhone. It was left UNANSWERED on
   purpose — a privacy grant on the owner's phone is the owner's call. One tap
   of *Allow* would let §6.2's iOS `.playAndRecord` outcome be measured on the
   product path (`docs/WATCH-TOGETHER.md` §9.dd); the real client ids would
   also remove the need, since a public host triggers no such prompt.
   `NSLocalNetworkUsageDescription` was deliberately NOT added to the shipping
   Info.plist — the product does no local networking.

8. **CLOSED 2026-09-20 — the Pixel 8a is paired and the phone has RUN.** The
   owner supplied the pairing code; `adb pair` over the mDNS
   `_adb-tls-pairing._tcp` advertisement, then connect over `_adb-tls-connect`.
   The first phone-class Android Studio measurement ever taken:
   **fps 20-22** against the Google TV dongle's 13 (per-frame draw 5.6-7.3 ms,
   drain 2.3-2.9, audio 4.2-5.3; draw split tex 0.9-1.3 / gl 1.2-1.4 /
   swapEnc 1.2-1.5 / swapDisp 1.0-1.4), publishing H264 + AAC to a real server,
   75 MB in the first run. Still short of 30 fps and that is now a phone
   number rather than a dongle number.
   **AND THE PAIRING WAS NEVER THE ONLY BLOCKER.** The studio bench door
   (`aw_studio_item`) was collected in `TvAppRoot` ONLY — television-only — so
   the pairing would have arrived and the door still would not have opened.
   Wired into `AppRoot` as the identical collector.
   **Two real defects the run found, both invisible on a television**: the
   program was stretched into the phone's portrait surface (§9.2b), and
   `filmAspect` was declared with a 16:9 default and **assigned by nothing**,
   so every non-16:9 film went out stretched — which is most of this
   catalogue, since a silent film is 4:3. Both fixed and verified from the
   server's own recording (Caligari pillarboxed to exactly 1.333) and from the
   phone's screen.
   **STILL NOT RUN: the camera and the microphone.** Permissions are granted
   on the Pixel and zero camera lines appear in the log — the bench door arms
   the Studio but attaches no capture, so `StudioCamera`/`StudioMicAudio`
   remain compile-time claims. That is the next Android item.

9a. **An Apple TV that is ASLEEP is not woken.** The tvOS encoder read
   (§9.vv) was attempted at 03:30 and `devicectl` refused: *"System is asleep -
   foreground app launch forbidden"*. Waking it would switch on a television in
   the owner's bedroom in the middle of the night, which is the same intrusion
   the Fireplace instruction is about; Movie Room would light another room in a
   sleeping house. **tvOS is DONE** (2026-09-18 06:04, owner said "you can wake the bedroom tv"): the readout on an Apple TV 4K 3rd gen says `encoder: hardware`, matching the Mac, and the same run photographed the configuration refusal ("Streaming is not set up yet") for the first time. **iOS IS DONE TOO** (2026-09-20 evening):
   `AWENC hardware=true` on an iPhone 12, at 6000 kbps, read from the device's
   own diagnostics file. This item had said iOS needed "a screenshot of the
   DEBUG readout", which framed a number the app already knows as a
   photography problem — and kept it open for two days. It is a log line. The
   reason it could not be read before is the same one that hid the publisher's
   counters: `StudioSession.diag` wrote to stderr, which reaches nothing on a
   phone, and the iOS loop printed no health line of its own.

10. **CLOSED 2026-09-20 by the owner's rule, same day it was raised.** Both
   television boxes had been offering a film-only "Watch Together": Google TV
   presented the dialog with no camera check, and Fire TV compiled the whole
   Studio because only the PERMISSIONS are flavour-scoped. I offered the owner
   two options (gate it, or keep it and describe it honestly) and they gave a
   better rule than either — *"a broadcast with no camera and no microphone is
   not watching together ... everyone might as well just watch the movie on
   their own"*. The entry is now gated on `canHostWatchTogether()` (camera AND
   microphone), so **Android Watch Together means the phone and nothing else**.
   Decision 132; 4 unit tests; both flavours compile.

11-NEW. **"WITH FRIENDS AND THE WORLD" IS FEASIBLE AND UNBUILT** (macOS only).
   The owner's own proposal — people use the calling service they already have
   (Zoom, Meet, FaceTime, a phone call), the app owns only playing, syncing and
   streaming — removes the guest-voice transport entirely, and with it the
   relay, the NAT traversal and the running cost that made every previous
   design fail the $0 constraint. **Measured, not assumed** (§8.21): a macOS
   host can capture a NAMED application's audio via
   `AudioHardwareCreateProcessTap` (macOS 14.2+), and the tap EXCLUDES every
   other process at 82 dB — which is what stops the film being captured twice
   and fed back into its own broadcast. `API_UNAVAILABLE(ios, watchos, tvos)`,
   so the HOST must be a Mac; everyone else watches on anything, which is the
   gating the owner already said was acceptable. What is NOT built: the
   cross-platform playback sync (SharePlay is Apple-only, so this needs our own
   — low-frequency, ~2,900 messages for a four-person two-hour film, which fits
   the existing free Worker), the host's picker for WHICH app to tap, and one
   more mixer input. What is NOT known: what TCC prompt a signed, bundled app
   raises, since §8.21 ran as a command-line tool under the terminal's grants.

12-NEW. **DOES THE TELEVISION GET CARDS? (owner decision, nothing built.)**
   Cards — "Starting soon", "Intermission", "Thanks for watching" — are on
   macOS, iOS and, since 2026-09-20, Android. tvOS is now the only platform
   that can broadcast and cannot show one. It is a QUESTION rather than a port
   because Rule 8.8c settles the television's only live surface as "two
   channels, a rotation, and nothing else", and that rule came from the owner
   and a rebuild. PROPOSED Rule 8.8f lays out the four places a card could
   live and what each costs; the short version is that a second transport-menu
   item (B) or nothing at all (D) are the honest choices, that choosing on the
   go-live screen (C) looks tidy and defeats the purpose — an intermission is
   decided DURING a show — and that putting it in the mixer (A) spends a rule
   that was expensive to learn. The WORDS are not in question either way.

13-NEW. **WHEN THE FILM ENDS, THE BROADCAST DOES NOT — AND NOBODY IS TOLD.**
   Measured 2026-09-20 on an iPhone: a 60-second film, a 97-second broadcast,
   and the last 37 seconds are the film's FINAL FRAME frozen, with the camera
   tile and lower third live over it and `state=LIVE fps=30` throughout.
   Continuing to broadcast is probably right — people talk after a film — but
   §4 says health is never hidden, and "your audience is watching a still" is
   health. The feature already has the right graphic for this moment (the
   Ending card) and offers it automatically nowhere. Four options in
   `docs/WATCH-TOGETHER.md` §9.bbbbbb; the hard part in any of them is telling
   "ended" from "buffering", where a false positive is worse than today's
   silence.

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

### 2026-09-20 (evening) — both phones proven, and three things macOS had never learned
Same standing /loop. The owner supplied the two things that were blocking:
YouTube sign-in plus camera/mic on the iPhone 12, and the Pixel's adb pairing
code.

**BOTH PHONES NOW BROADCAST END TO END.** iPhone 12 to YouTube on the product
path — `AWCAM attached camera=Front Camera mic=iPhone Microphone`, `AWPUB
publishing`, `AWPROV provenance cleared 20s after going live` — **confirmed
from YOUTUBE's own side**, the channel's `liveBroadcasts` totalResults going
59 -> 61. Pixel 8a to a real server with film, camera tile and audio
(mean -27.3 dB), read back from the server's own recording. First phone-class
Android numbers ever: **20-22 fps against the Google TV dongle's 13**.

**THE FIRST PHONE FOUND TWO DEFECTS NO TELEVISION COULD.** The display pass set
`glViewport` to the whole host surface — right where both surfaces are 16:9,
wrong on a 1080x2400 phone, so the program went to 2.22:1 and the owner
reported the film "heavily stretched vertically". The §9 warning that "the
viewport belongs to the surface" was already written, from this same defect in
its other form, and it named 1920x1080 as the host's size: that is how the
assumption survived. And **`filmAspect` was declared with a 16:9 default and
assigned by NOTHING**, so every film that is not 16:9 was published stretched —
most of this catalogue, since a silent film is 4:3. Caligari went out filling a
1.778 frame with no pillarbox; it now spans x=160..1120 of 1280, exactly 1.333.

**THE OWNER'S RULE ABOUT WHAT THE FEATURE IS.** Shown that Google TV and Fire
TV were quietly offering a film-only broadcast, they gave a better rule than
either option offered: *"a broadcast with no camera and no microphone is not
watching together ... everyone might as well just watch the movie on their
own."* Decision 132 — the gate is that the HOST can be in the show. Android
Watch Together now means the phone and nothing else.

**AND THE ANDROID TWITCH PATH HAD NEVER OPENED THE HOST AT ALL.** `startIfArmed`
has two exits and the Twitch branch returned without `openHost`, so every
broadcast reaching a real Twitch destination carried the film and nothing of
the person watching it. The bench path had it, which is why the harness never
noticed. Separately `openHost` was a one-shot against a camera texture the
render thread had not created yet — the microphone had had a retry since it was
written, the camera never did, and that asymmetry was the whole bug.

**THREE THINGS macOS HAD NOT LEARNED FROM THE TELEVISION**, all found by
reading tvOS's code rather than the docs, and all the same shape — a behaviour
written into one platform's file and believed to be the product's:
camera-stall RECOVERY (lived in the tvOS view; macOS borrows iPhones and drops
the same way); the **"film's audio is not being sent" warning** (lived in the
same view, and tvOS needs it LEAST — it pulls audio by film position, while
macOS and iOS use the tap that actually fails); and the **Continuity preset
CRASH fix**, which had been applied in `StudioContinuity` alone while the
shared host-camera path still set a preset before adding its input. All three
are now shared, and the Mac was made to BROADCAST rather than merely compile:
camera, mic, both tracks, theatre at 729 px of 1920.

**`.inputPriority` IS UNAVAILABLE ON macOS**, which is the platform that fix is
most for. Copying tvOS's line verbatim would not have compiled — the macOS
verb is to leave the preset at its default `.high`, which negotiates instead of
demanding.

**PARITY WORK THE OWNER ASKED FOR**: *"close gaps that can be closed on any
platform."* Camera placement was broken everywhere — **"Theatre row (you along
the bottom)" was "corner" moved 64 pixels down**, the same tile in the same
corner, on every Apple platform. Android had two of the five placements
(a boolean and a hardcoded corner); tvOS had ONE, with `layout: .corner`
hardcoded in the request. All three fixed; `StudioLayoutTest` pins the Kotlin
numbers to the Swift ones so they cannot drift.

**FOUR INSTRUMENTS LIED TODAY**, which is the recurring lesson rather than a
footnote. `devicectl --console` captures STDOUT only, so every `awdiag` line
(NSLog) was invisible and four launches read as "the harness cannot deliver
environment variables" — it delivers them fine; the DOOR was on the tvOS root
and iOS has its own. `strings` found neither my new literal nor `AWCAP` in a
binary where `AWCAP` demonstrably prints. `-v error` suppresses
`volumedetect`'s own output, so every film read as silent. And a devicectl
screenshot SUCCEEDED against a sleeping television, producing a black frame
that looks exactly like an app rendering black.

**Corrections owed**: I said Android had no OAuth at all — it has Twitch's
device flow, a token store, a sign-in screen and a configured client id, and
that stale note is why Android platform testing kept being deprioritised. I
said the 20-second provenance expiry explained the owner's overlay complaint —
it does not, the expiry works. I wrote a comment into the codebase asserting
`devicectl` could not deliver environment variables, which was never
established, and removed it. And a scripted correction HALF-LANDED: the python
assertion failed on one file while the commit went ahead, so the repo briefly
carried the fix in PARITY and the falsehood in SCRATCHPAD.

**Still owner-gated**: a Twitch device code on the Pixel (raised 18:04, lapsed
unapproved) — one browser approval and Android is proven against a real
platform rather than a bench. And the tvOS placement picker is built and
suite-green but UNPHOTOGRAPHED: `devicectl device capture screenshot` fails on
Ben Bedroom with `com.apple.Mercury.error 1001` whenever the app is actually
rendering, and succeeds only when the panel is asleep.

Suite 110 pass / 1 skip / 0 fail; Kotlin 87 / 6 skipped / 0 fail.

**LATER THAT EVENING — one defect shape, five times, and three blockers that
were never real.**

**THE SHAPE**: a value a host sets that never reaches the engine. Found in
`GoLiveTV.request()` (`layout: .corner` hardcoded), in `DetailView`
(`setLayout(.corner)` hardcoded), in the macOS SHEET (`request.layout` simply
not read, so every Mac broadcast went out as `corner` however the host chose —
and the macOS DOOR waited for `isLive` and set it, which is why every bench run
I had ever done looked right), in Android's engine (read once at arm, so the
picker was inert on the ONE platform whose picker exists only while live), and
in the macOS panel (opening on `.corner` over a show that was doing something
else). Each was found by DRIVING the product, and each one only because the
previous made me look. `StudioSession.armLayout` now removes the timing
question rather than adding a sixth caller that remembers.

**AND I PRODUCED A FRESH INSTANCE WHILE WRITING ABOUT THE OTHERS.** The
camera-stall recovery and the film-audio warning went into
`StudioSession.startPump` and were committed as reaching "macOS and iOS".
**iOS never arms or starts that object** — its container owns an engine and a
loop of its own — so both were inert on the phone, and `StudioControls_iOS`
was reading a warning nothing wrote. The shared TYPE looked like shared
BEHAVIOUR. It surfaced not by re-reading code but by running §6.4 and finding
the publisher's counters missing from the phone's diagnostics: I went looking
for a logging gap and found a behavioural one.

**THREE BLOCKERS THE DOCS ATTRIBUTED TO THE OWNER, NONE REAL.** "Android has
no OAuth at all" (it has Twitch's device flow, a token store, a sign-in screen
and a configured client id — nobody had signed in). The iOS Local Network
prompt (an iPhone and an Apple TV both published to a local server on the first
attempt, no prompt). And item 9a's iOS encoder readout, framed as needing "a
screenshot" — it is a log line, and it says `hardware=true`. Each had been
steering what got worked on, including by me. Killing the second one closed
FOUR rows in ninety minutes: iOS placement on the wire, chat on iOS and tvOS,
and §6.6's reconnect (0.7 s, agreed by both the app and the server).

**§6.4 PASSES ON A PHONE** — queued 0 / 30 fps / 0 dropped, then 1.2-1.6 MB /
1.8 fps / 834 dropped with audio unbroken at 43.8/s, then recovery. An earlier
run of the same test "passed" while nothing happened to the stream, because I
measured `pts_time` from the recording — MEDIA time, continuous by construction
(§9.zzzzz, written down as a negative result rather than quietly re-run).

**PARITY CLOSED**: all five camera placements on iOS, macOS, Android and tvOS,
each proved ON THE WIRE; cards on Android (its panel, its words pinned to
Apple's by test); camera-stall recovery on Android, INDUCED on hardware by
making another app take the camera — where its first readout said "no camera"
over a camera that had just reconnected, because it asked a stale `problem`
string instead of what the re-open returned.

**Still owner-gated, and unlike the three above these are real**: a Twitch
device code on the Pixel (a browser approval), and whether tvOS should have
cards at all given Rule 8.8c keeps that surface to two channels and a rotation.

### 2026-09-20 (Watch Together loop) — the mixer in numbers people read, macOS and Android catching up, and a home screen that trusted the uploader
Owner /loop, 5-minute cron, same standing prompt; redirected several times by
hand — the mixer's visuals, the camera's orientation, iPhone/Android end to
end, SharePlay guest audio, and finally the home screen.

**THE HOME SCREEN WAS ASKING THE UPLOADER, NOT THE AUDIT.** Owner: *"I keep
seeing nazi movies, controversial films, and things with questionable public
domain status."* Home's whole rights gate was `rightsStatus IN
('public_domain','creative_commons') OR year <= 1977`, and `rightsStatus` is
what the ARCHIVE ITEM claims — the field `TVOS-STUDIO-RUNBOOK` §3 already
warns about, which the Studio heeded and Home never did. At the top of Home's
own popularity order: Yojimbo, The Pink Panther, The Grapes of Wrath, High and
Low, Jason and the Argonauts, all `public_domain`, all still owned. Three
tiers now, all from the audit: Home takes KEEP buckets only; `presumed_pd` may
not carry a FOREIGN film, because it is a US renewal-lapse assumption and the
**URAA (1996) restored US copyright in foreign works** (that one rule removed a
Criterion shelf — Tokyo Story, The Seventh Seal, Harakiri, Wages of Fear); and
the HERO takes positive evidence only. **Every Nazi propaganda film is
`presumed_pd` and leaves the marquee while the Allied evidence is `safe_gov`
and stays** — no other field separates those. Android and the tvOS TOP SHELF
carried the identical defect and were corrected too; Roku had it right since
Decision 113.

**macOS AND iOS HAD NOT LEARNED THE 48 kHz LESSON.** The ring and the
sample-buffer retain fixes were shared and arrived free; the resampling did
not. Both tap paths were sample-DROPPING — 35.6 dB SNR at 440 Hz falling to
**10.1 dB at 8 kHz**, aliasing nearly as loud as the signal, on a third of the
catalogue and on the host's own voice. tvOS's `AVAudioConverter` could not be
copied (the tap callback is real time), so `PolyphaseResampler` builds its
kernel once: **95-107 dB** after, guarded by §8.17 with the old hold as the
control. They were also missing the 0-10 mixer and the auto-duck TOGGLE —
`StudioSession.setAudio` had no `duckEnabled` parameter at all, it stopped at
the engine — and the camera-stall warning.

**ANDROID COULD NOT CARRY THE HOST AT ALL**, and a PARITY line I wrote that
morning said otherwise ("its faders are still raw amplitude" — there were no
faders). The manifest declared only INTERNET; there was no `AudioRecord`
anywhere; the camera's RECEIVING end was complete with nothing to feed it.
Built on the owner's go-ahead: Camera2 (no new dependency), `AudioRecord` on
VOICE_COMMUNICATION, a mixer that **mixes INTO the film's buffers and drives
nothing** — because §9.qq is what a second clock cost this platform — the
shared 0-10 scale, and permissions asked at the point of going live,
google-flavour only. 12 tests with controls. **None of it has run on hardware**
and PARITY says so.

**THE §8 SUITE HAD NOT BEEN RUN SINCE 09-19 AND FOUR OF ITS CASES WERE LYING.**
§8.2 asserted the BUG (`prompt=consent`, the thing that sent the first
broadcast to the wrong channel); §8.13 asserted two gates deliberately replaced
by better ones; §8.11 measured the harness's own keychain entitlement; §8.9
demanded a credential withdrawn on 09-18. Each had been failing since the day
its subject was fixed. And the Kotlin back-pressure case failed for a reason
none of my three hypotheses covered: **a stale listener held the proxy's port**,
so the publisher reached mediamtx unthrottled while a TCP-only readiness probe
saw "something is listening". The proxy's own log said so and the test was
discarding it. 13/4 -> **82 pass, 1 skip, 0 fail**.

**WHAT I BROKE, AND IT IS THE POINT OF THIS ENTRY.** Chasing whether SharePlay
could carry guest voice, I put a debug probe inside `WatchTogether.adopt()`,
ON BY DEFAULT, in the product's own join path — and broke SharePlay, which
shipped as Decision 098 and which the owner uses. Four separate
self-inflicted faults in a row: an unbounded 50/s flood; a verdict written
where a tap-launched app could not record it; a CRASH from `data[0]` on a
`Data` SLICE (the subscript is an absolute index, and `count` reads fine on a
slice, so the `>= 5` guard passed and the next line trapped); and confusing
launching the APP with starting the ACTIVITY. Reverted to byte-identical, and
`VoiceFrame` + §8.18's 16 assertions are what survive. **A working feature
outranks a measurement and I inverted that for several rounds.**

Also corrected: SharePlay is not FaceTime (the messenger sends raw `Data` and
guest voice IS buildable — SHAREPLAY §5 is the rule, written before the code
this time); a `GroupSession` CAN be activated programmatically when a call
exists; and the camera's orientation cannot be read at all — `AVCaptureDevice.h`
says external cameras report 0 "even if they physically rotate" — so after
trying a host-stated Portrait option and finding it both wrong-way-round and
82% of frame height, the feature is **landscape only** and the sheet says so.

Older entries: `docs/SESSION-LOG.md` (verbatim, back to 2026-04-17).
