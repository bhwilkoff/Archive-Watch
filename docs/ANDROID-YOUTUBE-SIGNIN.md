# YouTube sign-in on Android — the plan, for after the quota increase

Owner, 2026-09-29: *"Please document the sign in for after we get the API limit
increased."* Nothing here is to be started until Google's YouTube API quota
review (docs/oauth/QUOTA-SCREENCAST.md, window closing ~2026-10-06) has closed.

Until then Android hosts reach YouTube with **their own stream key** (go-live
dialog → Stream key → YouTube, v1.42.965), which calls no API and spends no
quota (Decision 136).

## Why Android has no YouTube sign-in today

- Apple signs in with an **iOS**-type OAuth client in the **Archive Watch**
  Google Cloud project (the project whose `…/auth/youtube` scope passed
  verification on 2026-09-26 and whose quota the review is about). Google binds
  a client to its platform and refuses the iOS client from Android (measured,
  WATCH-TOGETHER §9.www).
- Android therefore needs an **Android**-type client: package name + the SHA-1
  of the key that signs the installed app.
- The television reason recorded in `StudioPlatformAuth.kt` (a TV needs Google's
  device grant and a client *secret*) no longer applies: Watch Together on
  Android is phone-only since Decision 132.

## The one decision to make first: which Google Cloud project

Android's package + SHA-1 pairs are **already registered** — as the Drive-sync
clients in the project **`archivewatch-play`** (docs/google-oauth-setup.md):

| Build | Package | SHA-1 |
|---|---|---|
| Play (app signing key) | `com.archivewatch.app` | `CB:4B:ED:31:3B:06:79:44:03:4E:03:B0:88:BB:1B:40:22:C5:8E:97` |
| Local release (upload key) | `com.archivewatch.app` | `8B:3E:FF:3E:05:8B:60:54:84:19:E0:0F:F4:7A:85:42:83:54:63:AD` |
| Debug | `com.archivewatch.app.debug` | `B2:0D:E1:7E:31:C1:6D:33:E0:30:8B:2F:9D:97:A8:C3:D2:C5:A7:43` |

Google allows a given package + SHA-1 in **one** project. YouTube's verified
scope and quota are in **Archive Watch**. So one of these has to be true:

- **A (recommended). Add the YouTube scope to `archivewatch-play`.** Sync keeps
  working untouched. But that project's consent screen then requests a
  SENSITIVE scope, so it needs its own verification (demo video, justification —
  the same package as last time, docs/oauth/) and its own YouTube quota. Android
  hosts would draw on a separate 10,000 units, which is arguably a benefit.
- **B. Move the Android clients to Archive Watch.** Delete them from
  `archivewatch-play`, re-create them in Archive Watch, and add `drive.appdata`
  there. One project, one quota — but Drive sync breaks for every Android user
  until an update ships, and the web client (also in `archivewatch-play`) would
  need moving too or sync splits across projects. Not recommended.

Either way, Google's verification rule is that the demo video show the consent
flow for **every OAuth client on the project**, so adding a client after
verification can mean a new video. Do it once, after the quota review.

## Owner steps (Google Cloud console, benwilkoff@gmail.com)

For option A, in project `archivewatch-play`:

1. APIs & Services → Library → enable **YouTube Data API v3**.
2. Google Auth Platform → Data Access → add `…/auth/youtube` with the same
   written justification used in the Archive Watch project.
3. Submit verification (branding is already verified for this project's
   domain; the demo video must show the Android consent on a phone).
4. The existing three Android clients need no change.

## Code steps (after the owner steps)

1. **Sign-in**: Google Identity Services' `AuthorizationClient`
   (`Identity.getAuthorizationClient(context).authorize(...)` with the
   `…/auth/youtube` scope) — the native Android API, google flavor only, the
   same library Drive sync already uses. No redirect URI, no secret, no
   refresh token to store: `authorize` returns a fresh access token silently
   once granted.
2. **`YouTubeLive.kt`**: a port of the Swift go-live calls in
   `StudioPlatforms.swift` — `liveBroadcasts.insert`, `liveStreams.insert`
   (`part=snippet,cdn,status,contentDetails` — the `part` must name every
   property the body sets, the defect that blocked the first YouTube go-live),
   `liveBroadcasts.bind`, and the `liveStreamingNotEnabled` pre-check. Price
   every call next to it (Decision 136); never retry a `quotaExceeded`.
3. **Go-live dialog**: a YouTube sign-in beside Twitch's, and the channel
   chooser prompt (`prompt=select_account` equivalent) so a Brand Account can
   be picked — the Apple lesson of 2026-09-18.
4. **PARITY**: the platform sign-in and "with the world" rows.
5. Prove it on the Pixel against a real channel, read back from YouTube's own
   `liveBroadcasts` count, as the iPhone run was (SCRATCHPAD 7-DONE).

## Not before

- The quota review closes (~2026-10-06).
- The Android version now in Play review is approved (owner, 2026-09-29: no
  new Android version until the current one is approved).
