# Audio-first platform engineering, per platform (research for the old-time-radio sister app)

*Date: 2026-10-17. Research track 04. Nothing here is built.*

**How to read this file.** The container's network policy blocks page fetches; only web search worked, and the session's search budget ran out before every question was asked. So every fact is tagged one of three ways:

- **[S]**: the fact came from a search-result snippet of the URL cited. The page itself was not opened.
- **[R]**: the fact came from this repository, with a path. Archive Watch has already measured or shipped it.
- **[K] UNVERIFIED**: prior knowledge of the platform that no source fetched this session confirms. Check it against the live documentation before relying on it. "To measure" (section 12) lists a probe for each of these that matters.

---

## Verdict

1. **The audio shell is easier than the video shell on every platform but one.** Background audio, lock-screen and car controls, and voice play all hang off one object per platform: `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` on Apple (and, from the 2026 SDKs, the new **Now Playing framework**, WWDC26 session 312 [S]), a Media3 `MediaLibraryService` on Android, and the Media Session API on the web. Build that object first and CarPlay, Android Auto, Wear, Assistant and Siri mostly follow from it.
2. **The web is the exception, and it is a serious one: an installed iOS home-screen PWA is not a dependable background audio player.** Lock-screen audio in a standalone PWA stops working after it has been paused for about 30 seconds (Apple Developer Forums 762582, 2024 [S]), and WebKit bug 243258 (a paused, backgrounded MediaSession cannot be resumed) was filed in 2022 [S]. No 2025 or 2026 fix was found. Treat the web as a way to discover and try shows. iPhone listeners need the native app. Plain Safari tabs behave better than installed PWAs [S, Discourse thread].
3. **Cars are the biggest new surface, and both are gated.** CarPlay needs the `com.apple.developer.carplay-audio` entitlement, which you request from Apple, and Apple reviews the request [S]. Android Auto needs a `MediaLibraryService` browse tree and has to pass Google's car quality review before Play will list the app for cars [S]. Both are template-driven, so you write data, not UI. CarPlay lists are capped at 500 items, per an Apple engineer on the forums [S].
4. **On Android TV the rule flips.** Archive Watch had to switch MediaSession OFF on TV, because Google's TV-NP rule bars Now Playing controls for video apps [R: docs/TV-PLATFORM-EXPANSION.md item 5]. An audio app is the case that rule is written for, so the radio app should keep the session ON for TV [K, unverified].
5. **Roku's screensaver is the trap.** An Audio-node channel goes idle and the screensaver starts. Roku documents `disableScreenSaver` on the **Video** node "typically used ... when playing audio-only streams". Setting it on an Audio node logged "nonexistent field", and the reported workaround is an invisible Video node [S, Roku forum]. Channels may no longer bundle a screensaver of their own [S].
6. **Loudness: measure it in the pipeline and store a gain. Do not re-encode.** OTR files vary a lot in level. Run a CI pass of `ffmpeg ... loudnorm=print_format=json` (EBU R128) on each file, store `integratedLUFS` / `truePeak` / `gainDb` beside the file in the catalog, and apply that gain as a player volume at playback on every platform. archive.org stays the host. Nothing is re-uploaded. That is the same "compute in the pipeline, the client applies it" rule as Decision 050 [R].
7. **Transcripts: the case for pipeline ASR is stronger for audio than it was for video, and Decision 039b's lesson still binds.** Whisper was dropped for film captions because it HALLUCINATED on poor, music-heavy film audio [R: DECISIONS-031-060 039b]. OTR is one mono speech track with short episodes, but it also carries organ stings, sound effects and hiss, which are exactly what produces hallucination (arXiv 2501.11378 [S]). Ship transcripts only with VAD gating (whisper.cpp `--vad` with a Silero model [S]), a hallucination detector, and a human-review sample before the first shelf goes out. Use them first for search, and display them second.
8. **Store risk is Archive Watch's own risk again.** It is 5.2.3 (streaming from third-party sources), and Archive Watch already wrote the answer [R: docs/app-store-review-5.2.3-response.md]. Add a 4.2 risk: a thin "RSS player" can read as minimum functionality. The answer is the native shell in section 9, which is offline downloads, CarPlay, sleep timer and transcripts.

---

## 1. What Archive Watch already has that carries straight over [R]

| Piece | Where it lives in Archive Watch | Use in the radio app |
|---|---|---|
| Now Playing + remote commands | `ArchiveWatch/ArchiveWatch/Services/NowPlayingWarmup.swift`, `Views/AVPlayerScreen.swift` | Starting point. Audio needs skip intervals and rate; video needs neither |
| Audio session handling | `Services/TVAudioSession.swift`, Studio files | Category and interruption pattern |
| Background downloads | `Services/DownloadManager.swift` (background URLSession into Application Support; Decision 099) | Episode downloads, unchanged in shape. Decision 099 also gave tvOS no downloads |
| SharePlay | `Services/WatchTogether.swift`, `iOS/SharePlayStarter_iOS.swift`, `macOS/SharePlayStarter_macOS.swift` (Decision 098, archiveID-coordinated) | "Listen together" with the same coordinator |
| Background refresh | `Services/BackgroundRefresh.swift` | Fetch new episodes and the catalog |
| Android MediaSession | `android/.../ui/screens/PlayerScreen.kt` (media3-session, switched off on TV per TV-NP) | Promote to a `MediaLibraryService`, switched ON on TV for audio |
| Web Media Session | `watch.js` around line 3655 (metadata, play, pause, seek, next, previous) | Reuse as is, add `setPositionState` |
| archive.org Range/CORS facts | `docs/CATALOG-CONTRACT.md` notes; `docs/WEB-DESIGN.md` §2.5 | `download/` nodes serve 206 **without CORS**, which is fine for `<audio>` but blocks `fetch()`. The `/metadata` API **does** send CORS (measured 2026-06-09) |
| Resilient loader | Decisions 021/031/034/077 (node pinning, failover, 30-second start guarantee) | Same need. Archive storage nodes fail the same way for MP3 as for MP4 |
| AirPlay rule | Decision 051: the receiver gets the published origin URL, never 127.0.0.1 | Same rule for AirPlay 2 and HomePod |

What Archive Watch never needed, and the radio app does: skip intervals, playback rate, sleep timer, chapters, a car browse tree, a watch app, smart resume tuned for 30-minute episodes, gapless queueing.

---

## 2. Apple (iOS 18 floor, iPadOS, macOS, tvOS, watchOS, CarPlay)

### 2.1 Playback engine
- **AVPlayer / AVQueuePlayer** play progressive MP3 over HTTPS with Range requests. For HLS audio, Apple says "point AVQueuePlayer to the feed and it will take care of streaming" and that watchOS is "optimized for HLS audio feeds" (WWDC19 session 716 [S]).
- **Gapless**: an Apple forum answer says AVQueuePlayer "can do gapless playback just fine as long as the files are actually gapless". The gaps people report come from encoder padding in the MP3 itself. MP3 has no standard delay/padding field; the LAME info tag or Apple's `iTunSMPB` carries it (Wikipedia, Hydrogenaudio [S]). For HLS, WWDC21 10142 says the content must be authored for gapless and that AVQueuePlayer favors a gapless transition over a higher variant [S]. **Consequence:** OTR episodes are self-contained 30-minute shows, so gapless between episodes is not a requirement. It matters only for multi-part serials split mid-scene, which are rare. Do not build HLS for gapless alone.
- **No re-hosting**: Archive Watch's 5.2.3 answer rests on "streams directly from the Internet Archive's own public servers" and "hosts nothing" [R]. Re-encoding to HLS would mean hosting a copy, which changes that answer and adds cost. Stay on progressive MP3 from `archive.org/download/…`.

### 2.2 Background audio and AVAudioSession [K]
- Turn on `UIBackgroundModes = audio` (Signing & Capabilities, "Audio, AirPlay, and Picture in Picture"). Without it, playback stops when the app is backgrounded. A WWDC19 716 snippet confirms the watchOS equivalent: add the background audio capability to the extension [S].
- Category `.playback`, mode `.spokenAudio`. `spokenAudio` tells the system the content is speech, so other apps' navigation prompts pause it rather than duck it, and CarPlay and AirPods treat it as spoken [K]. Set route-sharing policy `.longFormAudio` so AirPlay and HomePod routing offer it as long-form audio [K].
- **Interruptions**: watch `AVAudioSession.interruptionNotification`. On `.ended` with `.shouldResume`, resume. For spoken word, rewind a few seconds before resuming, because a listener who lost the last line of dialogue loses the plot [K].
- **Route change**: on `.oldDeviceUnavailable` (headphones unplugged) **pause**. Every audio app is expected to do this, and reviewers check it [K].

