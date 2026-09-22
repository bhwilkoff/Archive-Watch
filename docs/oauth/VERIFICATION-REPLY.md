# OAuth verification — what Google asked for, and the reply

Google's mail of **2026-09-22**, *"[Action Needed] OAuth Verification Request
Acknowledgement"*, project `895559137709` (`archive-watch`), rejected the first
demo video and named four things. This file tracks each to done, and holds the
reply to send once the video exists.

Google requires the reply to come **on that thread** — "you must reply to this
email after fixing the highlighted issues to continue" — so it is the owner's
to send from benwilkoff@gmail.com.

## The four items

| # | What Google asked | State |
|---|---|---|
| 1 | A demo video showing the **OAuth workflow**, consent screen with the scope **fully expanded and readable** | ⏳ `tools/oauth_demo_record.sh` — beats + pre-flight checks written; needs recording |
| 2 | A demo video showing the **full operational functionality** of `…/auth/youtube`, including **the change reflected in the source account** | ⏳ same recording, beats 5–11 |
| 3 | **Test credentials** and step-by-step navigation instructions | ✅ drafted below — the app has no login of its own |
| 4 | A privacy policy specifying **data protection mechanisms for sensitive data** | ✅ published 2026-09-22 |

## Why the first video was rejected, in its own words

> The demo video you provided does not sufficiently demonstrate why the
> following scope(s) are necessary or why narrower permissions cannot be used.

The first video showed a host signing in and going live. It never showed
**what the scope is for** step by step, it never showed **the broadcast
appearing in the YouTube account**, and its consent screen had collapsed the
scope into *"Archive Watch already has some access"* — because that brand
account had granted it before. That last one was written down as a caveat
beside the file on 2026-09-21 and shipped anyway.

**The fix for it is a revoke, and it must happen before the camera rolls**:
myaccount.google.com/permissions → Archive Watch → Remove access. The
recording script asks about this and refuses to start until it is confirmed,
because it is the one defect that cannot be repaired in an edit.

## Item 4 — the privacy policy (done)

<https://archivewatch.org/privacy.html> now carries, under *Watch Together
Studio*: what the permission is used for operation by operation; why no
narrower scope exists (`youtube.readonly` cannot write, `youtube.upload` is
for uploaded videos and cannot start a live event); the Keychain protection
class the token is held under
(`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — encrypted at rest, never
synchronised to iCloud, never copied off the device); that we operate no
server that could receive it; that stream keys are never stored, shown or
logged; revocation and deletion; and an explicit **Limited Use** statement
including that the data is never used to train any AI or ML model.

## Item 3 — the reply's answer on test credentials

Archive Watch has **no accounts and no login of its own** (it is free, with no
advertising and no user records — that is a design decision, not an omission).
So there is nothing for us to issue. A reviewer installs the app from the
public App Store listing and signs in with **their own** Google account, which
is the only credential the integration ever uses.

---

## Draft reply — for the owner to send on Google's thread

> Thank you for the review. I have addressed all three items.
>
> **1. Demo video — OAuth workflow and full functionality**
>
> [VIDEO URL]
>
> The video shows the complete consent flow with the requested scope expanded
> and legible. I revoked the application's prior access before recording, so
> the permission is presented in full rather than collapsed as "already has
> some access", which is why it was not readable in my first submission.
>
> It then demonstrates the full operational use of
> `https://www.googleapis.com/auth/youtube`, which is the only Google scope
> the application requests:
>
> - reading the signed-in channel, so the host can see which channel they are
>   about to broadcast to, and checking that live streaming is enabled on it
> - creating a live stream and a live broadcast with the title and privacy
>   setting the host chose
> - binding them and transitioning the broadcast to live
> - reading that broadcast's live chat, so the audience's messages can be
>   shown on screen during the presentation (the app never posts a message)
> - transitioning the broadcast to complete when the host ends the show
>
> **Source account impact**: after going live, the video shows YouTube Studio
> (Content → Live) on the same account with the newly created broadcast in the
> list under the title typed in the app, and then shows it no longer live after
> the host presses End in the app.
>
> **Why no narrower scope**: there is no Google permission that allows an
> application to create and start a live broadcast without
> `…/auth/youtube`. `youtube.readonly` cannot write, and `youtube.upload`
> covers uploaded videos rather than live events. The application never reads
> the user's existing videos, never uploads, never edits or deletes any
> channel content, and never touches subscriptions, playlists or comments.
>
> **2. Privacy policy**
>
> <https://archivewatch.org/privacy.html> has been updated and now specifies
> the data protection mechanisms for this sensitive scope: OAuth 2.0
> authorization-code flow with PKCE in a system browser session the app cannot
> read; tokens stored only in the device Keychain under
> `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, encrypted at rest and
> never synchronised to iCloud or copied to another device; no Archive Watch
> server exists that could receive them, and none does; stream keys held in
> memory for the session only and never written to disk, displayed or logged;
> no analytics, crash reporting or telemetry of any kind on any platform; video
> published directly from the user's device to YouTube over RTMPS. It also
> states revocation and deletion, and an explicit Limited Use commitment
> including that Google user data is never used to train any generalized or
> non-personalized AI or ML model.
>
> **3. Test credentials and navigation**
>
> Archive Watch has no accounts and no login of its own — it is a free,
> non-commercial app for watching public-domain films from the Internet
> Archive, with no advertising and no user records. There is therefore no test
> credential to issue and no authentication blocker to remove: the reviewer
> signs in with their own Google account, which is the only credential the
> integration uses.
>
> The application is publicly available on the App Store for macOS, iPhone,
> iPad and Apple TV:
> <https://apps.apple.com/us/app/archive-watch/id6776697407>
>
> Step by step, on a Mac:
>
> 1. Install Archive Watch from the link above and open it. No sign-in is
>    required or offered to browse or watch.
> 2. Search for a pre-1930 film — for example *Safety Last!* (1923) — and open
>    its page. Only films published before 1930 may be broadcast, which the app
>    enforces and explains on screen.
> 3. Press Play, then choose **Broadcast → Watch Together Studio**
>    (Shift-Command-S).
> 4. In the **Output** column, choose platform **YouTube** and press
>    **Sign in**. This is the consent flow in the video.
> 5. After consent, the Output column names the channel you signed in to.
> 6. Type a stream title, leave privacy as **Unlisted**, and press **Go Live**.
>    The broadcast appears on that channel.
> 7. Press **End the broadcast** to finish; the broadcast is transitioned to
>    complete on YouTube.
>
> Live streaming must be enabled on the reviewer's channel beforehand
> (youtube.com/features); the app checks this and says so before enabling
> Go Live, but YouTube's first activation can take up to 24 hours.
>
> Please let me know if anything further would help.

## Before sending

- [ ] Revoke Archive Watch at myaccount.google.com/permissions on the account
      you will record with (**benwilkoff@gmail.com** — the live-enabled
      channels are there, not on ben@learningischange.com)
- [ ] `bash tools/oauth_demo_record.sh` and record
- [ ] Watch it back: is the scope legible on the consent screen? Is the
      broadcast visible in YouTube Studio?
- [ ] Upload unlisted to YouTube, paste the URL in place of `[VIDEO URL]`
- [ ] Confirm the Cloud Console submission still names exactly
      `https://www.googleapis.com/auth/youtube` and resubmit there too —
      Google asked for the privacy-policy link to be updated **in the Console**
      as well as in the reply
- [ ] Reply on Google's own thread (replying is what restarts the review)
