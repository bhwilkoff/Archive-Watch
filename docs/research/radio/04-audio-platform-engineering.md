# Audio-first platform engineering, per platform (research for the old-time-radio sister app)

*Date: 2026-10-17. Research track 04. Nothing here is built.*

**How to read this file.** For most of this session only web search worked; page fetches were blocked. Network access opened near the end, and the load-bearing claims were then checked against the primary pages, and two archive.org MP3s were measured. Every fact is tagged one of four ways:

- **[V]**: VERIFIED. The primary page was fetched on 2026-10-17 and quoted, or the value was MEASURED in this container (section 8.0). Pages read: App Store Review Guidelines ("Last Updated: October 16, 2026"); the CarPlay Developer Guide PDF (October 2026, footer dated 2026-10-13); Apple's "Requesting CarPlay Entitlements"; Android "Car app quality"; Android "TV app quality" (last updated 2026-06-29); Roku Video and Audio node references; Amazon Alexa AudioPlayer reference.
- **[S]**: the fact came from a search-result snippet of the URL cited. The page itself was not opened.
- **[R]**: the fact came from this repository, with a path. Archive Watch has already measured or shipped it.
- **[K] UNVERIFIED**: prior knowledge of the platform that no source fetched this session confirms. Check it against the live documentation before relying on it. "To measure" (section 12) lists a probe for each of these that matters.

---

## Verdict

