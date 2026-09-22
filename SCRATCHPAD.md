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

0-NEW. **PRESS "ALLOW THE CAMERA" ONCE, IN THE MAC STUDIO** (2026-09-22). The
   macOS product path had NEVER called `AVCaptureDevice.requestAccess` — only
   `StudioLab` (DEBUG), the iOS sheet and the tvOS one did — so
   `authorizationStatus` was `.notDetermined` for the life of the app and the
   Studio's camera row read "not attached" forever with nothing to press. That
   is the owner's *"I cannot seem to attach any cameras (not even the facetime
   camera)"*. The row now offers **Allow the camera** (and **Open System
   Settings** if it has been denied), and `beginShow` asks before building the
   engine. **It is a TCC grant on the owner's own Mac, so it is deliberately
   NOT pressed by the harness** — the same rule as the iPhone's Local Network
   prompt. Until it is pressed, the Mac's camera tile is code that has never
   run, and this line says so rather than claiming a fix that has not been
   exercised. The microphone is already granted (Creation Studio's voiceover).

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
   - **CORRECTED 2026-09-21 by looking at the console instead of the note.** The
     consent screen is NOT in Testing — publishing status is **In production**,
     and has been. So the "refresh tokens expire in 7 days" consequence never
     applied either. The REAL cause of "Google hasn't verified this app" was
     that **Data Access listed no scopes at all** — not sensitive, not
     restricted, none — while the app requests `…/auth/youtube` at runtime. The
     Audience page says it in as many words: "If your users are seeing the
     'unverified app' screen, it is because your OAuth request includes
     additional scopes that haven't been approved." An undeclared scope is an
     unapproved scope.
     **Done 2026-09-21**: the scope is declared with a written justification,
     the app logo (the 1902 Méliès still, 120x120 from the app icon) is
     uploaded, and BRANDING VERIFICATION is submitted — an automated check
     Google says takes up to five minutes. Home page, privacy policy,
     authorized domain and developer contact were already correct.
     **BRANDING IS NOW VERIFIED AND PUBLISHED** (2026-09-21): "Your branding has
     been verified and is being shown to users." The failure on the first
     attempt named its own cause — *"The website of your home page URL
     'https://archivewatch.org' is not registered to you"* — so
     `google23384a8cb98dcec2.html` was added at the repo root (deploy-pages
     rsyncs the root into `_site`, so a root file publishes), Search Console
     verified ownership by HTML file, and re-verification passed. **That file
     must never be deleted**: Search Console re-checks it and losing the
     property would fail the branding check again.
     **ONE FIELD STANDS BETWEEN US AND A CLEAN CONSENT SCREEN: the DEMO VIDEO.**
     Prepare-for-verification shows everything else green — branding summary,
     the declared scope, the written justification — and says "Missing the
     following fields for one or more requested scopes: demo video." Confirm is
     greyed until a YouTube link is supplied.
     The video must show the consent flow for `…/auth/youtube` and include every
     OAuth client on the project. Google is explicit that it must NOT be
     recorded against production traffic — use a staging route or a separate
     project — and that the unverified-app screen is EXPECTED to appear in it.
     The recording is a job for the Mac; the UPLOAD is the owner's, since it
     goes on their channel.
     **RECORDED 2026-09-21: `~/Desktop/ArchiveWatch-OAuth-demo.mp4`** (73 s,
     1422x800). It shows the Detail page, the film playing, the Go Live sheet
     with the rights line, Apple's "Archive Watch Wants to Use
     accounts.google.com", Google's unverified-app screen, Advanced -> "Go to
     Archive Watch (unsafe)", the consent screen and Continue. The account
     chooser is deliberately cut out — it lists the owner's family's email
     addresses and must not reach a file Google reviews.
     **ONE CAVEAT BEFORE SUBMITTING**: the consent screen collapsed the scope
     into "Archive Watch already has some access" because that brand account
     had already granted `auth/youtube`, so the video does not print the scope
     in words. If a reviewer bounces it, revoke Archive Watch at
     myaccount.google.com/permissions and re-record that ~20 seconds — the
     scope line renders in full on a fresh grant (seen today on another
     account). Use **benwilkoff@gmail.com**: the owner confirms the channels
     approved for live streaming (Learning is Change, Archive Watch) are
     there, not on ben@learningischange.com.
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
   **CORRECTED 2026-09-21: macOS COULD NOT SIGN IN AT ALL until today, and
   this line said otherwise since 09-18.** It was true of the CODE — the
   shared sign-in row, Rule B13g's sheet content, a real
   `ASWebAuthenticationSession` anchor — and false of the product, which is
   Decision 133's defect in its purest form. Two blockers, both found by
   running the go-live sheet on a Mac for the first time since the ids were
   registered: (a) `macOS/Info-macOS.plist` never declared
   `YOUTUBE_CLIENT_ID`/`TWITCH_CLIENT_ID`, so there was nothing for the build
   setting to substitute into and `info("YOUTUBE_CLIENT_ID")` returned nil on
   every Mac build ever made (`plutil -p` on the built app found no key); it
   also lacked the OAuth redirect scheme, which is the BUNDLE ID (Decision
   128). (b) With those fixed, pressing Continue at Google **killed the app** —
   `ASWebAuthenticationSession` is not `NS_SWIFT_UI_ACTOR` in the SDK, so its
   completion closure inherited main-actor isolation from our type and Swift 6
   emitted a dynamic check; iOS and tvOS deliver on the main queue so it passed
   for a year, macOS delivers on an XPC reply queue and it TRAPPED.
   `{ @Sendable ... }` fixes it. **The Mac has now completed a sign-in**
   (v1.42.441–442). **tvOS still cannot** — it has the engine, the
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

13-CLOSED 2026-09-21 (option A). Every Apple surface now says "the film has
   ended — your audience is watching a still", and macOS offers the
   "Thanks for watching" card as a BUTTON rather than imposing it, because the
   owner's rule is that the host decides when a show ends. §9.bbbbbb thought
   the hard part was telling "ended" from "buffering" via `filmFramesPulled`;
   it dissolves by asking the PLAYER (`didPlayToEndTimeNotification`) instead
   of a counter. It lives in `StudioEngine.attachFilm` — the one function
   macOS, iOS and tvOS all call — because I wrote it into `StudioSession`
   first, where it would have been inert on two platforms out of three.
   **Android is not covered.** Original item follows.

13-orig. **WHEN THE FILM ENDS, THE BROADCAST DOES NOT — AND NOBODY IS TOLD.**
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

16-NEW. **WATCH TOGETHER ROOMS ARE BUILT AND THE WORKER IS DEPLOYED** (SHAREPLAY
   §11, 2026-09-21). The owner's own design: people use the call they already
   have, the app syncs the film. The transport is LIVE at
   `archivewatch-pulse.benwilkoff.workers.dev` (the same Worker as the privacy
   counter, on the same D1 — no new infrastructure, which is why it fits the $0
   constraint). Smoke-tested live including the counter beside it.
   **JOINING SHIPS on macOS, tvOS, iOS, Android phone, Android TV, Fire TV and
   the web.** HOSTING is macOS only, and that is settled rather than missing:
   the owner ruled that rooms exist to serve a LIVE STREAM, so a room with no
   broadcast is not a product (§11.13).
   **What is NOT done**: Roku's surface (the rule and the poll task exist, and
   nothing creates them — PARITY says so); and no room has ever been driven
   between two REAL devices, only between two clients on this Mac against the
   live Worker.
   **The rule that makes a spoken code work is in FIVE languages** — Swift, the
   Worker's JS, Kotlin, the browser, BrightScript — with §8.28/§8.29/§8.32 and
   `StudioRoomTest` asserting the same input table and §8.34 pinning the
   alphabet across all five.

