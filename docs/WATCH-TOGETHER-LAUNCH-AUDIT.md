# Watch Together — launch audit (2026-09-23)

Owner: *"Can you audit all features, design, and code within the Watch Together
Studio and the Watch Together implementations across all platforms to see if
anything can be improved, optimized, or better built out for launch once the
YouTube oauth approval is available?"*

Five read-only reviews (macOS UI, shared engine, iOS/tvOS, Android + web +
Worker + Roku, launch readiness), merged and ranked here. **This is the work
list for the Studio loop**: take items from the top, prove each on the product
path (Decision 130/133), and strike it with the version that fixed it.
Items marked *(suspected)* were inferred from code and need a run before a fix.

## A. Launch blockers

| # | Item | Where | Status |
|---|---|---|---|
| A1 | Preview → Go Live deleted the broadcast it had just created (end() after arming) | macOS `goLive()` | **FIXED v1.42.536**, proven on YouTube (RDmqaI1PgVw live → complete), §8.54 |
| A2 | App Store builds carried no YouTube/Twitch client id — sign-in "not set up" on every store build, and Google's reviewer is told to install from the store | `appstore-build.yml`, `play-release.yml` | **FIXED v1.42.537** — `AW_YOUTUBE_CLIENT_ID` / `AW_TWITCH_CLIENT_ID` secrets, build fails if missing. Needs a store build before the verification reply goes out |
| A3 | YouTube chat captured one access token for the whole show — dies within the hour, then polls 401s | `StudioSession.attachYouTubeChatIfArmed` | **FIXED v1.42.537** (token asked for per page) — not yet run past an hour |
| A4 | YouTube quota: `liveChatMessages.list` (5 units) polled all show on a project-wide 10,000/day budget — about one 2-hour show a day for ALL hosts; no `quotaExceeded` handling | `StudioChatYouTube.swift`, `StudioPlatforms.swift` | **Decision 136** (owner chose all three: slim sign-in + quota extension + own stream key). **Partly FIXED v1.42.539**: chat floor 10 s, viewer count 60 s, exponential backoff, quotaExceeded stops and says so (§8.56). Stream-key path BUILT on macOS v1.42.540 (Sign in / Stream key; no API, no quota) — not yet proven with a real key; iOS/tvOS/Android still sign-in only. Chat opt-in DONE v1.42.547: "Show chat from YouTube" on the Mac, iPhone and Apple TV go-live forms, off by default and remembered; live check ESeqclB1yg8 read no chat with it off. **OWNER**: file the YouTube API quota extension |
| A5 | YouTube API Services policy: privacy page must link YouTube ToS + Google Privacy Policy and say the app uses YouTube API Services; a ToS line at sign-in | `privacy.html`, `StudioSignInRow` | **FIXED v1.42.541** — YouTube API Services section with the ToS and Google Privacy Policy; a ToS line under Sign in to YouTube on every Apple platform |
| A6 | privacy.html contradicts itself/the code: "collects nothing"/"only server-side thing" vs rooms; sign-out now also revokes; uninstall does not remove Keychain items; Twitch uses (title/category PATCH, markers, viewer count) undisclosed; "Apple TV app" intro | `privacy.html` | **FIXED v1.42.541**, and the six-hour promise made true by the Worker's hourly sweep (deployed 37ea0138) |
| A7 | Docs/demo say the app "transitions the broadcast to live"; code uses `enableAutoStart`. Readiness does a `liveBroadcasts.list?mine=true` not disclosed | reply, privacy, demo beat 8 | **FIXED v1.42.541** |
| A8 | Demo step 2 revokes at myaccount.google.com — shown not to work for Brand Accounts | `tools/oauth_demo_record.sh`, Desktop checklist | CODE: "Sign out in the app (it revokes), confirm the scope prints in words" |
| A9 | Which OAuth clients live in the Google project? The social poster's upload client may share it; the reply says `auth/youtube` is the only scope | Cloud Console | **RESOLVED 2026-09-23**: project 895559137709 has ONE OAuth client, "Archive Watch (Apple)" (iOS); the social poster's client is elsewhere, so "the only scope" is true. Branding has no Terms of Service URL — deliberately NOT added while Data Access is under review: saving branding "will update your verification request" and may re-review verified information. Add `https://archivewatch.org/terms.html` after the review concludes |
| A10 | One keystroke ends a live show with no confirmation: ⌘W on the Studio, Esc on the projection ✕, ⇧⌘E from any window, End; ⌘Q never completes the broadcast | macOS | **FIXED v1.42.545** (§D37): close disabled on air, confirm on ⇧⌘E / End / ✕ / ⌘Q, ⌘Q completes the broadcast; bench-verified `closable=no` while live |
| A11 | Film can change under a live show: projection window autoplays the next film (macOS); Play Next / auto-advance and lineup/channel entry (tvOS); engine follows any item swap without a rights re-check | `PlayerWindow_macOS`, `DetailView.swift`, `StudioEngine.noteFilmItemChanged` | **FIXED v1.42.546** — every advance site refuses while live and Play Next leaves the tvOS menu (§8.57, control fails 4/4). Open: a rights re-check inside the engine as defense in depth |
| A12 | tvOS End cancels its own teardown task — the YouTube broadcast is neither completed nor deleted (orphans); Menu mid-show ends it silently | `DetailView.swift` | **Orphan half FIXED v1.42.538** — `completeArmedBroadcast` runs outside the caller's cancellation; §8.55 (a real request: wrapped reaches, bare refused -999). Not yet run on an Apple TV. Menu half built v1.42.551 (Rule 8.8i: cover not dismissable while live, Menu asks) — needs a real remote press |
| A13 | iOS End leaves the camera and mic running (privacy dots, battery) | `StudioPlayerContainer_iOS.end()` | **FIXED v1.42.542** — `StudioSession.stopHostCapture()` on End and on disappear; iPhone 12 bench run: `AWCAM host capture stopped running=no` 97 ms after the show ended |
| A14 | Worker: ~~no stale-room sweep~~ (**hourly sweep deployed v1.42.541**, SQL tested on the real schema); ~~no rate limit~~ **FIXED v1.42.552** (deployed bf4cae7e): per-address limiter 300/min (measured: engages, ~860 through across two bursts, Cloudflare's count is approximate) + 10 creates/min; filmID/position/rate validated; a host update without filmID keeps the film; presence capped at 50; /together answers its own preflight (* , max-age 86400) | `worker/` | done |
| A15 | Android has no foreground service for a live broadcast — locking the phone kills camera/mic | Android manifest | **BUILT v1.42.553** — `StudioBroadcastService` (camera\|microphone, "You're live" notification with End). Pixel 8a: service started types=192, and with the screen OFF (dozing) the camera count kept rising 342→805 in 25 s at 19–23 fps. CONTROL NOT YET RUN (`--ez aw_studio_no_fgs true`): the phone locked and needs the owner's unlock |
| A16 | Rooms: a pending code joins whatever film plays next (Android, iOS, tvOS); followers never leave on close (web, iOS, tvOS) — inflated presence, next film hijacked | followers, `watch.js` | **Apple FIXED v1.42.548** — code tied to the room's film, iOS/tvOS leave on close (§8.58, control fails). Android and web FIXED v1.42.550 (Android code tied to the film; web leaves on close and on navigation) |

## B. Should-fix before or soon after launch

- **Engine**: media packets handed over through one `Task` each (possible reordering → the unreproduced "audio artifacts"); A/V timestamps from counters drift over two hours *(suspected)*; token refresh has no single-flight (Twitch refresh tokens are one-use); `encodeAndAwaitFormat` can hang go-live forever; `blankFrame()` force-unwrap + unbounded pixel-buffer pool; reconnect callbacks from a cancelled connection can fail the new one; simulcast extras never reconnect; `prepare()` leaves a stream/broadcast behind on partial failure and inserts a new reusable `liveStream` every show; server `onStatus` text may echo the key *(suspected)*.
- **DEBUG doors reachable in Release** on every Apple platform (`AW_STUDIO_DEST` can send a rehearsal to any server; `applyLaunchOverrides`, StudioLab, `AW_STUDIO_CHAT`, `AW_GOLIVE_CUSTOM` …). Wrap all in `#if DEBUG`; decide whether "Custom server" is a product feature (OBS has it) or DEBUG-only.
- **macOS**: ~~go-live `problem` invisible once on air and raw `\(error)`~~ (FIXED v1.42.557: shown in the on-air summary; shared `studioSentence(for:)`); ~~room code has two sources of truth~~ (FIXED v1.42.557: `RoomJoin.hostCode` reads `StudioRoomHost.code`); landing page's "Start a room…" is always disabled and contradicts §11.13; ~~scene switch can UNMUTE the mic~~ (FIXED v1.42.556, self-test 10/10, control fails 2); ~~⇧⌘S collides with Save As; ⌘1–9 from any window~~ (FIXED v1.42.560: ⇧⌘S removed, ⇧⌘L opens the Studio; scene keys only while the Studio is key, via focusedSceneValue); accessibility: FIRST PASS v1.42.558 (scene buttons named + selected trait, faders/meters/mute switches named with values, audience rows combined with a named "Show on the broadcast" action) — not yet heard with VoiceOver; guest-window menu now fills without hover (only where Screen Recording is already granted) and text fields carry their titles, v1.42.559; keyboard tile framing still open; whole window re-evaluates every second; `measuredKbps` assumes 30 fps; no "Going live…" progress; recording clock breaks past an hour.
- **iOS/iPad**: Duck toggle never reaches the engine alone (Decision 133); leaving the app kills the picture (auto-PiP, no scenePhase handling) — **BUILT v1.42.554**: no PiP in the Studio; Intermission goes up when the app stops being active and comes down on return (iPhone 12: `AWAWAY` up/down logged and the show published cleanly afterwards; measured DURING a live show v1.42.555: on the old code a 15-s trip to Settings killed the VIDEO for the rest of the show (VideoToolbox session invalidated, -12903, nothing rebuilt it; audio kept flowing). The engine now rebuilds a dead encoder — proved by a forced invalidation on the Mac bench: 2 fps → STOPPED → restarted → 33 fps within a second, 0 reconnects. A second iPhone on-air trip did not kill the encoder at all, so iOS does not do it every time); iPad controls sheet covers the program; denied camera/mic is a dead end (no Open Settings); Twitch activation URL is plain text; an ended show is titled "Could not go live"; kbps is a lifetime average (tvOS too); no §D21 stall sentence (tvOS too); host pause reads as a fault on tvOS; Back from GoLiveTV leaves the film paused.
- **Android**: Go-live dialog still says camera is optional and enables Go live without it (Decision 132); denial has no retry/Open Settings; room status never shown to a guest; TV join grid double focus targets; encrypted prefs may break after device transfer; sign-out does not revoke.
- **Sync**: correction policy differs — "paused" means buffering on Swift/Android but not web; only Swift seeks with `seekLead`; macOS host publishes buffering as a pause to every guest.
- **Worker**: validate `filmID`/`rate`/`position`; `/together` preflights answered by the global handler (web-TV presence fails); cap presence rows; `Access-Control-Max-Age`.
- **Twitch**: hourly `/validate` during a show; drop unused `user:read:chat`; IRC reader drops split UTF-8 chunks and double-reconnects.
- **Recorder**: non-fragmented MP4 loses everything on a crash; dropping P-frames corrupts until the next keyframe.
- **Other**: macOS mic usage string mentions only Creation Studio (5.1.1 risk); call-audio / window capture can carry copyrighted audio past the rights gate; `selfDeclaredMadeForKids` hard-coded; revoked token still shows "Signed in"; `StudioRights` cutoff `<= 1929` should follow the year (1930 entered the US public domain 2026-01-01 — safe, just stale).

## C. Roku rooms (not built)

About 200–250 lines: an options row, a keyboard dialog, a `roomCode` on PlayerScreen driving `TogetherTask`, an ended/failed message — plus three fixes in the existing BrightScript: `awNowSeconds() as Float` (128-second steps at 1.8e9 — must be Double), one blip ends the room (end only on 404/410), no presence ping.

## D. Polish

Captions that explain rather than refuse/warn (macOS, iOS, tvOS lists in the reviews); typography beyond six levels and hard-coded brand orange beside system-orange warnings; ~660 lines of dead `StudioVoice*` code; Android `createRoom/publish/endRoom` unused; duplicated chat-attach in three places; stale PARITY (rooms "not deployed"), SCRATCHPAD item 7, `Secrets.xcconfig.example`, the `tv_signin_is_qr_and_phone` memory; web guest has native controls that fight sync; iOS Watch Together two menus deep.

## Quota per two-hour YouTube show (review estimate — confirm against Google's table)

| Call | Units | Count | Total |
|---|---|---|---|
| insert stream + broadcast + bind | 50 each | 3 | 150 |
| thumbnails.set | 50 | 1 | 50 |
| complete / delete | 50 | 1 | 50 |
| viewer count every 30 s | 1 | 240 | 240 |
| chat list at 5 s | 5 | 1,440 | 7,200 |
| **Total** | | | **~7,700** of 10,000/day for the whole project |