### 2.3 Now Playing and remote commands
- `MPRemoteCommandCenter.shared()`: `skipForwardCommand` / `skipBackwardCommand` are `MPSkipIntervalCommand`s with `preferredIntervals` (seconds) (Apple docs [S]). Commonly 30 forward and 15 back for spoken word (forum example sets 30 [S]). **The CarPlay catch:** setting `preferredIntervals` makes CarPlay show skip buttons instead of next/previous track; to get track buttons, remove the intervals (Apple forums 772603 [S]). Choose skip intervals for episodes, and next/previous for a queue of episodes in a series. That has to be decided per screen.
- `changePlaybackRateCommand` "controls the rate of the current item" [S]. Set `supportedPlaybackRates` (for example 0.75, 1.0, 1.25, 1.5, 2.0) [K].
- Publish `MPNowPlayingInfoPropertyElapsedPlaybackTime`, `MPMediaItemPropertyPlaybackDuration`, `MPNowPlayingInfoPropertyPlaybackRate`, `MPNowPlayingInfoPropertyDefaultPlaybackRate`, artwork, `MPMediaItemPropertyTitle` (episode), `MPMediaItemPropertyAlbumTitle` (series), and `MPMediaItemPropertyArtist` (network or sponsor, **only from data**) [K].
- **Chapters**: `MPNowPlayingInfoPropertyChapterCount` / `CurrentPlaybackPosition` exist [K]. Chapters in this app would be acts of a show and commercial breaks, which need detection (§8.4).
- **New for 2026: the Now Playing framework** (WWDC26 session 312, "Meet the Now Playing framework" [S]). An observable model conforms to `MediaSessionRepresentable`, is wrapped in a `MediaSession`, and the system keeps Lock Screen, Control Center, Dynamic Island, StandBy and CarPlay updated "without manual pushes". State is a `MediaPlaybackSnapshot` (playing or paused) [S, session digest github.com/ivan-magda/wwdc26-notes]. It also adds **remote media sessions** for playback on external devices (an app extension, APNs, `RemoteMediaSessionRepresentable`) [S, secondary]. **This is a 2026 OS feature, so it sits above the iOS 18 floor (Decision 155).** Build on MP* APIs, and gate the new framework behind `#available` only if it buys something the MP* path does not. Check its OS minimum on the session page.
- **tvOS**: audio metadata appears "in a badge in the corner of the screen and as a full-screen display when the user is idle" (WWDC17 251 [S]). tvOS shows a full-screen now-playing overlay after a short idle period (WWDC22 110338 [S]). So the app does **not** need its own screensaver or idle art on tvOS; supplying good artwork is enough. On tvOS, do not use `MPNowPlayingSession` alongside AVKit, which publishes automatically (WWDC22 [S]).

### 2.4 Lock Screen, Live Activities, widgets
- The Lock Screen and Dynamic Island show playback through Now Playing; that is what WWDC26 312 describes as the surface [S]. **A Live Activity is not the audio player surface.** A Live Activity for "now playing" would duplicate the system's. The HIG text was not retrieved [UNVERIFIED]. Live Activities are worth considering only for a timed event, such as a scheduled "broadcast hour" channel (the radio counterpart of Decision 144's Channels), if one is built.
- **Widgets**: an Apple DTS answer says either AudioPlaybackIntent or INPlayMediaIntent works for Siri, but **widgets need an App Intent**, so build on App Intents (forum 768926 [S]). A "Resume [series]" button widget is the obvious one, and its contents come from listening history, not editorial copy.

### 2.5 Siri, App Intents, suggestions
- **App Intents first** (`AudioPlaybackIntent`, plus `AppEntity` for Series and Episode, plus `AppShortcutsProvider` phrases such as "Play \(series) in \(app)") [S for AudioPlaybackIntent, K for the rest].
- **INPlayMediaIntent** (SiriKit Media Intents, WWDC19 207: "Play Outer Peace in my app" [S]) is the older route. HomePod and "play X" with no app named historically rode on it [K, UNVERIFIED]. Forum threads report a handler that never fires and Siri failing to recognize the app name in non-English locales [S]. Decide by measuring on a HomePod (section 12).
- Donate `INPlayMediaIntent` / `NSUserActivity` on play, so Siri Suggestions and Lock Screen suggestions learn the habit [K]. Archive Watch already does NSUserActivity (Decision 015) [R].
- Siri's "play Suspense" needs to resolve fuzzy series names. The `AppEntity` query should use the catalog's alternate titles (from data, for example Wikidata aliases).

### 2.6 CarPlay
- Request the CarPlay audio entitlement through Apple's CarPlay contact page and agree to the CarPlay Entitlement Addendum. Apple reviews it, and if approved adds it to the account as a managed capability; then update the App ID, the provisioning profile and the entitlements file. CarPlay apps are also held to extra review guidelines in the CarPlay App Programming Guide (Apple, "Requesting CarPlay entitlements" [S]). An Apple DTS reply calls carplay-audio "the most common and straightforward path" [S]. The key is `com.apple.developer.carplay-audio`; the old playable-content key is deprecated [S, forum plus a third-party site]. Review time "1–2 weeks" is a third-party estimate only [UNVERIFIED].
- **Templates for audio apps**: `CPTabBarTemplate` (max 4 tabs for audio, per a third-party guide [S, UNVERIFIED]), `CPListTemplate` (max 500 items per an Apple engineer; images are **not** lazy-loaded, so supply them at the item's maximum size, forum 798894 [S]), `CPGridTemplate`, and the system `CPNowPlayingTemplate.shared`. Navigation depth of 5 is reported (forum 813008 [S]). iOS 26 added image-row customization to the list template (WWDC25 216 [S]).
- **Design consequence:** the car's tabs are something like *Continue · Series · Downloads · (Channels)*. A 1,000-episode series has to be paged by season or year to stay under 500 rows. **Downloads matter more in the car** (dead zones).
- CarPlay uses the same Now Playing state (§2.3). The skip/track-button choice applies here hardest.
- **The entitlement is per bundle ID.** Request it early; it is a calendar item, not code.

### 2.7 Apple Watch
- watchOS supports standalone streaming over Wi-Fi/LTE with AVPlayer / AVQueuePlayer; `URLSession` streaming tasks and the AV-streaming network service type were added for custom protocols (WWDC19 716 [S]). Background audio needs the capability on the extension [S].
- Risks from forums [S]: background URLSession requests not answering after a track finished; asset URLs expiring; background refresh no more often than every 15 minutes. **Prefer downloads on the watch** (a background URLSession transfer while charging), and plain progressive MP3 URLs that do not expire. archive.org URLs are stable, which helps.
- Audio on a watch plays through Bluetooth headphones or a speaker [K]. Sync history through the same store as the phone (CloudKit, Decision 022/028 [R]).
- **Priority: low.** Ship after CarPlay.

### 2.8 AirPlay 2 and HomePod
- AirPlay 2 comes free with AVPlayer, the `.longFormAudio` route policy and an `AVRoutePickerView` [K]. Decision 051 binds: hand the receiver the origin URL [R].
- HomePod: "Hey Siri, play Suspense on Archive Radio" needs the Siri intent path (§2.5). HomePod runs third-party audio through the iPhone's intent handling [K, UNVERIFIED]; measure it.

### 2.9 SharePlay "listen together"
- `AVPlayer.playbackCoordinator.coordinateWithSession(_:)` with a GroupSession; AVFoundation then syncs play/pause/seek/rate itself, and transport state must NOT travel in the messenger. Local interruptions use `beginSuspension(for:)` (WWDC21 10225 [S]). A `.listenTogether` activity type is listed by a community guide [S, UNVERIFIED]. Archive Watch's Decision 098 ("coordinates by archiveID, listens from launch, never lets Watch Together play alone") carries over word for word [R].

### 2.10 Background downloads
- Reuse `DownloadManager.swift` (background URLSession into Application Support, played back as a local file; Decision 099) [R]. OTR MP3s are 15–30 MB per half-hour at 64–128 kbps (arithmetic: 64 kbps × 1,800 s ≈ 14.4 MB; 128 kbps ≈ 28.8 MB), so "download a season" is realistic on a phone and on a watch. Offer **auto-download next N episodes of followed series**, with a storage cap.

### 2.11 Playback-time DSP: AVAudioEngine / AVAudioMix [K]
- **Loudness gain**: apply the pipeline's `gainDb` as `AVPlayer.volume` (linear = 10^(gainDb/20), capped at 1.0) or, for boosts above unity, an `AVAudioMix` with `AVMutableAudioMixInputParameters.setVolume`. Volume above 1.0 cannot boost, so negative gains are easy and positive gains need a tap or AVAudioEngine. **That makes the pipeline target matter:** pick a target that most files sit *above* (for example -18 LUFS for speech), so most corrections are cuts.
- **EQ and noise reduction**: an `MTAudioProcessingTap` on the AVPlayerItem's audio mix can feed `AVAudioUnitEQ`-style processing; or play through `AVAudioEngine` + `AVAudioPlayerNode` (which loses AVPlayer's streaming, so it needs downloaded or buffered files). A "voice clarity" toggle (high-pass at about 100 Hz, presence lift around 2–4 kHz) is cheap and helps hiss-heavy transfers. Real denoising (spectral subtraction, RNNoise-class) at runtime is costly on a watch. **Recommendation:** EQ at runtime on iOS/macOS only, no runtime denoise. Do not publish denoised copies either, because that would be re-hosting (§2.1).
- AVPlayer does **not** apply ReplayGain/iTunNORM tags in a streamed MP3 by itself [K, UNVERIFIED; the search found tagging background only]. Gain has to come from the catalog.

