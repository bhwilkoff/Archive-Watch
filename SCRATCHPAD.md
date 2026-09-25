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
social program posts daily to five platforms (`docs/SOCIAL-PROGRAM.md`,
Decision 120).

**What to build next in the Studio**: `docs/WATCH-TOGETHER-ROADMAP.md`
(2026-09-22) — OBS/StreamYard researched against what we already have, ranked,
with the two items that need an owner decision named as such.

**Where the rules live** (read before changing the thing they govern):
`docs/ENGINEERING-PROCESS.md` (the eleven disciplines) · `PARITY.md` (what
ships where) · per-platform binding design docs `docs/tvOS-DESIGN.md`,
`docs/iOS-DESIGN.md`, `docs/IPAD-DESIGN.md`, `docs/macOS-DESIGN.md`,
`docs/ANDROID-DESIGN.md`, `docs/TV-DESIGN.md`, `docs/ROKU-DESIGN.md`,
`docs/WEB-DESIGN.md` · `docs/DEVICE-TESTING.md` (real hardware only, never
emulators) · `docs/CAPTIONS.md` · `docs/SHAREPLAY.md` ·
`docs/PLAYLIST-SHARING.md` · `docs/CATALOG-CONTRACT.md`.

**RESUMING THE STUDIO LOOP**: `docs/STUDIO-LOOP-RESUME.md` (2026-09-23) — the
prompt verbatim, the bench-harness recipe that produces a real broadcast, the
six open threads in order, and the traps that cost time this session. Written
because the loop was stopped mid-stride for a Claude update.

### Open owner items (nothing else is blocked)

0-NOW. **GOOGLE OAUTH: RESUBMITTED 2026-09-24, NOTHING TO DO UNTIL GOOGLE REPLIES.**
   New demo video <https://youtu.be/N0zP6D6hOm8>, Console link + justification
   updated, reply sent on Google's thread (docs/oauth/VERIFICATION-REPLY.md).
   Everything below in item 7 about the demo video is history. After approval:
   add the Terms of Service URL to Branding (audit A9).

0-DECIDED-2026-09-25. **SIX OWNER CALLS, ANSWERED — IN PROGRESS.** Asked as a
   series; the answers, verbatim where the owner wrote their own:
   1. ~~Modern CC-only titles: *"If you have proof of genuine creator CC, then
      you can release them. Otherwise, it is clear that many of these have no
      business being in an app built to watch the public domain. Unless we
      have evidence for CC or PD, an uploader's word is not enough."*~~
      **LIVE 2026-09-25** (Decision 140): 1,387 hidden as
      `uploader_licence_only`; 7 kept on Wikidata evidence (Star Wreck, Fossils…).
   2. ~~Home's community rows take the HERO's evidence bar (Home only).~~
      **LIVE 2026-09-25**: all three index rows 60/60 hero-safe; apps via `heroRightsAnd`/`heroAnd`.
   3. ~~"New to Archive Watch" Home row: yes, all platforms.~~
      **LIVE 2026-09-25**: `new-arrivals` (addedAt within 45 days), 1,325 in
      item_shelves, 60 in the index; rule in all seven design docs.
   4. ~~Director rows ranked by popularity, computed in the pipeline.~~
      **LIVE 2026-09-25**: `director_rank` (60) + index `directorRank`;
      Roger Corman, Izzy Sparber, Dave Fleischer, Sam Newfield lead.
   5. ~~Television typed as film (Roots, The World at War...): retype as TV,
      decide with the TV rights question.~~ **LIVE 2026-09-25**: 50 of the 52
      curated ids are TV in the live DB (2 are hidden); the 1942 US-government
      "TheWorldAtWar" stays a film.
   6. ~~The TV rights question (section below): apply the film audit to TV,
      hide what fails, gate TV backfill so it cannot refill.~~ **LIVE
      2026-09-25**: `audit_tv_rights --apply` runs in tv-canonical; 1,920 items
      removed (manifest `tv_rights_removed.csv`), from EVERY spine they were
      matched onto, and a manifest item stays removed on later runs. Live
      episodes-index: 0 of 2,678 are removed items. Getting there exposed a
      publish-db push loop that went green with a stale index (7d6359537).
   Work order: 1, 5, 6 (rights) then 2, 4, 3 (Home). Each lands as its own
   commit and is struck from this item when live.

