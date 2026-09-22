# OAuth verification — the reply to Google, item by item

Google's mail of **2026-09-22**, *"[Action Needed] OAuth Verification Request
Acknowledgement"*, project `895559137709` (`archive-watch`), named four
things. This file holds the reply and the state of each.

Google requires the reply **on that thread** — *"you must reply to this email
after fixing the highlighted issues to continue"* — so it is the owner's to
send from benwilkoff@gmail.com.

| # | What Google asked | State |
|---|---|---|
| 1 | Demo video: the **OAuth workflow**, consent screen with scopes **fully expanded and readable** | ⏳ see "The consent screen" below |
| 2 | Demo video: **full operational functionality** of `…/auth/youtube`, with **the change reflected in the source account** | ✅ recorded |
| 3 | **Test credentials** + step-by-step navigation | ✅ drafted — the app has no login of its own |
| 4 | Privacy policy specifying **data protection mechanisms for sensitive data** | ✅ published |

## The consent screen — what we learned, and why it matters to the reviewer

The first video was rejected because the consent screen read *"Archive Watch
already has some access"* instead of naming the scope. The cause was NOT a
missing revoke, which is what we assumed for two days. It is this:

**A YouTube Brand Account holds its own OAuth grant, and Google exposes no way
to revoke it.**

Measured 2026-09-22:

- Every Archive Watch entry was deleted from the owning account's Linked apps
  — both the "Access to" and "Sign in with Google" categories — and verified
  absent (search returns "No results found"). The Brand Account's consent
  screen **still** collapsed.
- `myaccount.google.com/u/N/b/<brandID>/connections` authenticates as the
  brand (the avatar switches) and then fails to render. `/permissions`
  silently redirects to the owning account's list.
- The proof it is per-brand: signing in to a DIFFERENT brand account with no
  prior grant showed the scope in full — *"When you allow this access, Archive
  Watch will be able to: **Manage your YouTube account**"* — same app, same
  client id, same owning account. The only variable was which brand.

So the only handle on a brand grant is the **token itself**:
`https://oauth2.googleapis.com/revoke`. `StudioPlatforms.signOut` now calls it
(it previously cleared only the local Keychain), which is both the fix for
this and a real privacy improvement — signing out used to leave the app
authorized on the user's account indefinitely.

## Draft reply — for the owner to send on Google's thread

> Thank you for the review. I have addressed each item.
>
> **1 & 2. Demo video — the OAuth workflow and the full functionality of the
> scope**
>
> [VIDEO URL]
>
> The video shows the complete flow in one take: the application with a
> public-domain film loaded and a local preview running that is explicitly not
> being sent anywhere; the sign-in; the system prompt; the account and channel
> selection; Google's unverified-app screen, which I have left in because it
> is expected at this stage; the consent screen; and then the full operational
> use of `https://www.googleapis.com/auth/youtube`, which is the only Google
> scope the application requests:
>
> - reading the signed-in channel, so the host can see which channel they are
>   about to broadcast to, and checking that live streaming is enabled on it
> - creating a live stream and a live broadcast with the title and privacy
>   setting the host chose
> - binding them and transitioning the broadcast to live
> - reading that broadcast's live chat, so the audience's messages can be
>   shown on screen during the presentation — the application never posts a
>   chat message
> - transitioning the broadcast to complete when the host ends the show
>
> **Source account impact**: after going live, the video shows YouTube Studio
> on the same account, under Content → Live, with the newly created broadcast
> in the list — the title typed in the app, Type "Streaming software",
> Visibility "Unlisted", status "Live now".
>
> **Why no narrower scope is possible**: there is no Google permission that
> lets an application create and start a live broadcast without
> `…/auth/youtube`. `youtube.readonly` cannot write, and `youtube.upload`
> covers uploaded videos rather than live events. The application never reads
> the user's existing videos, never uploads, never edits or deletes channel
> content, and never touches subscriptions, playlists or comments.
>
> **3. Privacy policy**
>
> <https://archivewatch.org/privacy.html> now specifies the data protection
> mechanisms for this scope: OAuth 2.0 authorization-code flow with PKCE in a
> system browser session the application cannot read; tokens stored only in
> the device Keychain under
> `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, encrypted at rest and
> never synchronized to iCloud or copied to another device; no Archive Watch
> server exists that could receive them; stream keys held in memory for the
> session only and never written to disk, displayed or logged; no analytics,
> crash reporting or telemetry of any kind on any platform; and video
> published directly from the user's device to YouTube over RTMPS. It states
> revocation and deletion, and an explicit Limited Use commitment including
> that Google user data is never used to develop, improve or train any
> generalized or non-personalized AI or machine learning model.
>
> Signing out of the application now also calls
> `https://oauth2.googleapis.com/revoke`, so a user withdrawing consent in the
> app withdraws it at Google as well, rather than only locally.
>
> **4. Test credentials and navigation**
>
> Archive Watch has no accounts and no login of its own. It is a free,
> non-commercial application for watching public-domain films from the
> Internet Archive, with no advertising and no user records, so there is no
> test credential to issue and no authentication blocker to remove. The
> reviewer signs in with their own Google account, which is the only
> credential the integration uses.
>
> The application is publicly available on the App Store for macOS, iPhone,
> iPad and Apple TV:
> <https://apps.apple.com/us/app/archive-watch/id6776697407>
>
> Step by step, on a Mac:
>
> 1. Install Archive Watch from the link above and open it. No sign-in is
>    required or offered in order to browse or watch.
> 2. Search for a pre-1930 film — for example *Safety Last!* (1923) — and open
>    it. Only films published before 1930 may be broadcast, which the
>    application enforces and explains on screen.
> 3. Press Play, then choose **Broadcast → Watch Together Studio**
>    (Shift-Command-S).
> 4. Optionally press **Start preview**. This produces the full program
>    locally and sends it nowhere; the status reads "NOT SENDING — the show is
>    being made but not sent anywhere". No Google API call is made at this
>    stage.
> 5. In the **Output** column, choose platform **YouTube** and press
>    **Sign in**. This is the consent flow shown in the video.
> 6. After consent, the Output column names the channel you signed in to.
> 7. Type a stream title, leave privacy as **Unlisted**, and press **Go Live**.
>    The broadcast appears on that channel.
> 8. Press **End the broadcast** to finish.
>
> Live streaming must already be enabled on the reviewer's channel
> (youtube.com/features). The application checks this before enabling Go Live
> and says so if it is not; YouTube's first activation of that setting can
> take up to 24 hours.
>
> Please let me know if anything further would help.

## Before sending

- [ ] Record the take (see `tools/oauth_demo_record.sh`)
- [ ] Watch it back: is the scope legible on the consent screen?
- [ ] Upload unlisted to YouTube; paste the URL over `[VIDEO URL]`
- [ ] Update the privacy-policy link in the Cloud Console submission and
      resubmit there — Google asked for both the reply and the Console
- [ ] Reply on Google's own thread; replying is what restarts the review