1. **The audio shell is easier than the video shell on every platform but one.** Background audio, lock-screen and car controls, and voice play all hang off one object per platform: `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` on Apple (and, from the 2026 SDKs, the new **Now Playing framework**, WWDC26 session 312 [S]), a Media3 `MediaLibraryService` on Android, and the Media Session API on the web. Build that object first and CarPlay, Android Auto, Wear, Assistant and Siri mostly follow from it.
2. **The web is the exception, and it is a serious one: an installed iOS home-screen PWA is not a dependable background audio player.** Lock-screen audio in a standalone PWA stops working after it has been paused for about 30 seconds (Apple Developer Forums 762582, 2024 [S]), and WebKit bug 243258 (a paused, backgrounded MediaSession cannot be resumed) was filed in 2022 [S]. No 2025 or 2026 fix was found. Treat the web as a way to discover and try shows. iPhone listeners need the native app. Plain Safari tabs behave better than installed PWAs [S, Discourse thread]. **One web constraint has eased:** archive.org storage nodes now send `Access-Control-Allow-Origin: *` on ranged MP3 GETs, and so does the `archive.org/download/` 302 [V, measured 2026-10-17]. The repo recorded "no CORS" on 2026-06-09 [R]. That makes Web Audio gain and EQ, and service-worker offline caching, possible on the web (§5).
3. **Cars are the biggest new surface, and both are gated.** CarPlay: you request `com.apple.developer.carplay-audio` at developer.apple.com/contact/carplay and agree to the CarPlay Entitlement Addendum, Apple reviews the request "using predefined criteria", and then the CarPlay Developer Guide's rules apply [V]. Those rules include "never show song lyrics on the CarPlay screen" (so no transcripts in the car), a template depth of 5 for audio apps, up to 4 tabs, and lists that "some cars dynamically limit ... to 12 list items" [V]. Android Auto needs a media browse tree, and every car app gets "an additional manual review beyond normal Play Store review". The media rules in force: support Gemini and Google Assistant voice commands (VC-1, May 2026), never autoplay on startup (MA-1), launch and load content in 10 seconds or less (DR-2/3), and no animated elements (SA-1) [V]. Both platforms are template-driven, so you write data, not UI.
4. **On Android TV the rule flips, and Google's own text says so.** TV-NP: "If the app continues to play audio after the user returns to the home screen ... the app provides media controls in the system UI (such as a card or notification) ... Video apps must not use these media controls." The criterion was narrowed to audio playback in May 2024 [V]. Archive Watch switched its session OFF on TV because it is a video app [R: docs/TV-PLATFORM-EXPANSION.md item 5]. The radio app **must** keep it ON.
5. **Roku's screensaver is the trap, and the docs settle which node to use.** The **Video** node's `disableScreenSaver` is "typically used to suppress the screensaver when playing audio-only streams". The Video node's own `enableScreenSaverWhilePlaying` "has no effect when the video node plays audio only streams", and the **Audio** node reference has no screensaver field at all [V]. So: play audio through a Video node with `disableScreenSaver=true` while playing, which matches the developers' workaround [S]. Channels may not bundle a screensaver [S].
6. **Loudness: measure it in the pipeline and store a gain. Do not re-encode.** MEASURED on two copies of the same 1942 *Suspense* episode: both are mono 44.1 kHz MP3, at 32 kbps and 128 kbps, with integrated loudness of -18.85 and -18.39 LUFS and true peaks of -2.59 and -0.43 dBTP [V, §8.0]. Use the `ebur128` filter (about 10 s per 30-minute file here) rather than `loudnorm` (about 53 s). Store the values in the catalog and apply the gain at playback. archive.org stays the host and nothing is re-uploaded, the same "compute in the pipeline, the client applies it" rule as Decision 050 [R].
7. **Transcripts: the case for pipeline ASR is stronger for audio than it was for video, and Decision 039b's lesson still binds.** Whisper was dropped for film captions because it HALLUCINATED on poor, music-heavy film audio [R: DECISIONS-031-060 039b]. OTR is one mono speech track with short episodes, but it also carries organ stings, sound effects and hiss, which are exactly what produces hallucination (arXiv 2501.11378 [S]). Ship transcripts only with VAD gating (whisper.cpp `--vad` with a Silero model [S]), a hallucination detector, and a human-review sample before the first shelf goes out. Use them first for search, and display them second.
8. **Store risk is Archive Watch's own risk again, plus one new one.** 5.2.3 (streaming from third-party sources) Archive Watch has already answered [R: docs/app-store-review-5.2.3-response.md]. 4.2.2 reads "Other than catalogs, apps shouldn't primarily be ... content aggregators, or a collection of links" [V], so present the app as a catalog with native depth (section 10). The new risk is **4.3(a): "Don't create multiple Bundle IDs of the same app"** [V]. A second Archive-Watch-shaped app from the same developer has to be visibly a different product (audio-first, car, sleep timer, episodic resume), and the review notes should say so.

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
| archive.org Range/CORS facts | `docs/CATALOG-CONTRACT.md` notes; `docs/WEB-DESIGN.md` §2.5 | The repo says `download/` nodes serve 206 **without CORS** (measured 2026-06-09). **Re-measured 2026-10-17 for an MP3: the 302 and the node both send `access-control-allow-origin: *`** (§5). The `/metadata` API sends CORS |
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
- **Request** [V, "Requesting CarPlay Entitlements"]: "request the appropriate entitlement for your app's category at CarPlay Contact Us (developer.apple.com/contact/carplay) and agree to the CarPlay Entitlement Addendum. Apple reviews each application using predefined criteria. If your request meets the criteria, Apple adds the entitlement to your developer account using managed capabilities." Then: enable "CarPlay Audio App (CarPlay framework)" under the App ID's Additional Capabilities, make a new provisioning profile, **turn off automatic signing** and download the profile, and add `com.apple.developer.carplay-audio` = true to the entitlements file. The key needs iOS 14+, and "Multiple CarPlay entitlements may not be combined in a single app" (CarPlay Developer Guide, October 2026 [V]). Archive Watch signs through the cloud workflow with manual REST signing (`apple-app-store-cli-submission` skill [R]), so the CarPlay profile has to go into that pipeline. Review time "1–2 weeks" is a third-party estimate only [UNVERIFIED].
- **Rules** (CarPlay Developer Guide, "Guidelines for all CarPlay apps" plus "Additional guidelines for CarPlay audio apps" [V]): audio apps "must be designed primarily to provide audio playback services"; never tell people to pick up the iPhone; every flow must work without the iPhone; nothing unrelated to the primary task (no unrelated settings); use templates only for their intended information types ("album artwork in the now playing screen must be used to show an album cover"); **"Never show song lyrics on the CarPlay screen"**. Treat a transcript as lyrics: no transcripts in CarPlay. Audio and video CarPlay apps also appear on Apple HomeView without changes [V].
- **Templates** [V, same guide]: the tab bar "allows up to 4 tabs for audio apps", and "the now playing button may not appear if your tab bar has more than 4 tabs". Audio apps "are limited to a depth of 5 templates", including the root. Lists: "Some cars dynamically limit lists to 12 list items ... you always need to be prepared to handle the case where only 12 list items are shown". iOS 26 added pinned elements at the top of a list. iOS 27 adds portrait or landscape images, playback-progress overlays on thumbnails, and a details header. Now Playing: "You must be prepared to populate the now playing template at all times", and only a list template may be pushed on top of it (for example, an Up Next queue). From iOS 27 there is a MiniPlayer (`allowsMiniPlayer`). The 500-item app maximum comes from an Apple engineer on the forums [S]. Images are not lazy-loaded, so supply them at the item's maximum size [S].
- **Design consequence:** use 4 tabs at most, for example *Continue · Series · Downloads · Channels*. Every list has to work at 12 rows: its first 12 rows must be the most useful ones (recent, next unplayed), with "more" pushed deeper and within the 5-template depth. A 1,000-episode series is paged by year. **Downloads matter more in the car** (dead zones). The iOS 27 progress overlay on list thumbnails suits per-episode progress.
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
- The app "must meet specific design requirements before it can be listed on Google Play for Android Auto or AAOS" [S]. **Car app quality, the criteria that apply to Media** [V, developer.android.com/docs/quality-guidelines/car-app-quality, fetched 2026-10-17]:
  - EP-1 works as described in the listing. EP-2: "When the app is relaunched from the home screen, the app must restore the app state as closely as possible to the previous state". EP-4 (AAOS, August 2026): the listing must include AAOS screenshots.
  - PE-1 (AAOS): apart from setup, settings and sign-in while parked, no functionality through the app's own activities.
  - SA-1 no animated elements. AD-1 no text ads beyond an advertiser or product name. IU-1 no images except "a single static image for content context in the background of the consumption screen, such as album art". ST-1 no auto-scrolling text, so a scrolling transcript is out in the car. VI-1 if the user must use the phone, say to do it only when safe.
  - **VC-1: "The app must support Gemini and Google Assistant voice commands"** (updated May 2026).
  - DR-1 buttons respond within 2 s. DR-2 launch within 10 s. DR-3 load content within 10 s.
  - VD-1/2/3 contrast; white icon sets that the system colorizes. GB-1 disabled elements are nonfunctional.
  - NA-1 no ads in notifications. IN-1 notifications only when relevant to the driver ("Bad: Notifying the user about a new album release", so no "new episode" notifications in the car).
  - **MA-1: "The app must not autoplay on startup or without user initiated action"**.
  - DL-2 (AAOS) supports deep links.
  - Process: "Apps for cars are subject to an additional manual review beyond normal Play Store review". Failures are emailed. **"Any subsequent updates are not available for distribution until the app is approved"**, and Google warns "you shouldn't use your production APK for Android Auto support prototyping" [V]. That matters to Archive Watch's one-artifact promotion flow (Decision 110 [R]): the first car-enabled release can hold up phone updates.
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
- **Keep MediaSession ON for audio on TV.** The TV app quality text [V, last updated 2026-06-29]. TV-NP: "If the app continues to play audio after the user returns to the home screen or switches to another app, the app provides media controls in the system UI (such as a card or notification) so users can return to the app to control playback ... Video apps must not use these media controls" (May 2024: "updated to apply only to audio playback, not video"). TV-PA: selecting those controls opens a screen where the user can pause. TV-PC: D-pad center pauses and resumes; left and right fast-forward and rewind "the current track". Archive Watch's TV session is off because it is a video app [R]; the radio app inverts that by rule, not by taste.
- Fire TV: no specific audio guidance was retrieved (search budget exhausted) [UNVERIFIED]. Fire OS is Android, so the Media3 session gives the system's media controls [K]. Amazon's review checks Back behavior (Archive Watch's A16: Back returns to the launcher from root [R]).
- A TV audio screen needs something to look at: series art, episode art, an elapsed bar, and transcript lines if they exist. Burn-in: keep slowly moving or dimming art on OLED [K].

---

## 4. Roku

- **Audio node** (SceneGraph): `content` (a ContentNode with url and streamformat "mp3"), `control` ("play"/"stop"/"pause"/"resume") [K]. The reference [V] documents `seek` (write-only, "the number seconds from the beginning of the stream, specified as a double"), `contentIsPlaylist` / `contentIndex` (audio playlists), `autoplayAfterSeek`, `mute`, `streamInfo`, and timed metadata. **It has no screensaver field.**
- **The screensaver problem**: a screensaver is "automatically invoked when either a video, game, utility, or application has been idle" (Roku screensaver docs [S]). Developers report audio channels being interrupted by it, some with the audio *stopping* (forum threads [S]). The **Video** node reference [V]: `disableScreenSaver` (Boolean, default false): "Set this to true to suppress the screensaver. This is typically used to suppress the screensaver when playing audio-only streams". The Video node's `enableScreenSaverWhilePlaying` "has no effect when the video node plays audio only streams. For screensaver control with audio only streams, use the disableScreenSaver field." One developer's `Tried to set nonexistent field "disablescreensaver" of a "Audio" node` [S] is consistent with the Audio reference. **Decision: play OTR through a Video node (no visible video) with `disableScreenSaver=true` while playing and false while paused**, the forum's working approach [S]. Avoid `roAppManager.UpdateLastKeyPressTime()`, said to fail static analysis [S]. Confirm on a real Roku.
- **Channels may not bundle a screensaver**: "only standalone screensaver apps are permitted" and streaming apps may not bundle one (Roku screensaver docs [S]); Plex removed theirs (community thread [S]). The Channel Behavior Analysis tool checks whether an app "overrides or interferes with Roku's system screensaver" (Roku cert tests [S]). So the Archive Watch Roku screensaver feature (Party Play/screensaver under Surprise [R: SCRATCHPAD 0-NEW-2026-09-28 (a)]) is an in-app mode, not a system screensaver. The radio app's "now playing" screen should be gently animated art, with the screensaver suppressed only *while audio plays*.
- **Certification**: autoplay rule (since Oct 1 2024: when autoplay is disabled the app may not start playback until the user starts it) [S]; accessibility section 4.8 (comply with applicable laws, captions/audio description where legally required) [S, secondary]. A specific "audio app" or "now playing" certification rule was **not found** [UNVERIFIED]. Continue Watching participation is required from Oct 1 2026 only for apps over 1M hours a month outside the US store [S], so it does not apply.
- Roku's Search feed (Decision 113/117 [R]) is film/TV oriented; whether it ingests audio/radio series is **UNVERIFIED**.
- Roku has no background play: leaving the channel stops audio [K].
- Signing key: never regenerate, per CLAUDE.md [R]. A new channel gets its own key, backed up the same way.

---

## 5. Web (PWA at the site root, plus webOS/Tizen)

- **`<audio>`** plays archive.org MP3 directly. **MEASURED 2026-10-17** [V]: `GET https://archive.org/download/SUSPENSE/42-06-17_Burning_Court.mp3` with `Range: bytes=0-1023` and an `Origin` header returns `302` with `access-control-allow-origin: *` and `accept-ranges: bytes`. The storage node (`dn721805.ca.archive.org`) then answers `206`, `content-type: audio/mpeg`, `content-range: bytes 0-1023/7025865`, `access-control-allow-origin: *`, `access-control-allow-headers: ...Range...`, and `access-control-allow-credentials: true`, three times out of three. **This contradicts the repo's 2026-06-09 note** that `download/` nodes "range-serve without CORS" [R: docs/CATALOG-CONTRACT.md]: either archive.org changed, or MP3 and MP4 differ. Re-measure a film MP4 before amending that contract. Also seen once: a HEAD that followed the redirect got **HTTP 500** from the node, while GETs succeeded. Never probe with HEAD; the repo learned the same about GitHub Pages [R]. Consequences if the header holds: (a) `<audio crossorigin="anonymous">` works, so **Web Audio** (`MediaElementAudioSourceNode` → `GainNode` and EQ) becomes possible on the web, including gain boosts; (b) `fetch()` of whole files for offline works (below). Keep a fallback: if a node answers without the header, a `crossorigin` element **fails to play**. So play without `crossorigin` (volume-only gain) unless a per-session probe saw the header.
- **Media Session API**: `metadata`, action handlers `play`, `pause`, `seekbackward`/`seekforward` (details.seekOffset, default 10 s in MDN's example), `seekto`, `previoustrack`/`nexttrack`, and `setPositionState({duration, playbackRate, position})`. Position must be within [0, duration] and the rate nonzero. `setPositionState` is in Chrome/Edge 81+, Firefox 82+, Safari 15+ (MDN, caniuse [S]). Archive Watch already sets most of this up for video [R: watch.js ~3655].
- **iOS home-screen PWA background audio: not dependable.** Lock-screen playback stops working after about 30 s paused until the PWA is foregrounded again (Apple forums 762582, 2024 [S]); a paused backgrounded MediaSession cannot be resumed (WebKit 243258, 2022 [S]); playback stops when locked in standalone mode but continues from the Safari tab (Discourse thread [S]); WebKit 198277 was still open in 2020 [S]. No 2025/2026 fix was found [UNVERIFIED either way]. **Product consequence:** the website says, on iPhone, "for listening with the screen off, get the app" (a WARNING caption, which the "only essential information" rule allows [R: CLAUDE.md]). It is a fact the listener cannot discover by looking.
- **Offline**: Workbox's guide says runtime caching does not work for media, because playback fetches partial content. Precache with `cache.add()` or `warmStrategyCache`, and serve with CacheFirst plus `RangeRequestsPlugin`. Media elements "need `crossorigin`" for this, and files "can exceed storage quotas" (developer.chrome.com/docs/workbox/serving-cached-audio-and-video [S]). This was a blocker while archive.org sent no CORS, because the service worker would get an **opaque** response that cannot be range-sliced and is padded heavily against quota [K]. With the measured `access-control-allow-origin: *` [V, above], `cache.add(url)` should get a normal CORS response that RangeRequestsPlugin can slice. **Web offline listening is now plausible on desktop and Android Chrome** (about 7–29 MB per episode, measured sizes §8.0). Test it end to end (section 12) before promising it. iOS Safari's storage eviction and the PWA background limits above make it a weak feature on iPhone regardless.
- The archive.org `/metadata/{id}` API does send CORS [R], so a file list, durations and sizes are readable in the browser. Measured responses carry `server`, `dir`, and per-file `name`, `source` (original/derivative), `format`, `size` and `length` (seconds) [V].
- webOS/Tizen: the same web layer (`tv.js`), Chromium 85 floor on Tizen 2022+ (Decision 162 [R]). `navigator.mediaSession` support on these TVs is **UNVERIFIED**; media keys come through the existing key shims.

---

## 6. Voice speakers, Sonos, and side doors

### 6.1 Alexa skill (AudioPlayer interface)
- [V, Amazon docs fetched]: "You must host the audio file at an internet-accessible HTTPS endpoint on port 443. The web server must present a valid and trusted SSL certificate. Self-signed certificates aren't allowed". `audioItem.stream.url` is "a remote HTTPS location on port 443". The token is at most 1024 characters. `offsetInMilliseconds` resumes mid-episode. Events: `PlaybackNearlyFinished` (enqueue the next episode), `PlaybackFinished`, `PlaybackStopped`, `PlaybackFailed`. **`stream.captionData` takes WEBVTT** (the reference example shows a WEBVTT caption payload), so Echo Show devices can show the same transcript the pipeline makes. Formats AAC/MP4, MP3, PLS, M3U/M3U8, HLS; 16–384 kbps [S]. The measured 32 kbps and 128 kbps files fit. The `AudioPlayer.Play` directive needs `url` (HTTPS), `token` (≤1024 chars), optional `playBehavior` (REPLACE_ALL default, ENQUEUE); send it from an intent with `shouldEndSession: true` [S].
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

### 8.0 MEASURED 2026-10-17 [V]: one episode, two uploads

The same broadcast, *Suspense* "The Burning Court" (CBS, 1942-06-17), as two different archive.org uploads. ffmpeg 6.1.1 in this container (4 vCPU).

| | `SUSPENSE/42-06-17_Burning_Court.mp3` | `OTRR_Suspense_Singles/Suspense 420617 001 The Burning Court (128-44) 28455 30m00s.mp3` |
|---|---|---|
| archive.org `/metadata` says | format "64Kbps MP3", size 7,025,865, length 1756.46 | format "VBR MP3", source original, size 29,137,361, length 1800.44 |
| ffprobe says | mp3, **mono**, 44100 Hz, **32 kbps** (7,025,865 B × 8 / 1756.5 s = 32.0 kbps) | mp3, **mono**, 44100 Hz, 128 kbps, plus an embedded **MJPEG cover-art stream** |
| ID3 tags | none of note | `iTunNORM` present, `genre=OTR-Drama`, `date=1942`, `album=Suspense OTRR Set v2 ...`, `composer=Suspense_1942-06-17_The_Burning_Court_wCharlieRuggles UPGRADE` |
| Integrated loudness (loudnorm pass 1 / ebur128) | **-18.85 LUFS** / -18.8 | **-18.39 LUFS** / -18.4 |
| True peak | -2.59 dBTP | **-0.43 dBTP** |
| LRA | 9.6 LU | 7.6 LU |
| Time to measure 30 min | loudnorm 52.7 s; **ebur128 10.1 s**; decode only 7.4 s | loudnorm 55.1 s |
| Leading silence (−45 dB, ≥1 s) | none in the first 3 minutes | none detected at the start |
| Item `licenseurl` | `creativecommons.org/licenses/publicdomain/` | `creativecommons.org/licenses/by-nc-nd/3.0/` |

What this shows:
1. **archive.org's `format` label is not the bitrate.** "64Kbps MP3" was 32 kbps. Read the bitrate from ffprobe or compute it from size/length; never show the label.
2. **The same episode exists as several uploads with different quality**, so best-copy selection is needed (Decision 040 [R]). The OTRR copy has 4× the bitrate, cover art, and clean ID3 tags that carry the air date.
3. Both copies sit near -18.5 LUFS. A **-18 LUFS playback target** would leave these almost untouched. The 128 kbps copy's -0.43 dBTP peak leaves no room for a boost without a limiter. Measure 200 files before fixing the target (section 12).
4. Use **`ebur128`** for the CI measurement (about 3 min of audio per second of wall time here). `loudnorm` is about 5× slower because it upsamples internally [K] and is only needed to re-encode, which this app does not do.
5. **For the rights track:** the OTRR set's item carries a **CC BY-NC-ND** licenseurl on a 1942 broadcast. That is an uploader's claim over a collection, not evidence about the recording (the "uploader's word" class, Decision 140 [R]), and an NC/ND tag must not be read as "free". Hand this to research track 0x (rights).

### 8.1 What OTR files are like [K, measure in section 12]
Mostly MP3, **mono**, 32–128 kbps (many 64 kbps or below), 22.05–44.1 kHz, with transfers from transcription discs and tape: **hiss, crackle, hum, wow, clipped peaks, and level differences of 10 dB or more** between episodes of the same series. Many archive.org uploads ship several derivatives (the original plus archive.org's own VBR MP3 and Ogg derivatives) [K]. Pick one file per episode by a rule (original if MP3; else the VBR MP3 derivative), the same "best copy" logic as Decision 040 [R].

### 8.2 Loudness: measure, store, apply at playback
- Two-pass `loudnorm`: pass 1 `-af loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json -f null -` reports `input_i`, `input_tp`, `input_lra`, `input_thresh`, `target_offset`. A pass 2 would re-encode with `measured_*` values and `linear=true`, and loudnorm "will revert to dynamic normalization if the target loudness range is lower than the source, or if the target loudness produces a true peak above the limit" (secondary guides [S]). Common spoken-word target -16 LUFS, TP -1.5, LRA 11; ffmpeg-normalize defaults to -23 LUFS (EBU R128 broadcast) (slhck.info [S]).
- **Only the measurement is used, and `ebur128=peak=true` is the faster way to get it** (§8.0: 10 s vs 53 s per 30-minute file). Store `loudness: {i, tp, lra, measuredAt, tool}`; the client computes `gainDb = target - i`, then clamps so `tp + gainDb ≤ -1`. This keeps archive.org's file as the stream (§2.1), costs one decode per file in CI (≈ 10 s wall per 30-minute mono MP3 with ebur128, measured §8.0; about 2 runner-hours per 1,000 episodes plus download time), and lets the target change without rerunning.
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
| Downloads / offline | Y (Decision 099) | Y | N (Decision 099) | Y | via phone | Y | via phone | P | P | N | N | N | P (CORS now sent [V]; test SW caching) | weak (eviction) | N | N |
| Voice play | Siri/App Intents | Siri | Siri | Siri | Siri | Assistant [S] | Assistant [S] | Assistant | ? | Assistant | Alexa? | Roku voice ? | N | N | Y (skill) | Sonos voice ? |
| Listen together | SharePlay [S] | SharePlay | SharePlay | N | N | rooms (Worker) [R] | N | N | N | rooms join [R] | rooms join [R] | ? | rooms join [R] | rooms join | N | N |
| Cast / AirPlay out | AirPlay 2 | AirPlay 2 | (is a receiver) | N | n/a | Cast (google flavor) [S] | n/a | n/a | output picker [S] | (is a receiver) | N | N | Remote Playback API ? | AirPlay | n/a | n/a |
| Runtime loudness gain | Y (cut; boost via tap) | Y | Y | Y | Y | Y (LoudnessEnhancer) | Y | Y | Y | Y | Y | ? volume field | Y via Web Audio if CORS holds [V], else cut only | P | N | N |
| Runtime EQ | P (tap/engine) | P | P | N | via phone | P (AudioProcessor) | via phone | P | N | P | P | N | P (Web Audio, CORS [V]) | P | N | N |
| On-device transcript | iOS 26+ SpeechAnalyzer [S] | macOS 26+ | ? | N | N | N (live-mic API only [S]) | N | N | N | N | N | N | N | N | N | N |
| Widget / home surface | Y (App Intents [S]) | Y | Top Shelf | complication | CarPlay widgets iOS 26 [S] | Glance widget | n/a | n/a | tile | Continue row ? | ? | N | N | N | N | N |
| Review gate | App Review + CarPlay entitlement [V] | App Review | App Review | App Review | entitlement + CarPlay guide [V] | Play | Play manual car review, holds updates [V] | same + AAOS screenshots [V] | Play Wear review | Play TV review (TV-NP [V]) | Amazon | Roku cert [S] | none | none | Alexa cert | Sonos validation [S] |
| Transcript on screen | Y | Y | Y | small | **N ("never show song lyrics") [V]** | Y | **N (ST-1 no auto-scroll) [V]** | N | N | Y | Y | Y | Y | Y | Echo Show captionData WEBVTT [V] | N |

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
- [ ] CarPlay: tab bar of at most 4 tabs, every list useful at 12 rows, depth of 5 or less, `CPNowPlayingTemplate` populated at all times, Up Next as a list pushed on it, no transcripts [V]
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
- [ ] `automotive_app_desc.xml` `<uses name="media"/>`; root tabs; content-style hints; artwork URIs
- [ ] Voice: Gemini and Assistant play-from-search (VC-1) [V]; no autoplay at start (MA-1) [V]; launch and load in 10 s or less (DR-2/3) [V]; state restored on relaunch (EP-2) [V]; no "new episode" notifications (IN-1) [V]
- [ ] Prototype on a non-production track: car review holds every update until approved [V]

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
- **5.2.3** [V, guidelines dated October 16, 2026]: "Audio/Video Downloading: Apps should not facilitate illegal file sharing or include the ability to save, convert, or download media from third-party sources (such as Apple Music, YouTube, SoundCloud, Vimeo, etc.) without explicit authorization from those sources. Streaming of audio/video content may also violate Terms of Use, so be sure to check before your app accesses those services. Authorization must be provided upon request." Other apps passing "is never an argument" (forum moderator [S]); Movist was pulled in 2019 over "downloading 3rd party media" (mjtsai.com [S]). Archive Watch was rejected under 5.2.3 on build 1.0 (36), 2026-06-16, and answered with a paste-ready reply plus a rights-evidence PDF [R: docs/app-store-review-5.2.3-response.md]. **Radio-specific changes to that answer:** (a) the app *does* download (offline episodes), so say plainly that downloads are of public-domain works from archive.org's public endpoints, stored in the app sandbox, never exported as files; (b) OTR rights are messier than film (unpublished broadcasts, transcription discs, scripts and music under separate copyright, and the 1972 sound-recording rule for US pre-1972 recordings under the Music Modernization Act's Classics Protection, which put pre-1923 recordings into the public domain on 2022-01-01 and later recordings on a rolling schedule [K, UNVERIFIED here; the rights track must confirm]); the PDF needs its own radio methodology from the rights research track; (c) never offer "save to Files" / share the MP3.
- **4.2 Minimum Functionality** [V]: "Your app should include features, content, and UI that elevate it beyond a repackaged website. If your app is not particularly useful, unique, or 'app-like,' it doesn't belong on the App Store. If your App doesn't provide some sort of lasting entertainment value or adequate utility, it may not be accepted." **4.2.2**: "Other than catalogs, apps shouldn't primarily be marketing materials, advertisements, web clippings, content aggregators, or a collection of links." Rejections cite "usefulness limited by the minimal amount of content or features" [S]. Describe the app in review notes as a **catalog** (the 4.2.2 exception) with native depth: downloads, CarPlay, Siri, sleep timer, SharePlay, transcripts, loudness leveling. Do not ship v1 as a thin list player. **4.2.3(ii)**: if the app must download resources at first launch, "disclose the size of the download and prompt users" [V]. Archive Watch's catalog DB download is the precedent to check.
- **4.3 Spam** [V]: "(a) Don't create multiple Bundle IDs of the same app ... (b) Don't submit apps that are indistinguishable from what's already widely available." A second app from the Archive Watch developer, built on the same template, is the case (a) describes. The answer is a different product (audio-first, episodic, car), different content (radio, not film), and saying so in the review notes. The owner could also ask whether radio belongs **inside** Archive Watch instead. That is an owner decision this research does not make, and it is the one 4.3(a) poses.
- **2.5.4** [V]: "Multitasking apps may only use background services for their intended purposes: VoIP, audio playback, location, ..." Only hold the `audio` background mode while actually playing.
- **CarPlay**: the entitlement is reviewed against "predefined criteria" and the CarPlay Developer Guide's rules apply [V] (no lyrics, templates for their intended types, primarily audio playback). The Review Guidelines introduction lists "CarPlay Audio" among the limited-use entitlements [V].
- **Metadata**: the App Store listing must not claim "all public domain" more strongly than the evidence (the same rights posture as 5.2.3).

**Google Play**
- Car apps get "an additional manual review", and **updates for every device wait until the car review approves** [V]. Wear and TV form factors each have their own review [K]. TV-NP requires the Now Playing card for background audio [V].
- Foreground service type declaration (`mediaPlayback`) is checked on Android 14+ targets [K].
- Play's "Repetitive content" and "Minimum functionality" policies mirror Apple's 4.2/4.3 [K, UNVERIFIED].
- Play automatic protection needs minSdk 24 (Decision 165 [R]).

**Roku**
- Channel Behavior Analysis flags apps that override or interfere with the system screensaver [S]; a bundled screensaver is not allowed [S]; the autoplay rule [S]. An audio channel that leaves the screen frozen for a long time may fail on design review [K, UNVERIFIED]; animate the now-playing art gently.

**Amazon / Alexa**
- Alexa: HTTPS 443, trusted certs, `shouldEndSession` [S]; skill certification tests that pause, resume, next and previous are handled (`AudioPlayer.PlaybackNearlyFinished` for the queue) [K].

---

## 12. To measure (probes for a session with network access)

Done this session [V]: the Range, CORS and redirect probe on one 32 kbps MP3 (§5); ffprobe and loudness on two files (§8.0); the guideline text for 4.2, 4.3, 5.2.3 and 2.5.4; the CarPlay guide's audio rules; Android car and TV media criteria; the Roku Video and Audio node screensaver fields; Alexa's URL rules. Still to do: everything below, starting with the 200-file loudness distribution and a re-check of the MP4 CORS claim in CATALOG-CONTRACT.

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

- **Web offline**: in Chrome and Safari, from a page on archivewatch.org, `caches.open('t').then(c=>c.add(url))` (CORS mode) against an archive.org MP3, then play it offline through a Workbox RangeRequestsPlugin route with `<audio crossorigin="anonymous">`. Expect success now that `access-control-allow-origin: *` is sent [V]; record `navigator.storage.estimate()`. Repeat across 20 items on different storage nodes to confirm every node sends the header.
- **Film MP4 CORS** (to settle the contradiction with docs/CATALOG-CONTRACT.md): the same `curl -D - -r 0-1023 -H "Origin: https://archivewatch.org"` against a feature film's MP4 node URL.
- **iOS PWA background**: on iPhone 15 Pro (iOS 27.2) and iPhone 12 (26.6.1) [R: device list in Decision 155], install a test PWA, play, lock, wait 5/30/120 s paused, resume from Lock Screen. Record each.
- **Roku screensaver**: on a real Roku, play an MP3 with (a) an Audio node, (b) an Audio node with `disableScreenSaver`, (c) a hidden Video node with `disableScreenSaver=true`; set the system screensaver to 1 minute; record which keeps playing and what the debug console prints.
- **Alexa redirect**: a test skill `AudioPlayer.Play` with an `archive.org/download/...` URL (302) vs the resolved node URL.
- **Siri on HomePod**: "Play Suspense on <app>" with (a) App Intents only, (b) with an INPlayMediaIntent handler.
- **Android TV session**: read the current TV quality guidelines' audio-app items (TV-NP and the Now Playing card) and run the session ON on the Google TV dongle.
- **Retrieve and quote**: Android app quality for cars (media MUSTs); CarPlay App Programming Guide PDF (audio section); App Store Review Guidelines 4.2, 4.3 and 5.2.3 current text; WWDC26 312's OS minimum; Fire TV audio app guidance; Sonos partner terms for a free service; Podcast namespace `transcript`/`chapters` spec.

---

## Sources

Fetched and read in full on 2026-10-17 [V]
- https://developer.apple.com/app-store/review/guidelines/ ("Last Updated: October 16, 2026")
- https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements.md
- https://developer.apple.com/carplay/documentation/CarPlay-App-Programming-Guide.pdf (title "CarPlay Developer Guide", October 2026)
- https://developer.apple.com/carplay/
- https://developer.android.com/docs/quality-guidelines/car-app-quality
- https://developer.android.com/docs/quality-guidelines/tv-app-quality (last updated 2026-06-29)
- https://developer.roku.com/docs/references/scenegraph/media-playback-nodes/video.md
- https://developer.roku.com/docs/references/scenegraph/media-playback-nodes/audio.md
- https://developer.amazon.com/en-US/docs/alexa/custom-skills/audioplayer-interface-reference.html
- https://developer.amazon.com/en-US/docs/alexa/custom-skills/use-long-form-audio.html
- Measured: https://archive.org/metadata/SUSPENSE, https://archive.org/metadata/OTRR_Suspense_Singles, https://archive.org/metadata/OTRR_Dimension_X_Singles; https://archive.org/download/SUSPENSE/42-06-17_Burning_Court.mp3; the OTRR_Suspense_Singles file "Suspense 420617 001 The Burning Court (128-44) 28455 30m00s.mp3"

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