15-NEW. **THE CODE IS PUBLIC AND THE HOST KEY IS NOT** — learned from the
   owner's Tidbits Trivia, whose own screen says "the room code alone cannot
   drive the show". This transport had NO auth: any guest who heard a code
   could pause somebody's broadcast. Fixed and asserted live (a guest write is
   403, the room is unchanged, a GET never carries the key).

14-NEW. **WHAT A SIGNED, SANDBOXED APP GETS FROM A PROCESS TAP IS UNKNOWN.**
   The Studio's fourth input — a call's audio, the piece that makes "With
   Friends and the World" real — is built and tested (§8.26), and §8.21 proved
   the mechanism at 82 dB of isolation. But §8.21 ran as a COMMAND-LINE TOOL
   under the terminal's grants, which is exactly Decision 130's "a harness can
   prove the logic and say nothing about where the logic RUNS". A process tap
   has its own TCC service, which the microphone entitlement does not cover;
   `NSAudioCaptureUsageDescription` is now in the macOS Info.plist. **Two
   minutes to settle**: Watch Together -> Open the Studio -> pick an app under
   Inputs, and `StudioSession.callProblem` prints whatever macOS says. It is
   written to say it rather than leave a silent channel.

15-NEW. **THE ANDROID MARQUEE HAD NO RIGHTS GATE OF ITS OWN** (found and fixed
   2026-09-21 from the owner seeing "Dollar Store Killers", a 2025 film, on the
   hero row). Its hero pool asked `browse(homeOnly = true)` and so inherited
   HOME's rule, which admits `presumed_pd` and `safe_archive_license` — both
   excluded from the marquee on every Apple surface since 09-20. It had been
   headlining **The Pink Panther, The Grapes of Wrath, Gentlemen Prefer
   Blondes, Frankenstein (1931), Jason and the Argonauts**: the owner's 09-20
   complaint, only ever half-answered. Fixed in SQL on Android (it could not be
   fixed in Kotlin — `browse` selects `liteCols`, which carries no
   `rightsBucket`), and a modern-year rule added on all four platforms.
   **STILL OPEN AND OWNER-RESERVED**: 347 modern-year items sit in KEEP buckets
   on `rightsEvidence: "source_unverified"`, including **Taxi Season 1** (1980)
   and Die Harald Schmidt Show (1995). That is the same class as the television
   audit below and is a Decision 027 content call.

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