0-NEWEST-2. **THREE SMALL OWNER CALLS FROM 2026-09-23** (nothing blocked on them).
   (a) The social poster's YouTube token is `youtube.upload` only, so
   `social_metrics.py` has never read a YouTube view or like (14 × HTTP 403 a
   run). Fix = a read scope on that token OR a YouTube API key — and the read
   scope lives in the Google project whose OAuth verification is pending, so it
   is yours. (b) Twitch `tags` (`PublicDomain`, `SilentFilm`…) were NOT sent,
   because `PATCH /channels` REPLACES a host's own tags on every go-live. (c) A
   default Twitch category / YouTube `categoryId` is editorial.

0-NEWEST. **TWO CATALOGUE ENTRIES FOR ONE BUSTER KEATON SHORT, AND THE CAUSE
   IS EXACT** (owner, 2026-09-22: *"there are two different copies of 'The
   Scarecrow' (one with sound and one without) ... Why are there two versions
   of the same movie that aren't folded together as different versions that can
   be pulled in the versions picker?"*). Not fixed; the cause is measured and
   the fix is a catalog-pipeline change of its own.

   | | `TheScarecrow1920` | `the-scarecrow` |
   |---|---|---|
   | title | `Buster Keaton's "The Scarecrow"` | `The Scarecrow` |
   | imdbID | *(none)* | `tt0011656` |
   | runtime | 1085 s | 1140 s |
   | audio | **none** | AAC |

   **Decision 040's merge never considered them**, because it clusters by
   normalized title FIRST and only then asks `_same_film`. Run against the two
   titles, `build_sqlite._dupe_title_key` returns `busterkeatonsthescarecrow`
   and `scarecrow` — different clusters. And `_same_film(a, b)` on those two
   records returns **True**: one carries an imdb anchor, the other none,
   runtimes are 5% apart against a 40% tolerance. So the ONLY thing standing
   between these two cards is the uploader's `Buster Keaton's ` attribution
   prefix, which `_DUPE_QUALIFIERS` does not strip.

   **The narrow fix, and why it is not just "strip a possessive".** Stripping
   any leading `<Word>'s ` would turn *Pandora's Box* into `box` and invite an
   over-merge. The uploader convention here is stronger and safer: when a title
   contains a QUOTED substring, the quoted part IS the title —
   `Buster Keaton's "The Scarecrow"` → `The Scarecrow`. That is testable,
   bounded, and does not touch unquoted titles at all. It needs a catalog
   rebuild to take effect, which is why it is its own change set.

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
   prompt. **DONE, same day**: the owner pressed Allow, and the product path
   then measured `AWCAM video=AVAuthorizationStatus(rawValue: 3)` (authorized)
   followed by `AWCAM attached camera=FaceTime HD Camera` and a 1920x1080 BGRA
   frame. The camera tile is on the wire in the STREAM preview.

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
   catalog, since a silent film is 4:3. Both fixed and verified from the
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
   more mixer input. **The TCC question is now ANSWERED** (item 14 above): a
   signed, sandboxed Archive Watch taps a named app with no prompt and no
   refusal, and captures that app alone. So of the three things this item
   listed as missing, the mixer input and the host's app picker are built and
   proven; what remains is the cross-platform playback sync, and §11's room
   transport is now live, which is most of it.

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

17b-CLOSED 2026-09-23 — THE SECOND BLACK-PROGRAM CAUSE. The Mac player
   swaps its AVPlayerItem ~10 s into a show and the engine's video output and
   audio tap stayed on the old item (`outputOnItem=n`). The engine now follows
   the item; verified from the server's frames; §8.50. Why the player swaps
   at all is still unmeasured.

17-CLOSED 2026-09-22 — the cause was exact once it was LOOKED FOR rather
   than reproduced. `PlayerSurface.teardown()` calls
   `replaceCurrentItem(with: nil)` on the player IT owns, and the engine may
   be holding that same object — leaving the compositor pulling from a player
   with no item. §D12's fix (a departing surface stops its film, from the
   owner's "no way to stop the audio at all") is right when a WINDOW closes
   and wrong when SwiftUI merely REBUILDS the view, which is exactly why it
   was intermittent: whether a rebuild lands during a live show is timing.
   Guarded now by `StudioSession.engineIsUsing(_:)`, with `end()` releasing
   the player the surface declined to — and only when the surface is already
   gone, so a show ending under a visible player leaves it playing. §8.45
   holds the shape and goes red when the unconditional teardown is put back.
   **`forgetSurfacePlayer` had been printing the answer all along**: it logs
   `engineHolds=YES` in precisely this case and did nothing with it. A
   diagnostic that names a condition nobody acts on is half a fix.
   Original item follows.

17-orig. **THE MAC'S PROGRAM GOES BLACK ABOUT ONE RUN IN FOUR, AND NOTHING SAYS
   WHY** (2026-09-22, reproduced twice in eight). The FILM pane plays at 25 fps
   beside a STREAM pane that is black behind the lower third and the camera
   tile, the film row reads "no new frames", and the log of a black run is
   IDENTICAL line for line to a healthy one — both get a first video frame
   (`AWCLOCKS`) and then the pump stops in silence. Six runs afterwards were
   healthy, so there is no signature yet and this is NOT claimed as fixed.
   What IS done: `AWSURFACE register` / `forget` / `engine attaching` now carry
   the `AVPlayer`'s IDENTITY, because the leading theory is that a rebuilt
   player surface nils the item the engine is pulling from (§D12's
   stop-the-film fix, correct where it was applied) and no line could ever have
   shown that; and §D21 puts the CAUSE on screen under the film row after
   three silent seconds — "the film's player has no item — its window was
   probably rebuilt" is one of its six sentences, so the next occurrence names
   itself. §8.40 covers every branch and their ORDER.
   **One thing that is NOT this defect, and cost twenty minutes**: the first
   black run was my own door. `AW_STUDIO_MAC=1` calls `router.play()` directly,
   which MOVES the film to the projection window — a thing the product
   disables while live, with the reason in the button's help text. A door that
   reaches a state the UI forbids produces a very convincing false defect
   (Decision 133 from the other direction).

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

14-CLOSED 2026-09-22 — **A SIGNED, SANDBOXED APP GETS THE AUDIO, AND ONLY
   THAT APP'S AUDIO.** Measured on the product path with Chrome playing a
   440/660 Hz tone:

       AWCALL door selected=Google Chrome pid=768 objects=3 problem=none
       AWCALL app=Google Chrome samples=1645568 level=0.7453 running=true
       AWCALL app=Google Chrome samples=1694208 level=0.0000 running=true
       AWCALL app=Google Chrome samples=2032128 level=0.0000 running=true

   No TCC refusal; three Chrome audio objects (the browser and its helpers)
   tapped as one. **And the negative control is the half that matters**: the
   third line is the moment that Chrome was closed — the level fell to exactly
   0.0000 while `samples` kept climbing, i.e. the tap still running and now
   delivering silence — **while the film was playing its own soundtrack the
   whole time** (*Safety Last!*, `filmHasAudio=true`). So the tap captures that
   app and nothing else, which is §8.21's 82 dB isolation confirmed where it
   counts: the film cannot be captured twice and fed back into its own
   broadcast. The rate corroborates as well — ~48,600 frames a second is the
   output device's 48 kHz, resampled to the program's 44.1.
   `AW_STUDIO_CALL="Google Chrome"` is the door that makes it repeatable.
   Original item follows.

14-orig. **WHAT A SIGNED, SANDBOXED APP GETS FROM A PROCESS TAP IS UNKNOWN.**
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
   Fireplace. Movie Room is provisioned since 2026-09-24 (DEVICE-TESTING §1).

---

## RESOLVED 2026-09-25 (owner: apply the film audit to TV) — television had never passed the rights audit

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
`modern_copyright_unconfirmed` — the audit wants a license check before
hiding, by design (it never hides on a failed fetch). A 24-show sample of
that confirm step: **23 have no license at all**; one (The Man from Snowy
River, 1994) carries a genuine CC public-domain dedication and would be
correctly rescued. Names in the hide set include Murphy Brown, Knight Rider,
The Dukes of Hazzard, Freddy's Nightmares, Designing Women, Minder, Count
Duckula, Honey I Shrunk the Kids, and a 2025 documentary.

**Addendum 2026-09-24 — television typed as FILM escapes this audit too.**
48 visible film-typed items carry episode markers or TV collections; beyond
NASA's own series (government work, fine) they include Roots (ABC 1977, 8
parts), The World at War (Thames 1973-74) and Destination America, all typed
`short-film`. They are catalog items, so the series-spine fix below would not
reach them; whatever the owner decides for television should cover them too.

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

