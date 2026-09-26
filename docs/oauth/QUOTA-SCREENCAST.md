# YouTube API quota screencast — shot by shot (2026-09-26)

The YouTube API Services team, 2026-09-25, on the quota-extension thread
("YouTube API Services: Thank you for your submission"), within seven business
days:

> Kindly provide a detailed step-by-step screencast (English version)
> demonstrating how the application uses YouTube Data API Services on behalf of
> signed-in users to **create and manage live watch-along broadcasts of
> public-domain films**, **update video thumbnails**, **monitor concurrent
> viewers**, and **interact with live chat**, along with **the end result**.

OAuth for `…/auth/youtube` was approved the next morning (project
895559137709), so the consent screen is now the verified one — no
unverified-app interstitial to explain.

Every section opens with an English title card that names the YouTube Data API
calls it shows and when the app makes them. The app's window and the browser
window are recorded separately, window-only (`tools/demo_window_record.swift`),
never the whole screen. **Not filmed:** the Google account chooser (it lists
family addresses), notifications, any other window.

| # | Their ask | Shot | API calls on the card |
|---|---|---|---|
| 1 | — | Title card: what Archive Watch is; project number; "every call is made on behalf of the signed-in host, on the host's own channel". | — |
| 2 | public-domain films | Archive Watch → *Safety Last!* (1923), its Detail, the rights line. Card: only films published 1930 or earlier can be broadcast; the app refuses others and says why. | none |
| 3 | create | Watch Together Studio: "Use this film"; FILM and STREAM panes; Start the preview (nothing is sent — the app makes no API call yet). | none |
| 4 | signed-in users | Output → YouTube → Sign in. Apple's prompt, Google's consent screen (verified, "Manage your YouTube account" readable), Continue. The Output column names the channel. | `channels.list mine=true`; `liveBroadcasts.list mine=true` (is live streaming enabled?) |
| 5 | create | Type the stream title, Unlisted, **Go Live**. STREAM reads LIVE. | `liveStreams.insert`, `liveBroadcasts.insert` (enableAutoStart), `liveBroadcasts.bind` |
| 6 | end result (source account) | Browser: YouTube Studio → Content → Live — the new broadcast, the title typed in the app, Unlisted, "Live now". | — |
| 7 | update thumbnails | ~10 s after going live the app sets the thumbnail to a still of the show; YouTube Studio's row shows it. | `thumbnails.set` (once per show) |
| 8 | monitor concurrent viewers | A viewer opens the broadcast link (a phone); the Studio's AUDIENCE header reads "1 watching". | `videos.list part=liveStreamingDetails` — once every 60 s |
| 9 | interact with live chat (read) | The host turns on "Read chat"; the viewer types in YouTube's chat; the message arrives in the AUDIENCE pane (and, if shown, on the broadcast). | `liveChatMessages.list` — every 10 s, only while the host has it on; stops on `quotaExceeded` |
| 10 | interact with live chat (write) | The host presses "Share the film in chat"; the film's title and its Internet Archive link appear in YouTube's own chat. The app never posts on its own. | `liveChatMessages.insert` (one, host-pressed) |
| 11 | manage → end | "End the broadcast". | `liveBroadcasts.transition broadcastStatus=complete` (a show that never went live is `liveBroadcasts.delete`d instead) |
| 12 | end result | YouTube Studio: "Streamed"; the finished broadcast plays on YouTube as an unlisted video with the show's thumbnail. | — |
| 13 | quota | Card: what one show costs (≈375 units without chat, ≈4,000 with chat read every 10 s), shared by every host; the stream-key route that uses no API; `quotaExceeded` stops reading rather than retrying. Sign out → token revoked. | `oauth2.googleapis.com/revoke` |

Delivered as one video (title cards + the two windows cut together), uploaded
**unlisted**, and linked in a reply on the same thread.

## Delivered 2026-09-26

<https://youtu.be/6QiRJhHyw3E> (unlisted, 4:49), broadcast `ah780Fm7ky8` on
Archive Watch, answered on the thread the same day. Shots 4's consent screen
and 13's sign-out were NOT filmed: consent was already granted and verified,
and re-granting passes through the account chooser. Both are covered on cards.

**Recording traps, for the next time:**
- replayd serves ONE ScreenCaptureKit stream reliably; two at once kill both
  ("application connection being interrupted"). Record the app with
  `demo_window_record.swift` and the browser with a `screencapture -l <window>`
  still loop.
- A macOS alert (End the broadcast?) is its own window and is not in the app
  window's recording.
- The Studio's film search reacts to keystrokes, not to an AX value set.
- A new show over a released or paused film broadcasts black: re-choose the film
  and confirm the Film input reads fps before Go Live.
- The Chrome tab driven by the browser tools shows a "started debugging this
  browser" banner in every window of that profile. Crop it.