---

## 3. Android (phone, tablet, Wear OS, Android Auto, Android Automotive, Google TV, Fire TV)

### 3.1 Playback service
- **Media3 `MediaLibraryService`** (a superset of `MediaSessionService`) hosting ExoPlayer. "The library is expected to be structured in a tree format, with a single root node and children nodes that may be playable or further browsable"; Android Auto gets "its own driver-safe UI" from it (developer.android.com/media/media3/session/serve-content [S]).
- Manifest: declare the service with both the Media3 action and `android.media.browse.MediaBrowserService` for compatibility. Two versions of the docs page show different Media3 actions, so check the live page [S]. Foreground service type `mediaPlayback` on Android 14+ [K]. Archive Watch's floor is minSdk 24 on Play and 23 on Fire TV (Decisions 141/165) [R]; Decision 154 says gate newer features by `SDK_INT` [R].
- Media3 gives notification, lock screen, Bluetooth, Wear and Auto controls from that one session [K]. "Media button preferences" (custom commands like skip 30 s or sleep timer) are set on `MediaLibrarySession.Builder` [S, API reference]. Media3 1.8.0 improved playback-resumption notification persistence (third-party summary [S]). **Playback resumption** (`onPlaybackResumption`) lets the system's media carousel resume yesterday's episode after reboot [K]. That is smart resume for free.
- Speed: `player.setPlaybackSpeed()`, with pitch kept by Sonic [K]. Skip: `seekBack/ForwardIncrementMs` on the ExoPlayer builder [K].
- Loudness: ExoPlayer's `player.volume` (0–1) applies cuts. For boosts use a `LoudnessEnhancer` audio effect on the session's audio session id, or a custom `AudioProcessor` [K].
- **Audio focus**: `setAudioAttributes(AudioAttributes(USAGE_MEDIA, AUDIO_CONTENT_TYPE_SPEECH), handleAudioFocus = true)` and `setHandleAudioBecomingNoisy(true)` (pause on unplug) [K]. CONTENT_TYPE_SPEECH tells the system to pause rather than duck under navigation prompts [K].

### 3.2 Android Auto
- A car media app must provide a media browser service so Auto and AAOS can discover and display content (developer.android.com/training/cars/media [S]). Items may be browsable, playable, or both [S]. Auto renders the UI; the app supplies the tree, artwork, and content-style hints (grid vs list) [S].
- The app "must meet specific design requirements before it can be listed on Google Play for Android Auto or AAOS"; requirements are tiered MUST/SHOULD/MAY (Google cars design pages [S]). The specific `CAR_MEDIA` criteria were **not retrieved** [UNVERIFIED]; open "Android app quality for cars", filter Media, before building.
- `automotive_app_desc.xml` with `<uses name="media"/>` referenced from the manifest [S, third-party; K].
- `onGetRoot()` must return non-null for allowed callers; implement every playback callback; supply album art (Harman developer pages [S, secondary]).
- Keep media IDs stable (a third-party guide [S]). Archive Watch's rule "ids never change" (Decision 113 for Roku Search) is the same rule [R]. **Use archive.org identifier + filename as the episode ID**, never a database row number.
- Voice search in the car: genre, artist, album, song, station and playlist categories; do not block in `onPlayFromSearch`; set the state to connecting first (developer.android.com/media/implement/assistant [S]).