### 2026-09-24/25 — the catalog loop: sourcing that actually runs, one hero rule, connected films

Owner /loop (5-minute cron): *"further enhancements for the title/movie
database ... better sourcing of missing movies ... ways to connect movies
together ... audits of home screens and hero rows ... better workers/action on
GitHub."* v1.42.641 -> v1.42.663. `tools/verify_catalog_changes_2026_09_24.py`
reads the live plane; it went 0/7 -> 7/7.

**Sourcing**: the nightly sweep re-read the top 600 of each collection forever
(6,521 feature_films never queued); two collection ids were wrong-cased and one
did not exist. Ingest spent 881 of 900 slots on stale entries, newest-first. All
fixed; the first run ingested 885 (was 18), 625 visible, oldest first; 331
matched with art within hours. Guards added because the volume made them
necessary: a queue ceiling, holds for modern licence-only uploads and for age
claims the title contradicts, and "a year before 1874 is not evidence".
PD-by-age backfill (1880-1927, 300 a night) is ON.

**Connections**: More Like This ranked once in the pipeline (Decision 139) by
series, director, cast, writer, keywords and archive subject tags — 17,243
films, verified on the web and on the Roku. 19 film-series Collections.
Franchise search.

**Home/hero**: web and Roku had no hero rights bar (46% / 67% of their pools);
Home shelves admitted modern titles on an uploader's licence; the web's
curated shelves were starved (Silent Era 7 vs 3,467). All fixed and live. Owner
calls recorded above: items 0-NEWEST-3/4/5 and the TV-rights addendum.