### 2026-09-22 — the Studio became the whole surface, and a button learned to say what it does

The owner ran the shipped macOS Studio for the first time and reported six
things. **Four of them were not defects in the build — they were rules that
were wrong, faithfully implemented** (Decision 134, macOS-DESIGN §D7-§D13).

**THE STUDIO NOW CONTAINS THE BROADCAST.** §D1 gave it a window and left the
film in a different one, so it was a window of controls for a show it did not
hold. It now carries a FILM CHOOSER (search the catalogue from inside it;
rights-refused titles are SHOWN with their reason — *"This film is probably in
the public domain but nothing proves it"* — rather than hidden), the film's own
player in a **SOURCE** pane beside the **PROGRAM** preview (§D8, OBS's split),
and "Open in a separate window" that MOVES the film out for projection and
never copies it. Seen on the glass at 1300x1000 with Caligari and with Buster
Keaton's *The Scarecrow*.

**THE GO-LIVE SHEET IS DELETED.** Rule B13g asked where a host PRESSES Go Live
and never where they DECIDE to, which is how the owner found it: *"I think I may
have found it hidden behind a button on the video player (rather than in the
studio for some reason.)"* Everything it carried is the Studio's **Output**
column now — platform, the shared sign-in row (reading **"YouTube — Learning is
Change"** on this Mac), the readiness answer, the title, privacy, the rights
sentence, and a Go Live that is disabled with the reason above it. ⇧⌘L and the
player's toolbar button open the Studio.

**THE CAMERA HAD NEVER BEEN ASKED FOR.** *"I cannot seem to attach any cameras
(not even the facetime camera) to the studio."* They could not: nothing in the
macOS product path has ever called `requestAccess`, so
`authorizationStatus` was `.notDetermined` for the life of the app and the row
read **"not attached"** forever with nothing to press. The rule behind it —
*"the Studio REPORTS, never REQUESTS"* — came from tvOS, where a prompt in a
living room is a real intrusion, and on a Mac it was a dead end with a label on
it. Four states now say their own names, with **Allow the camera** on
`.notDetermined` and **Open System Settings** on denied. **OWNER STEP: press
Allow once.**

**AND THE DEVICE PICKERS ARE LIVE.** §D2 said "device changes take effect on
the next broadcast", from a true fact (an `AVCaptureSession` is built once) and
a wrong conclusion: the capture session is not the encoder, the tile is
COMPOSITED, and the wire never learns which device made the pixels. §D4's "not
while live" belongs to resolution and frame rate alone.

**A CARD OF THE HOST'S OWN WORDS** (§D10) — four lines, each ranked Display /
Heading / Body / Caption from the project's own six levels. Rendered and LOOKED
AT (`build/qa/studio-overlay/card-custom*.png`): empty lines dropped, one-line
and four-line cards both optically centred, same wordmark and rule as the three
fixed ones. **Writing it produced a chicken-and-egg bug that only the glass
found**: the picker read its value back out of `card`, and §D10 says an empty
custom card is never shown — so choosing "My own words" set `card` to nil, the
picker snapped back to "No card", and the editor never appeared. The CHOICE is
now its own state, separate from what the engine is drawing.

**THE BUTTON RULE TOOK TWO PASSES, AND THE FIRST ONE WAS WRONG.** *"Button
text should never be truncated or abbreviated."* The first answer was a
wrapping `Layout` — which kept the words and destroyed the design: seven large
buttons reflowed into three ragged rows with "Share" stranded alone on the
last. The owner, correctly: *"We don't want button wrapping. We want actual
designed buttons that say what they mean and perform like macOS buttons
should."* So `ViewThatFits` over arrangements that were each DESIGNED — at
1500 points all seven; at 1150 **Play · Favorite · Add to Playlist · More**; at
the 960 minimum **Play · Favorite · More** — with every control `.fixedSize()`
(without it the first arrangement always "fits", by squeezing) and a native
More menu that still says every word. The layout was deleted. The rule reaches
past buttons: the same screen was rendering "Rev. Arthur Di…" and "Roger Prynne
a…" under cast portraits, and the row was centre-aligned so portraits hung at
different heights.

**THE FILM THAT WOULD NOT STOP** (§D12). *"The movie continued to play and then
when I opened the interface back up, a new copy of the movie started playing …
there is no way to stop the audio at all at that point."* `teardown()` did
everything its name implies except stop the player: it removed observers,
cancelled tasks and saved progress, and left the `AVPlayer` running — and macOS
keeps a closed `WindowGroup` window's `@State`, so the player survived with no
view left to pause it and the next open built a second one over the first.
**Measured**: 4.0% CPU playing → **0.0% after the red button**, and re-opening
landed on Detail rather than a second copy.

**A defect I introduced and caught by reading the projection path**:
`forgetSurfacePlayer` was keyed on the archive id, and moving a film between
the Studio and the projection window tears one surface down and builds another
for the SAME id — with no ordering promise, a late teardown would forget the
registration the new surface had just made. It compares the PLAYER now.

Builds green on macOS, iOS and tvOS. v1.42.477 (1489).

### 2026-09-21 — the Mac Studio finished, and Watch Together got a transport

Owner /loop, 5-minute cron, standing prompt: *"continue to work on the
identified issues and feature buildout until you have solved for all
documented issues and we have a fully functioning OBS-like studio on MacOS for
live streaming."* Redirected repeatedly by hand — the demo video, discoverability,
code length, Tidbits, what a surface may advertise — and stopped by the owner
when the scope was done.

**THE macOS STUDIO IS BUILT AND MEASURED** (macOS-DESIGN **Part D**, §D0-§D6,
written this session and renumbered from a second "Part C" that collided with
the shipping one). A real `Window("Watch Together Studio")`: PROGRAM PREVIEW
across the top, then Inputs / Mixer / Output. All six build-order steps ship.

- The preview draws **the engine's own `CVPixelBuffer`**, published from the
  one line that hands a frame to the encoder and put on a `CALayer` as an
  IOSurface. Not a second composite — Decision 133's failure is exactly "what
  I see" diverging from "what they see". The displayed buffer is RETAINED,
  because `CVPixelBufferPool` recycles on last release and a buffer that is
  only on screen can be drawn into while the display reads it.
- **Device pickers** (§8.24). This Mac reports **four cameras** — FaceTime HD,
  Airtime, OBS Virtual Camera and the owner's iPhone over Continuity — and
  seven microphones, and `AVCaptureDevice.default` had been silently taking
  the first. A host who wanted their phone had no way to ask.
- **Output settings** (§8.25), size and frame rate locked while live because
  an RTMP ingest will not accept a change mid-publish, bitrate live because
  the encoder genuinely supports it. `config` became a `var` for one reason
  worth knowing: §6.5 restores to `config.videoBitrate` after a thermal step,
  so a stale value would have undone the host's choice minutes later.
- **A call's audio as a fourth input** (§8.26) — `AudioHardwareCreateProcessTap`
  over a named app, a third mixer channel that ducks the film as the host's
  voice does. What a SIGNED, SANDBOXED app gets from TCC is still unmeasured
  (§8.21 ran as a CLI tool under the terminal's grants), and
  `callProblem` carries the refusal so the answer lands on screen.
- **A preview that runs before going live**, which exposed that `isLive` never
  meant on-air: it has always meant "the engine is running", and on macOS the
  engine runs with no destination whenever a film is armed. Two things broke
  the moment a rehearsal existed — the Go Live button hid itself, and
  `attachIfArmed`'s `!isLive` guard silently swallowed the arm for a real
  broadcast. `isOnAir` and `isRehearsing` now say which is meant.

**PROVED ON THE WIRE**, which is the standard: settings set to 1280x720 @ 24
fps / 3000 kbps — none of them the old hardcoded default — published to a
local mediamtx and read back from the server's own recording as
`h264 High level 31, 1280x720, 24/1, 2481440 bps, aac 44100 stereo`, with the
film, the camera tile and the lower third all in one frame.

**AND THE TEN-MINUTE SOAK HAD NEVER BEEN ABLE TO COMPILE.** §8.3 is the
reliability gate and it is skipped by default; run with `--soak` it failed to
build, because its file list omits `$SHIM`. The suite's own rule found it —
*a SKIP is not a PASS* — and the case was not merely unrun but unrunnable,
which a default skip makes indistinguishable. Fixed, and it passes: 18,001
frames, **zero dropped**, 29-31 fps, queue peak 2% of cap, **memory DOWN
0.3 MB**.

**THREE DEFECTS FOUND BY RUNNING THE PRODUCT PATH ON A MAC FOR THE FIRST TIME
SINCE THE IDS WERE REGISTERED.** SCRATCHPAD had claimed since 09-18 that
"macOS can now sign in and go live"; it was true of the code and false of the
product.
1. `Info-macOS.plist` never declared `YOUTUBE_CLIENT_ID`/`TWITCH_CLIENT_ID`,
   so `info(...)` returned nil on every Mac build ever made, and it lacked the
   OAuth redirect scheme (the bundle id).
2. With those fixed, pressing Continue at Google **killed the app**:
   `ASWebAuthenticationSession` is not `NS_SWIFT_UI_ACTOR`, so its completion
   closure inherited main-actor isolation and macOS delivers it on an XPC
   reply queue. `{ @Sendable ... }` fixes it. **The Mac has now signed in.**
3. The first sign-in showed one sentence TWICE — the shared row and all three
   go-live sheets each drew the readiness warning. Removed from all three.

**AND THE OAUTH SCREEN STILL SAYS "Google hasn't verified this app."**
Verifying the BRANDING was not verifying the APP for a sensitive scope. The
demo video is recorded (`~/Desktop/ArchiveWatch-OAuth-demo.mp4`, 73 s) with
one caveat written beside it: the consent screen collapsed the scope into
"already has some access" because that brand account had granted it before.
Revoke at myaccount.google.com/permissions and re-record those 20 seconds.

**WATCH TOGETHER ROOMS: a transport, and it is DEPLOYED.** SHAREPLAY §11,
designed in answer to the owner's questions and built across five languages.
A host publishes STATE, never the playhead; clients extrapolate; the clock
comes from Cristian's algorithm keeping the **smallest** round trip, never the
average, because the error bound is RTT/2. Drift is closed by a 3% rate nudge
(Decision 081's rule for captions) and only seeks past two seconds. Joining
ships on macOS, tvOS, iOS, Android phone, Android TV, Fire TV and the web;
hosting is macOS only and that is SETTLED — the owner ruled rooms exist to
serve a live stream. **Roku has the rule and the poll task and NO surface**,
and PARITY says so.

**TIDBITS TRIVIA FOUND A REAL HOLE.** Asked what could be learned from it:
its own screen says *"The PIN is on the host screen, not the projector — the
room code alone cannot drive the show."* This transport had NO auth, so any
guest who heard a code could pause somebody's broadcast. Fixed with a
`hostKey` returned once at creation and asserted live (guest write 403, room
unchanged, a GET never carries it). **The owner corrected my reading** — 
Tidbits has one host and several surfaces, not guests who might drive — and
the correction is in §11.12 rather than smoothed over.

**DEPLOYING FOUND WHAT NO TEST COULD**: the Worker is **not** on
archivewatch.org (that is GitHub Pages) but at
`archivewatch-pulse.benwilkoff.workers.dev`, and all three clients were
pointed at the site. Every test passes a base URL, so every test was happy.

**THE ANDROID MARQUEE HAD NO RIGHTS GATE OF ITS OWN.** From the owner seeing
"Dollar Store Killers" (2025) on the hero: its archive item lists
`collections: ["prelinger"]`, so the audit bucketed it `safe_gov` while
recording `rightsEvidence: "source_unverified"` — a field no client can read.
Android's hero used the HOME gate, so it had been headlining **The Pink
Panther, The Grapes of Wrath, Gentlemen Prefer Blondes, Frankenstein (1931)**
— the owner's 09-20 complaint, only ever half-answered. Fixed on all four
platforms. **347 modern-year items sit in KEEP buckets on unverified
evidence** (Taxi Season 1 among them) and that is an owner call, not absorbed.

**WHAT A SURFACE MAY SAY.** Owner: *"You shouldn't advertise features that
don't exist on the platform you are currently on, but you should definitely be
able to share what the current platform can do."* That sharpens Decision 131,
which had surfaces explaining their own absences — an explanation of something
unavailable is still an advertisement for it. `WatchTogetherHere` derives the
list, because five surfaces describing a feature in their own words is five
chances to promise something.

**TWO INSTRUMENT FAULTS OF MINE, both the same shape.** §8.6 back-pressure
failed because I had a wrangler, a mediamtx and a soak server running at once
and the throttle proxy could not create congestion. And **§8.21 was failing
because the owner was USING their Mac**: the tap follows the default output
device, a headset in call mode runs at 24 kHz, and the test tones resampled to
nothing while the control came back louder than the signal. It now SKIPS with
the device rate in the sentence — a red line that really means "somebody is
using this Mac" teaches a reader to discount red lines.

**I leaked the owner's screen again**, and the fix is the instrument rather
than the care taken: a region capture of the Studio's own bounds caught a
Minerva grading queue with student names in it, because the window was not in
front at the shutter. Deleted unread. The memory already said "activate first,
then capture its bounds"; that is a RACE. `tools/mac_window_shot.swift` uses
`screencapture -l<CGWindowID>`, which captures a window's own content whatever
overlaps it. **Never pass `-R` on the owner's machine.**

Suite 135 pass / 2 skip / 0 fail (the soak, run and passed separately; §8.21,
machine in use). Kotlin 89/0/0.

Older entries: `docs/SESSION-LOG.md` (verbatim, back to 2026-04-17).