### 3.3 Android Automotive OS (AAOS)
- The same `MediaLibraryService` serves AAOS. Vehicle-optimized non-media UI (sign-in, settings) is allowed only while Car UX Restrictions are off, that is, parked (Google cars docs [S]). The app has no accounts (Decision 009 [R]), so a settings screen is the only parked-only UI.
- AAOS apps ship through Play to cars with Google built-in, as a separate form factor in the same bundle [K, UNVERIFIED]. **Priority: after Android Auto.** Testing needs a real car or a real head unit (Archive Watch's "real devices only" rule [R]), which is an owner question.

### 3.4 Wear OS
- Wear OS 5+ has a system media output picker. Play only when Bluetooth headphones or a speaker are connected; `ExoPlayer.Builder.setSuppressPlaybackOnUnsuitableOutput(true)` plus `WearUnsuitableOutputPlaybackSuppressionResolverListener`, which pauses, launches the output dialog, and resumes if output connects in time (developer.android.com/training/wearables/apps/audio, Media3 reference [S]). Horologist's media sample shows the pattern [S].
- A phone's MediaSession already controls playback from the watch (media controls on Wear) for free [K]. A standalone Wear player is extra work. **Priority: low.**

### 3.5 Google Assistant / Gemini
- Implement `PLAY`, `PLAY_FROM_SEARCH`, `PLAY_FROM_URI` and their `PREPARE` counterparts; for "Play jazz on [app]" `onPlayFromSearch` gets a query plus extras; an empty query ("play [app]") should just start something sensible; some systems need a `MEDIA_PLAY_FROM_SEARCH` intent filter (developer.android.com/media/implement/assistant [S]). Media3 maps these to `MediaSession.Callback.onAddMediaItems` / `onSetMediaItems` with `RequestMetadata.searchQuery` [K].
- **"Something sensible" from data**: resume the most recent episode, else the next episode of the last series. Never a model-chosen pick (CLAUDE.md "No AI-written lists" [R]).
- How Gemini-as-assistant changed these voice actions was **not found** [UNVERIFIED].

### 3.6 Google Cast
- CAF Web Receiver plays MP3/MP4 through the media element; the hosted Styled Media Receiver suits audio and video with CSS branding; Custom receivers for anything beyond (developers.google.com/cast/docs/caf_receiver [S]). **For progressive MP3 the Default or Styled receiver is enough**, which means no hosting. A third-party table reports HLS audio-only failing on its receiver [S], one more reason to stay on MP3.
- Cast reaches Google Nest speakers and Cast-enabled speakers [K]. Media3 has a `CastPlayer` (`media3-cast`) that swaps in for ExoPlayer [K]. Note that Cast needs Google Play Services, so it is a `google`-flavor-only feature, and Archive Watch's Fire TV rule is zero GMS [R: docs/TV-PLATFORM-EXPANSION.md item 6].

### 3.7 Google TV and Fire TV
- **Keep MediaSession ON for audio on TV.** Archive Watch's TV-NP rule ("Video apps must NOT use Now Playing / background media controls; video must pause when switching out") is why its session is off on TV [R]. For an audio app the platform expectation is the opposite: background audio shows a Now Playing card and keeps playing when the user leaves to Home [K, UNVERIFIED]. Read the current TV quality guidelines for audio (TV-NP) before building; this is one line of code with a review consequence.
- Fire TV: no specific audio guidance was retrieved (search budget exhausted) [UNVERIFIED]. Fire OS is Android, so the Media3 session gives the system's media controls [K]. Amazon's review checks Back behavior (Archive Watch's A16: Back returns to the launcher from root [R]).
- A TV audio screen needs something to look at: series art, episode art, an elapsed bar, and transcript lines if they exist. Burn-in: keep slowly moving or dimming art on OLED [K].

---

## 4. Roku

- **Audio node** (SceneGraph): `content` (ContentNode with url, streamformat "mp3"), `control` ("play"/"stop"/"pause"/"resume"), `state`, `position`, `duration` [K]. Seeking is done by setting `seek` [K].
- **The screensaver problem**: a screensaver is "automatically invoked when either a video, game, utility, or application has been idle" (Roku screensaver docs [S]). Developers report audio channels being interrupted by it, and some report the audio *stopping* when it starts (Roku forum threads [S]). `disableScreenSaver` is documented on the **Video** node "to suppress the screensaver when playing audio-only streams". On an Audio node one developer got `Tried to set nonexistent field "disablescreensaver" of a "Audio" node`; another says it works. The reported working approach is **an invisible Video node playing the audio stream**. `roAppManager.UpdateLastKeyPressTime()` is said to fail static analysis (Roku developer forum [S]). **Measure on a real Roku before choosing.** Prefer the Video node so the documented field applies.
- **Channels may not bundle a screensaver**: "only standalone screensaver apps are permitted" and streaming apps may not bundle one (Roku screensaver docs [S]); Plex removed theirs (community thread [S]). The Channel Behavior Analysis tool checks whether an app "overrides or interferes with Roku's system screensaver" (Roku cert tests [S]). So the Archive Watch Roku screensaver feature (Party Play/screensaver under Surprise [R: SCRATCHPAD 0-NEW-2026-09-28 (a)]) is an in-app mode, not a system screensaver. The radio app's "now playing" screen should be gently animated art, with the screensaver suppressed only *while audio plays*.
- **Certification**: autoplay rule (since Oct 1 2024: when autoplay is disabled the app may not start playback until the user starts it) [S]; accessibility section 4.8 (comply with applicable laws, captions/audio description where legally required) [S, secondary]. A specific "audio app" or "now playing" certification rule was **not found** [UNVERIFIED]. Continue Watching participation is required from Oct 1 2026 only for apps over 1M hours a month outside the US store [S], so it does not apply.
- Roku's Search feed (Decision 113/117 [R]) is film/TV oriented; whether it ingests audio/radio series is **UNVERIFIED**.
- Roku has no background play: leaving the channel stops audio [K].
- Signing key: never regenerate, per CLAUDE.md [R]. A new channel gets its own key, backed up the same way.

---

## 5. Web (PWA at the site root, plus webOS/Tizen)

- **`<audio>`** plays archive.org MP3 directly: the `download/` nodes answer Range with 206 and no CORS, which media elements do not need [R: CATALOG-CONTRACT]. **Do not set `crossorigin` on the element** unless the source sends CORS; with `crossorigin="anonymous"` and no CORS header, playback fails [K]. That also means **no Web Audio processing** (a `MediaElementAudioSourceNode` on a cross-origin source without CORS outputs silence) [K]. So on the web, the loudness gain is `audio.volume` (cuts only), with no EQ.
- **Media Session API**: `metadata`, action handlers `play`, `pause`, `seekbackward`/`seekforward` (details.seekOffset, default 10 s in MDN's example), `seekto`, `previoustrack`/`nexttrack`, and `setPositionState({duration, playbackRate, position})`. Position must be within [0, duration] and the rate nonzero. `setPositionState` is in Chrome/Edge 81+, Firefox 82+, Safari 15+ (MDN, caniuse [S]). Archive Watch already sets most of this up for video [R: watch.js ~3655].
- **iOS home-screen PWA background audio: not dependable.** Lock-screen playback stops working after about 30 s paused until the PWA is foregrounded again (Apple forums 762582, 2024 [S]); a paused backgrounded MediaSession cannot be resumed (WebKit 243258, 2022 [S]); playback stops when locked in standalone mode but continues from the Safari tab (Discourse thread [S]); WebKit 198277 was still open in 2020 [S]. No 2025/2026 fix was found [UNVERIFIED either way]. **Product consequence:** the website says, on iPhone, "for listening with the screen off, get the app" (a WARNING caption, which the "only essential information" rule allows [R: CLAUDE.md]). It is a fact the listener cannot discover by looking.
- **Offline**: Workbox's guide says runtime caching does not work for media, because playback fetches partial content. Precache with `cache.add()` or `warmStrategyCache`, and serve with CacheFirst plus `RangeRequestsPlugin`. Media elements "need `crossorigin`" for this, and files "can exceed storage quotas" (developer.chrome.com/docs/workbox/serving-cached-audio-and-video [S]). **The conflict:** `cache.add()` is a `fetch()`, and archive.org `download/` sends no CORS, so the service worker gets an **opaque** response. Opaque responses cannot be range-sliced and are padded heavily against quota [K]. **Web offline listening is therefore not feasible against archive.org directly** without a CORS-sending proxy, which would be re-hosting. Measure it (section 12); if it holds, the web gets no downloads, like tvOS (Decision 099).
- The archive.org `/metadata/{id}` API does send CORS [R], so a file list, durations and sizes are readable in the browser.
- webOS/Tizen: the same web layer (`tv.js`), Chromium 85 floor on Tizen 2022+ (Decision 162 [R]). `navigator.mediaSession` support on these TVs is **UNVERIFIED**; media keys come through the existing key shims.

---

## 6. Voice speakers, Sonos, and side doors

### 6.1 Alexa skill (AudioPlayer interface)
- Audio must be at an internet-accessible **HTTPS endpoint on port 443** with a trusted certificate (child streams in a playlist too); formats AAC/MP4, MP3, PLS, M3U/M3U8, HLS; bit rates 16–384 kbps (Amazon, "Stream Long-Form Audio with AudioPlayer" [S]). The `AudioPlayer.Play` directive needs `url` (HTTPS), `token` (≤1024 chars), optional `playBehavior` (REPLACE_ALL default, ENQUEUE); send it from an intent with `shouldEndSession: true` [S].
- archive.org `download/` URLs are HTTPS on 443 with a trusted cert, but they **redirect (302) to a storage node** [K; Archive Watch's pinned-node loader exists because of this, Decisions 031/034 R]. Whether Alexa follows the redirect is **UNVERIFIED**. Measure it; if it does not, the skill resolves the node URL first (via `/metadata`, which names `d1`/`d2`/`server`) [K].
- A skill needs a backend (Lambda or a Worker). Archive Watch already runs a free Cloudflare Worker (SCRATCHPAD item 16 [R]), and one route there could host the skill endpoint at $0 [K, Workers free tier].
- **Classification:** this is a side door. Owner rule: "documented on the website, never a button, row or menu item in the apps' main surfaces" [R: CLAUDE.md].

### 6.2 Google Home / Nest
- Google retired Conversational Actions in June 2023 [K, UNVERIFIED this session]. The live route to Nest speakers is **Cast** from the Android app (§3.6) and Assistant media voice actions (§3.5) on the phone [K].

### 6.3 Sonos
- A Sonos service integration (SMAPI) needs APIs to add content, play it back and sync it; pagination for large lists; defined errors; TLS; allowlisting Sonos's cloud IPs; Extended Metadata is required; register on the Dev Portal, build, test in a sandbox, submit for validation (docs.sonos.com "Key requirements", "Add capabilities" [S]). Commercial terms and whether Sonos accepts a free nonprofit-content service: **UNVERIFIED**. A SOAP/SMAPI server is real infrastructure. **Priority: last, and only if listeners ask.** AirPlay 2 already reaches most Sonos speakers [K].

### 6.4 Podcast RSS feeds (a side door with large reach)
- Apple Podcasts requires RSS 2.0, a publicly reachable feed with no password, the iTunes namespace declared, one unique `<enclosure>` per episode (url, length, type), a GUID that never changes, duplicate enclosure URLs ignored, case-sensitive tags (podcasters.apple.com/support/823 [S]). Podcasting 2.0's `<podcast:transcript>` and `<podcast:chapters>` carry transcripts and chapters (secondary sources [S]; the spec is at github.com/Podcastindex-org/podcast-namespace, not retrieved [UNVERIFIED]).
- **Shape:** one feed per series (`archivewatch.org`-style path such as `/radio/feeds/suspense.xml`), generated in CI from the catalog, enclosures pointing at archive.org `download/` URLs, published on GitHub Pages like the IPTV feeds (Decision 145 [R]). `<itunes:summary>` comes only from archive.org descriptions or Wikidata (no AI copy [R]).
- **Rights caution**: submitting a feed to Apple Podcasts or Spotify publishes the shows under our name. That is a stronger act than a client streaming archive.org. Only the strictest rights tier goes into a submitted feed (like the Roku Search feed advertising only what the audit KEEPS, Decision 113 [R]); unsubmitted feeds on the website can carry what the app shows. Owner decision.
- `length` must be the byte size; take it from archive.org `/metadata` `files[].size` [K].

---

## 7. Standard listening features and their APIs

| Feature | Apple | Android (Media3) | Web | Roku |
|---|---|---|---|---|
| Skip 15/30 s | `skipBackward/ForwardCommand.preferredIntervals` [S] | `seekBack/ForwardIncrementMs`; media button preferences [K/S] | `seekbackward/forward` handlers [S] | own buttons; Audio/Video `seek` [K] |
| Speed 0.75–2× | `AVPlayer.rate` / `defaultRate`; `changePlaybackRateCommand` [S]; `audioTimePitchAlgorithm = .timeDomain` for speech [K] | `setPlaybackSpeed` [K] | `playbackRate` + `preservesPitch` [K] | Video node `playbackSpeed`? [UNVERIFIED] |
| Sleep timer | app timer; fade over 10 s then pause; "end of episode" option [K] | same, in the service so it survives the UI | same | same, a Timer node |
| Smart resume | store `position` per episode; resume minus 5–10 s if paused > N minutes [K] | same + system `onPlaybackResumption` [K] | same (localStorage for per-viewer convenience; the sync islands, Decision 102 R) | same, registry |
| Per-episode progress / "played" | union-merged durable history, Decision 078 [R]; "played" at ≥ 95% or under 60 s left [K] | same | same | same |
| Up Next queue | AVQueuePlayer or own queue + `MPRemoteCommandCenter.nextTrackCommand` [K] | `player.setMediaItems` playlist [K] | own queue + `nexttrack` [S] | ContentNode list [K] |
| Chapters / acts | `MPNowPlayingInfoPropertyChapter*` [K]; AVAsset chapter metadata needs a container that carries it, which MP3 rarely does [K] | timeline markers in own UI | own UI; podcast chapters JSON for the feed | own UI |
| Silence/intro skip | pipeline-computed `introEnd` / `outroStart` seconds, client offers "skip intro" [K] | same | same | same |
| Transcript follow-along | pipeline VTT/JSON; highlight by `currentTime` | same | same (`<track>` on `<audio>` is not rendered; draw it yourself) [K] | label list |

Episode ordering (air date, series and episode numbers) comes from data (the content and metadata tracks of this research), not from the player.

---

## 8. The audio pipeline (CI, GitHub Actions, like the catalog builders)

### 8.1 What OTR files are like [K, measure in section 12]
Mostly MP3, **mono**, 32–128 kbps (many 64 kbps or below), 22.05–44.1 kHz, with transfers from transcription discs and tape: **hiss, crackle, hum, wow, clipped peaks, and level differences of 10 dB or more** between episodes of the same series. Many archive.org uploads ship several derivatives (the original plus archive.org's own VBR MP3 and Ogg derivatives) [K]. Pick one file per episode by a rule (original if MP3; else the VBR MP3 derivative), the same "best copy" logic as Decision 040 [R].

### 8.2 Loudness: measure, store, apply at playback
- Two-pass `loudnorm`: pass 1 `-af loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json -f null -` reports `input_i`, `input_tp`, `input_lra`, `input_thresh`, `target_offset`. A pass 2 would re-encode with `measured_*` values and `linear=true`, and loudnorm "will revert to dynamic normalization if the target loudness range is lower than the source, or if the target loudness produces a true peak above the limit" (secondary guides [S]). Common spoken-word target -16 LUFS, TP -1.5, LRA 11; ffmpeg-normalize defaults to -23 LUFS (EBU R128 broadcast) (slhck.info [S]).
- **Only pass 1 is used.** Store `loudness: {i, tp, lra, measuredAt, tool}`; the client computes `gainDb = target - i`, then clamps so `tp + gainDb ≤ -1`. This keeps archive.org's file as the stream (§2.1), costs one decode per file in CI (≈ 1–3 s of CPU per 30-minute mono MP3 [K, measure]), and lets the target change without rerunning.
- **Pick a target that turns most corrections into cuts** (see §2.11, §5): measure the distribution first (section 12), then choose something like -18 or -19 LUFS if most files sit above it. Native platforms that can boost (AVAudioEngine/tap, Android LoudnessEnhancer) apply positive gain; the web cannot.
- Measure **with the whole file, not a seek window**: loudness stats "are not consistent across different seek/trim settings" [S].
- Fetching files to measure is a lot of bandwidth over archive.org: about 25 MB × N episodes. A 30,000-episode catalog is about 750 GB downloaded once [arithmetic]. Spread it across scheduled runs with per-source "already attempted" markers (Decision 055) and the commit-a-delta lock discipline (Decision 066) [R]. Be polite to archive.org: low concurrency, a contact User-Agent.

### 8.3 Silence, intro and outro detection
- `ffmpeg -af silencedetect=noise=-45dB:d=1.5` gives silence spans [K]. Use leading dead air → `startAt` (auto-skip the first N seconds of silence, which is safe). Theme-music intros are *content*; offering "skip intro" needs a per-series theme fingerprint (chromaprint of the first 60 s matched across episodes) [K]. That is honest data, not a guess. Ship only after measurement shows accuracy.

### 8.4 Commercials and sponsor segments
- OTR sponsor reads are part of the historical record ("Roma Wines presents..."). **Skipping them is an editorial choice the owner should make.** If it is wanted, detection needs ASR (sponsor names are in the transcript) plus a per-series sponsor list from data (Wikidata "sponsor" (P859) on the series item [K, UNVERIFIED property usage]) plus timing. Emit `segments: [{kind:"sponsor", start, end, evidence}]`; the client offers a skip button, never auto-skips. No model-written labels: the evidence is the matched words.

### 8.5 Transcripts: why audio differs from Decision 039b, and what still binds
- **039b recap [R]**: whisper.cpp on film audio was removed after the owner found it "unusable": on old films with poor or music-heavy audio whisper hallucinated coherent-sounding but wrong text. A later decision found archive.org's own ASR just as bad; the reliable signal was the SOURCE (human vs auto), and "a wrong subtitle is worse than none".
- **Why radio is different**: one mono track that is mostly dialogue and narration recorded for the ear; no picture, so a transcript is the only way a deaf user gets the show; and transcripts enable **search inside episodes** ("the one where the train stops at Elko"), which a radio catalog with thin metadata needs. Episodes are short (13–30 minutes), so CI cost is bounded.
- **Why it can still fail the same way**: music bridges, sound effects and long silences are the non-speech audio that drives Whisper hallucination (arXiv 2501.11378 tests Silero and WebRTC VAD as the fix [S]). Silero can mistake near-zero audio for speech; an energy pre-filter was suggested (GitHub discussion [S]).
- **Method if built**: whisper.cpp with `--vad --vad-model <silero>` (flags documented in the repo; threshold default 0.5, min speech 250 ms, min silence 100 ms listed in a server mirror [S, UNVERIFIED for CLI]); temperature 0 and no "condition on previous text" to stop repetition loops [K]; a **hallucination gate** per segment (compression ratio > 2.4, avg logprob < -1, repeated n-grams, the "why why why" ×19 pattern Archive Watch already caught [R]); and **a human sample review of N episodes per series before that series' transcripts ship**. Label every transcript "automatic" in the data; a human transcript from archive.org (some OTR uploads carry scripts) or OTRR-style logs outranks it, the same source ranking as Archive Watch's subtitle decision [R].
- **Where it shows**: (1) search index first, where an error costs a missed hit, not a lie on screen; (2) a "Transcript" view second, behind the gate, saying "automatic transcript" (a WARNING the listener would not otherwise know, so it is allowed [R: CLAUDE.md]).
- **On-device alternative**: Apple **SpeechAnalyzer / SpeechTranscriber** (iOS 26, WWDC25 277) is on-device, async, "suited to long-form and distant audio" [S]; a third-party test transcribed 34 minutes in about 45 s on a Mac [S, informal]. It is **iOS 26+, above the iOS 18 floor** (Decision 155 [R]), and per-device transcripts don't feed a shared search index. Use: optional live "follow along" on iOS 26+ devices for episodes with no pipeline transcript, and the same economics lessons as Archive Watch's caption engine (Decisions 058–074 [R]). Android's `createOnDeviceSpeechRecognizer` is aimed at live mic input, "not intended to be used for continuous recognition", and is slow (official reference, vendor notes [S]). **No Android on-device route; Android uses pipeline transcripts.**
- Cost on GitHub Actions: whisper.cpp base/small on CPU runs at roughly 2–10× real time [K, UNVERIFIED]. 30,000 half-hour episodes is 15,000 hours of audio, which is thousands of runner-hours. **Start with the most-played series only**, measured by Pulse (Decision 108 [R]).

### 8.6 HLS for audio?
No, for now. Reasons: it requires hosting segments (§2.1, 5.2.3), gapless is not needed for self-contained episodes (§2.1), and progressive MP3 with Range already seeks on every platform. VBR MP3 seeks *approximately* by byte offset unless a Xing/VBRI TOC is present [S for the CBR/VBR point, old thread; K for TOC]. Measure seek accuracy on archive.org's VBR derivatives (section 12); if a series' VBR files seek badly, prefer the CBR original file.

### 8.7 Output contract (per episode, added to the catalog)
`archiveID`, `file`, `bytes`, `durationSec`, `bitrate`, `sampleRate`, `channels`, `loudness{i,tp,lra}`, `startAt`, `segments[]`, `transcript{url, source: human|auto, gate}`, `hasXingToc`. Additive and merge-guarded (Decision 020 [R]); a run that produced nothing goes red (Decisions 093/107 [R]).

---

## 9. Capability matrix

Legend: Y = supported natively; P = possible with caveats; N = not available or not worth it; ? = unverified. Effort: S/M/L.

| Capability | iOS/iPadOS | macOS | tvOS | watchOS | CarPlay | Android phone | Android Auto | AAOS | Wear OS | Google TV | Fire TV | Roku | Web (desktop/Android) | Web (iOS PWA) | Alexa | Sonos |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Stream archive.org MP3 | Y | Y | Y | Y | Y (phone) | Y | Y | Y | Y | Y | Y | Y | Y | Y | ? redirect | P (SMAPI) |
| Background / screen-off play | Y (`audio` mode) | Y | Y (keeps playing, idle overlay [S]) | Y (BT out) | Y | Y (service) | Y | Y | Y (BT out [S]) | ? (should, §3.7) | ? | N (in-channel only) | P | **N, unreliable [S]** | Y | Y |
| Lock screen / system controls | Y | Y (Control Center) | Y | Y | Y | Y | Y | Y | Y | ? | ? | N | Y (Media Session [S]) | P | n/a | n/a |
| Skip intervals | Y [S] | Y | Y | Y | Y (or track buttons, not both [S]) | Y | Y | Y | Y | Y | Y | own UI | Y | P | voice | ? |
| Speed | Y | Y | Y | ? | Y | Y | ? | ? | ? | Y | Y | ? | Y | Y (fg) | N | N |
| Downloads / offline | Y (Decision 099) | Y | N (Decision 099) | Y | via phone | Y | via phone | P | P | N | N | N | **N vs archive.org (no CORS) [K]** | N | N | N |
| Voice play | Siri/App Intents | Siri | Siri | Siri | Siri | Assistant [S] | Assistant [S] | Assistant | ? | Assistant | Alexa? | Roku voice ? | N | N | Y (skill) | Sonos voice ? |
| Listen together | SharePlay [S] | SharePlay | SharePlay | N | N | rooms (Worker) [R] | N | N | N | rooms join [R] | rooms join [R] | ? | rooms join [R] | rooms join | N | N |
| Cast / AirPlay out | AirPlay 2 | AirPlay 2 | (is a receiver) | N | n/a | Cast (google flavor) [S] | n/a | n/a | output picker [S] | (is a receiver) | N | N | Remote Playback API ? | AirPlay | n/a | n/a |
| Runtime loudness gain | Y (cut; boost via tap) | Y | Y | Y | Y | Y (LoudnessEnhancer) | Y | Y | Y | Y | Y | ? volume field | cut only (no CORS for Web Audio) [K] | cut only | N | N |
| Runtime EQ | P (tap/engine) | P | P | N | via phone | P (AudioProcessor) | via phone | P | N | P | P | N | N (no CORS) | N | N | N |
| On-device transcript | iOS 26+ SpeechAnalyzer [S] | macOS 26+ | ? | N | N | N (live-mic API only [S]) | N | N | N | N | N | N | N | N | N | N |
| Widget / home surface | Y (App Intents [S]) | Y | Top Shelf | complication | CarPlay widgets iOS 26 [S] | Glance widget | n/a | n/a | tile | Continue row ? | ? | N | N | N | N | N |
| Review gate | App Review + CarPlay entitlement [S] | App Review | App Review | App Review | entitlement [S] | Play | Play car review [S] | Play car review | Play Wear review | Play TV review | Amazon | Roku cert [S] | none | none | Alexa cert | Sonos validation [S] |

---

## 10. Minimum viable audio shell, per platform (checklists)

Common to all: progressive MP3 from archive.org through the shared network client (CLAUDE.md "never fetch directly from a view" [R]) with node pinning and failover (Decisions 031/034 [R]); per-episode position saved every 5–10 s and on pause; resume with a small rewind; "played" marking; series → episodes browse ordered by air date from data; skip back 15 / forward 30; speed 0.75–2×; sleep timer (minutes and end of episode); up-next within a series; pipeline loudness gain applied; error states the listener can see; the universal empty/loading/error states per list (`universal-feature-states` skill).

**iOS / iPadOS (first)**
- [ ] `UIBackgroundModes: audio`; `.playback` + `.spokenAudio`, `.longFormAudio` route policy
- [ ] Interruption handling (resume with rewind); pause on headphones unplugged
- [ ] Now Playing info (title, series, artwork, elapsed, duration, rate) + remote commands (play/pause/toggle, skip 15/30, changePlaybackPosition, changePlaybackRate)
- [ ] Mini player + full player; rate and sleep timer controls
- [ ] Background URLSession downloads, storage cap, auto-download next N for followed series
- [ ] App Intents: `AudioPlaybackIntent` play series/episode, "resume" with no argument; App Shortcuts phrases
- [ ] AirPlay route picker
- [ ] Request the **CarPlay audio entitlement on day one** (calendar lead time)
- [ ] CarPlay: tab bar (Continue, Series, Downloads), list templates paged under 500 items, `CPNowPlayingTemplate`
- [ ] SharePlay listen together (reuse Decision 098)

**macOS**
- [ ] Same core; menu bar or Dock menu controls; media keys through `MPRemoteCommandCenter`; keyboard shortcuts (space, arrows, J/K/L)
- [ ] Mini-player window (`macos-native-app-shell` skill [R])

**tvOS**
- [ ] Same core minus downloads; artwork good enough for the idle overlay [S]; no custom screensaver
- [ ] Top Shelf "Continue listening" (Decision 049 pattern [R])
- [ ] Focus rules from `docs/tvos-playbook.md`, and never `buttonStyle(.plain)` [R]

**watchOS (later)**
- [ ] Downloaded episodes synced from the phone; play only to Bluetooth output; Now Playing controls

**Android phone (first on Android)**
- [ ] `MediaLibraryService` + ExoPlayer, foreground service type `mediaPlayback`, `USAGE_MEDIA` + `CONTENT_TYPE_SPEECH`, audio focus, becoming-noisy pause
- [ ] Notification with custom skip 15/30 buttons (media button preferences)
- [ ] `onPlaybackResumption` for system resume
- [ ] Assistant: play/prepare from search, empty query → resume
- [ ] Downloads through Media3's `DownloadService` or WorkManager [K]
- [ ] Browse tree with stable IDs (archiveID/filename)

**Android Auto (same APK)**
- [ ] `automotive_app_desc.xml` `<uses name="media"/>`; root tabs; content-style hints; artwork URIs; voice search
- [ ] Pass the "Android app quality for cars" media checklist (retrieve the current MUSTs first) [UNVERIFIED]

**Google TV / Fire TV**
- [ ] Session ON for audio (confirm the TV audio guideline) [UNVERIFIED]; Back from root to launcher; a now-playing screen with series art; no GMS on Fire TV

**Wear OS (later)**
- [ ] Suppress playback on unsuitable output + resolver listener [S]

**Roku**
- [ ] Play via a Video node (hidden) so `disableScreenSaver` applies **only while playing**, or measure the Audio node [S]
- [ ] Now-playing screen; options panel (speed if supported, sleep timer); resume from registry
- [ ] Autoplay rule (no start without a user action when autoplay is off) [S]; no bundled screensaver [S]

**Web**
- [ ] `<audio>` without `crossorigin`; Media Session metadata, handlers and `setPositionState` [S]
- [ ] iPhone warning: screen-off listening needs the app [S]
- [ ] No offline (unless the no-CORS probe in section 12 proves otherwise)
- [ ] Chromium 85 compat on the TV packages (Decision 162 [R])

---

## 11. Review pitfalls for audio apps

**Apple**
- **5.2.3**: "Apps should not facilitate illegal file sharing or include the ability to save, convert, or download media from third-party sources ... without explicit authorization"; "streaming of audio/video content may also violate Terms of Use"; documentation may be requested; other apps passing "is never an argument"; Movist was pulled in 2019 over "downloading 3rd party media" (forum threads, mjtsai.com [S]). Archive Watch was rejected under 5.2.3 on build 1.0 (36), 2026-06-16, and answered with a paste-ready reply plus a rights-evidence PDF [R: docs/app-store-review-5.2.3-response.md]. **Radio-specific changes to that answer:** (a) the app *does* download (offline episodes), so say plainly that downloads are of public-domain works from archive.org's public endpoints, stored in the app sandbox, never exported as files; (b) OTR rights are messier than film (unpublished broadcasts, transcription discs, scripts and music under separate copyright, and the 1972 sound-recording rule for US pre-1972 recordings under the Music Modernization Act's Classics Protection, which put pre-1923 recordings into the public domain on 2022-01-01 and later recordings on a rolling schedule [K, UNVERIFIED here; the rights track must confirm]); the PDF needs its own radio methodology from the rights research track; (c) never offer "save to Files" / share the MP3.
- **4.2 Minimum Functionality**: an app should offer "features, content, and UI that go beyond a repackaged website" (Apple text as quoted in forums [S]); rejections cite "usefulness limited by the minimal amount of content or features" [S]. A catalog browser over archive.org could be read that way; the native shell (downloads, CarPlay, Siri, sleep timer, SharePlay, transcripts) is the answer. Do not ship v1 as a thin list player.
- **4.3 Spam**: a second app from the same developer that looks like Archive Watch with audio could draw a 4.3 "similar apps" question [K, UNVERIFIED]. The audio-first design (car, sleep timer, episodic resume) is what differentiates it; say so in the review notes.
- **Background audio misuse**: Apple rejects apps that declare the `audio` background mode without playing audible content [K]. Only enter the mode while playing.
- **CarPlay**: the entitlement is reviewed separately, and the CarPlay guide's guidelines apply [S]; using the wrong template class or a non-audio template is a reject [K].
- **Metadata**: the App Store listing must not claim "all public domain" more strongly than the evidence (the same rights posture as 5.2.3).

**Google Play**
- Car apps need to pass the car quality review before listing [S]; Wear and TV form factors each have their own review [K].
- Foreground service type declaration (`mediaPlayback`) is checked on Android 14+ targets [K].
- Play's "Repetitive content" and "Minimum functionality" policies mirror Apple's 4.2/4.3 [K, UNVERIFIED].
- Play automatic protection needs minSdk 24 (Decision 165 [R]).

**Roku**
- Channel Behavior Analysis flags apps that override or interfere with the system screensaver [S]; a bundled screensaver is not allowed [S]; the autoplay rule [S]. An audio channel that leaves the screen frozen for a long time may fail on design review [K, UNVERIFIED]; animate the now-playing art gently.

**Amazon / Alexa**
- Alexa: HTTPS 443, trusted certs, `shouldEndSession` [S]; skill certification tests that pause, resume, next and previous are handled (`AudioPlayer.PlaybackNearlyFinished` for the queue) [K].

---

## 12. To measure (probes for a session with network access)

```bash
# 1. archive.org MP3 serving: redirect, Range, CORS, content type, Xing TOC
ID=suspense_otr   # replace with a real OTR item id
curl -sI "https://archive.org/download/$ID/" | head
curl -s "https://archive.org/metadata/$ID" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("d1"), d.get("server"), d.get("dir")); [print(f["name"], f.get("format"), f.get("size"), f.get("length"), f.get("bitrate")) for f in d["files"] if f["name"].endswith(".mp3")][:10]'
F="<file.mp3 from above>"
curl -sIL -H "Range: bytes=0-1023" -H "Origin: https://archivewatch.org" "https://archive.org/download/$ID/$F" | grep -iE "^HTTP|location|accept-ranges|content-range|content-type|access-control"
curl -sL -r 0-4095 "https://archive.org/download/$ID/$F" | xxd | grep -m2 -E "Xing|Info|VBRI"   # TOC present?

# 2. File characteristics across a sample of 200 OTR files
ffprobe -v error -show_entries stream=codec_name,sample_rate,channels,bit_rate:format=duration,bit_rate -of json "$F"

# 3. Loudness distribution (decides the playback target, section 8.2)
ffmpeg -hide_banner -nostats -i "$F" -af loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json -f null - 2>&1 | tail -12
# Run over 200 files; report median/p10/p90 of input_i and input_tp; pick a target that about 80% of files sit above.
# Time it: `time` the command to size the CI budget.

# 4. Silence / dead air at start
ffmpeg -hide_banner -nostats -i "$F" -t 120 -af silencedetect=noise=-45dB:d=1.5 -f null - 2>&1 | grep silence_

# 5. Transcription quality gate (whisper.cpp with VAD), on 10 episodes of 3 series
./whisper-cli -m ggml-small.en.bin --vad --vad-model ggml-silero-v5.1.2.bin -f ep.wav -ojf
# Score: count segments with compression ratio > 2.4 or repeated 3-grams; human-check 5 minutes per episode.
# Compare with SpeechTranscriber on a Mac running macOS 26 (same files): word error vs a human script if one exists.
```

- **Web offline**: in Chrome and Safari, from a page on archivewatch.org, `caches.open('t').then(c=>c.add(new Request(url,{mode:'no-cors'})))` against an archive.org MP3; then try to play it through a Workbox RangeRequestsPlugin route. Expect failure (opaque); record the quota consumed (`navigator.storage.estimate()`).
- **iOS PWA background**: on iPhone 15 Pro (iOS 27.2) and iPhone 12 (26.6.1) [R: device list in Decision 155], install a test PWA, play, lock, wait 5/30/120 s paused, resume from Lock Screen. Record each.
- **Roku screensaver**: on a real Roku, play an MP3 with (a) an Audio node, (b) an Audio node with `disableScreenSaver`, (c) a hidden Video node with `disableScreenSaver=true`; set the system screensaver to 1 minute; record which keeps playing and what the debug console prints.
- **Alexa redirect**: a test skill `AudioPlayer.Play` with an `archive.org/download/...` URL (302) vs the resolved node URL.
- **Siri on HomePod**: "Play Suspense on <app>" with (a) App Intents only, (b) with an INPlayMediaIntent handler.
- **Android TV session**: read the current TV quality guidelines' audio-app items (TV-NP and the Now Playing card) and run the session ON on the Google TV dongle.
- **Retrieve and quote**: Android app quality for cars (media MUSTs); CarPlay App Programming Guide PDF (audio section); App Store Review Guidelines 4.2, 4.3 and 5.2.3 current text; WWDC26 312's OS minimum; Fire TV audio app guidance; Sonos partner terms for a free service; Podcast namespace `transcript`/`chapters` spec.

---

## Sources

Apple
- https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements.md
- https://developer.apple.com/forums/thread/684491 (CarPlay audio entitlement, DTS reply)
- https://developer.apple.com/forums/thread/823974
- https://developer.apple.com/forums/thread/798894 (CPListTemplate 500 items, no lazy images)
- https://developer.apple.com/forums/thread/813008 (CarPlay depth)
- https://developer.apple.com/forums/thread/772603 (skip intervals vs track buttons in CarPlay)
- https://skills.cat/skills/ios-agent/iosagent-dev/carplay (third-party; key name, tab limits)
- https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter.md
- https://developer.apple.com/documentation/mediaplayer/mpskipintervalcommand.md
- https://developer.apple.com/forums/thread/699904
- https://developer.apple.com/forums/thread/768926 (AudioPlaybackIntent vs INPlayMediaIntent; widgets need App Intents)
- https://developer.apple.com/videos/play/wwdc2019/207/ (SiriKit Media Intents)
- https://developer.apple.com/forums/thread/124605
- https://developer.apple.com/videos/play/wwdc2019/716 (watchOS streaming audio)
- https://developer.apple.com/forums/thread/666946 · https://developer.apple.com/forums/thread/664474
- https://developer.apple.com/videos/play/wwdc2026/312/ (Meet the Now Playing framework)
- https://github.com/ivan-magda/wwdc26-notes/blob/main/sessions/312-now-playing-framework/digest.md (secondary)
- https://developer.apple.com/videos/play/wwdc2022/110338 (Now Playing; tvOS idle overlay)
- https://developer.apple.com/videos/play/wwdc2017/251 (tvOS audio metadata badge and idle display)
- https://developer.apple.com/forums/thread/786594
- https://developer.apple.com/videos/play/wwdc2025/216/ (CarPlay iOS 26)
- https://techcrunch.com/2025/06/09/apple-adds-widgets-and-message-tapbacks-to-carplay-with-ios-26
- https://developer.apple.com/videos/play/wwdc2021/10225/ (Group Activities coordinated playback)
- https://developer.apple.com/tutorials/data/documentation/avfoundation/supporting-coordinated-media-playback.md
- https://developer.apple.com/forums/thread/111413 (AVQueuePlayer gapless)
- https://nonstrict.eu/wwdcindex/wwdc2021/10142/ (HLS gapless)
- https://developer.apple.com/videos/play/wwdc2025/277/ (SpeechAnalyzer)
- https://www.gigazine.net/gsc_news/en/20250619-apple-speech-analyzer (secondary; speed test)
- https://developer.apple.com/forums/thread/762582 (iOS PWA lock-screen audio)
- https://bugs.webkit.org/show_bug.cgi?id=243258 · https://bugs.webkit.org/show_bug.cgi?id=198277
- https://meta.discourse.org/t/media-playback-with-pwa-keep-playing-when-phone-locked/182219
- https://developer.apple.com/forums/thread/765340 · https://developer.apple.com/forums/thread/131199 · https://developer.apple.com/forums/thread/776749 (5.2.3)
- https://mjtsai.com/blog/2019/05/27/movist-removed-from-the-mac-app-store
- https://developer.apple.com/forums/thread/108931 · https://developer.apple.com/forums/thread/816069 (4.2)
- https://podcasters.apple.com/support/823-podcast-requirements

Android / Google
- https://developer.android.com/media/media3/session/serve-content
- https://developer.android.com/training/cars/media
- https://developer.android.com/design/ui/cars/guides/app-types/create-media-apps
- https://developers.google.com/cars/design/automotive-os/apps/media/app-checklist
- https://developers.google.com/cars/design/create-apps/ux-requirements/overview
- https://developers.google.com/cars/design/automotive-os/apps/media/overview
- https://appdevelopers.harman.com/migrate-to-android-automotive (secondary)
- https://skillsmp.com/creators/sunnat629/android-media-pack/skills-media-ui-media3-android-auto-media-surface (third-party)
- https://developer.android.com/media/implement/assistant
- https://developer.android.com/training/wearables/apps/audio
- https://developer.android.com/reference/kotlin/androidx/media3/ui/WearUnsuitableOutputPlaybackSuppressionResolverListener
- https://google.github.io/horologist/media-sample/
- https://developer.android.com/reference/androidx/media3/session/MediaLibraryService.MediaLibrarySession.Builder
- https://thenote.app/post/en/media3-1-8-0-whats-new-ginwrpilk4 (secondary)
- https://developer.android.com/reference/android/speech/SpeechRecognizer
- https://nllapps.com/apps/cb/transcription-help.htm (vendor)
- https://developers.google.cn/cast/docs/caf_receiver · https://developers.google.com/cast/docs/migrate_v2/receiver
- https://www.radiantmediaplayer.com/docs/v9/google-cast.html (third-party)
- https://developer.chrome.com/docs/workbox/serving-cached-audio-and-video

Roku
- https://developer.roku.com/dev/docs/screensavers
- https://forum.developer.roku.com/t/how-to-prevent-screensaver-while-playing-live-audio/11296
- https://forum.developer.roku.com/t/audioplayer-invokes-screensaver-how-to-turn-off/10128
- https://forum.developer.roku.com/t/playing-audio-stops-when-screensaver-activates/8769
- https://forum.developer.roku.com/t/audio-channel-screensaver-question/11102
- https://community.roku.com/t5/Channels-viewing/What-Roku-guideline-caused-Plex-to-remove-screensaver/m-p/881484
- https://developer.roku.com/dev/docs/certification
- https://developer.roku.com/docs/developer-program/certification/cert-tests/channel-behavior-analysis-tool.md
- https://developer.roku.com/dev/docs/autoplay
- https://developer.roku.com/dev/docs/continue-watching
- https://cordcuttersnews.com/roku-is-working-on-making-streaming-more-accessible-to-those-with-disabilities-is-putting-new-limits-on-autoplay/

Web
- https://developer.mozilla.org/en-US/docs/Web/API/MediaSession/setPositionState
- https://developer.mozilla.org/docs/Web/API/MediaSession
- https://caniuse.com/mdn-api_mediasession_setpositionstate
- https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Range · https://http.dev/accept-ranges
- https://lists.xiph.org/pipermail/vorbis/2002-June/007975.html (CBR vs VBR byte seeking, historical)

Alexa, Sonos, podcasts
- https://developer.amazon.com/en-US/docs/alexa/custom-skills/use-long-form-audio.html
- https://www.jovo.tech/marketplace/jovo-platform-alexa/interfaces/audio-player (secondary)
- https://docs.sonos.com/docs/key-requirements · https://docs.sonos.com/docs/add-capabilities · https://docs.sonos.com/docs/sonos-partners-3p-guidelines-tou
- https://github.com/Podcast-Standards-Project/PSP-1-Podcast-RSS-Specification

Audio pipeline
- https://dev.to/javidjamae/ffmpeg-loudnorm-filter-ebu-r128-loudness-normalization-guide-15d4 (secondary)
- https://slhck.info/ffmpeg-normalize/usage/options
- https://animethemes.moe/wiki/encoding/audio_normalization (secondary)
- https://en.wikipedia.org/wiki/ReplayGain · https://www.beatunes.com/en/itunes-replay-gain.html
- https://en.wikipedia.org/wiki/Gapless_playback · https://hydrogenaudio.org/index.php/topic,63480.0.html
- https://arxiv.org/pdf/2501.11378 (Whisper hallucinations on non-speech audio)
- https://huggingface.co/spaces/Xenobd/whisper.cpp/commit/a28f35edf723da32f73be27cb7cf92283444494e (whisper.cpp VAD commit mirror)
- https://docsearch.algolia.com/mcp/docs/repo/ggml-org/whisper.cpp
- https://github.com/linto-ai/whisper-timestamped/issues/74 (Silero near-silence)

Repository (Archive Watch's own evidence)
- /home/user/Archive-Watch/docs/app-store-review-5.2.3-response.md
- /home/user/Archive-Watch/docs/decisions/DECISIONS-031-060.md (039b and its successor)
- /home/user/Archive-Watch/docs/CATALOG-CONTRACT.md, /home/user/Archive-Watch/docs/WEB-DESIGN.md §2.5 (Range/CORS measured 2026-06-09)
- /home/user/Archive-Watch/docs/TV-PLATFORM-EXPANSION.md item 5, /home/user/Archive-Watch/docs/TV-PLATFORM-BACKLOG.md A15 (TV-NP)
- /home/user/Archive-Watch/ArchiveWatch/ArchiveWatch/Services/{NowPlayingWarmup,TVAudioSession,DownloadManager,WatchTogether,BackgroundRefresh}.swift
- /home/user/Archive-Watch/android/app/src/main/java/app/archivewatch/android/ui/screens/PlayerScreen.kt
- /home/user/Archive-Watch/watch.js (Media Session, around line 3655)