**Mistake**: a Roku `mediaType=movie` deep link PLAYS; Metropolis ran ~80 s
in the bedroom (memory `roku_deeplink_movie_autoplays`).

### 2026-09-24 (evening) — the Studio run across every test device, after the Mac restart

Owner: *"Can you resume testing the Watch Together Studio across all of my
testing devices? In particular, you were struggling to install on the Apple
TVs ... I've fully restarted and updated the mac."* v1.42.636 -> v1.42.640.

**The restart was the fix** for the TVs' `unavailable / transport None`; the
documented lease + wake + UDID install then worked first time. The macOS 27.2
update removed the Metal toolchain (one download). Movie Room was registered
into the tvOS profile (`-allowProvisioningDeviceRegistration`); it installs,
but it cannot be LAUNCHED asleep — pyatv has no Companion pairing for it (a
PIN on that TV, the owner's step).

**Broadcasts, judged from the server's recording**: Apple TV (Morocco, 1080p30,
"encoder: hardware"), iPhone 12, iPad Pro, Pixel 8a (720p, 21 fps, camera
tile), Mac (1080p, 31 fps). **Room guests**: Apple TV, Pixel, Google TV, Fire
TV and the web (§8.66) all pause on the host's frame and follow a seek.

**Found and fixed**: (1) `MP4Fragmenter.plan` let each fragment's audio
overshoot by up to a frame and the overshoot ACCUMULATED — 42 s by the end of
an 85-min film — so every tvOS 27 seek landed seconds late (§8.71). (2) A slow
Apple seek read as the guest's own move. (3) The Android room door was never
collected on a television. (4) The Mac's Microphone row said "live" with no
microphone attached. (5) The iPhone door's mute did not hold once (the film
played aloud from the test phone); now re-asserted and logged — not reproduced.
**Open**: on tvOS's HLS path a 1.03 nudge is accepted and not honored, so a
late-landing guest stays ~0.5-1 s behind (LAUNCH-AUDIT).

Older entries: `docs/SESSION-LOG.md` (verbatim, back to 2026-04-17).
