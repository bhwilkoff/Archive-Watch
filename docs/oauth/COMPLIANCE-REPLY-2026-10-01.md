# Reply to the YouTube API Services compliance review — ToS Violations Report V.1 (2026-10-01)

Send as a reply in the existing thread ("Re: YouTube API Services: Thank you for
your submission", from youtube-disputes+2f0xs4f1bp7bh1n@google.com), from
Gmail's web page — never through the Gmail connector, which wraps every link in
an expiring google.com/url redirect (memory gmail_connector_wraps_links).

---

Hello,

Thank you for the review and for the clear report. Below is each item in the ToS
Violations Report V.1 for project 895559137709, with how it has been resolved.

**1. Policy III.D.1c — project numbers (confirmation)**

Archive Watch uses two Google Cloud projects with the YouTube Data API. My earlier
form said one; that was wrong, and I am sorry for the error.

- **895559137709** (project ID `archive-watch`) — the Archive Watch apps' OAuth
  client. This is the API Client under review: a host signs in with their own
  Google account in Watch Together Studio to broadcast a public-domain film, with
  their camera and microphone, to their own YouTube channel. All end-user YouTube
  API traffic goes through this project.
- **294492189901** (project ID `archivewatch-play`) — Archive Watch's own server
  automation, which uploads short public-domain film clips to Archive Watch's own
  YouTube channel (`videos.insert` only, scope `youtube.upload`, about two uploads
  a day, authorized by our own account). It involves no end user and no end-user
  data. If you would like it reviewed separately, or consolidated into
  895559137709, we will do whichever you prefer.

**2. Policy III.A.2a — privacy policy**

Archive Watch's privacy policy is at https://archivewatch.org/privacy.html. It is
published by Learning is Change, Inc., the API Client's owner, and now says so in
its first lines. It is linked:

- on the OAuth consent screen (Application privacy policy link; branding verified);
- on the home page of https://archivewatch.org (beside the Terms of Use);
- from the Help menu of the Mac, iPhone and iPad apps ("Privacy Policy");
- and now directly at the YouTube sign-in in Watch Together Studio, beside the
  notice "By signing in you agree to the YouTube Terms of Service", so a user sees
  both before connecting their account (on Apple TV, which cannot open links, the
  address is shown as text).

**3. Policy III.A.2d — what user information, including API Data, is accessed,
collected, stored and used**

The policy has a new section, "Watch Together Studio: the YouTube information
Archive Watch accesses, stores and uses"
(https://archivewatch.org/privacy.html#youtube-data). It lists every piece of
information obtained through YouTube API Services — the OAuth tokens; the
channel's id, name and live-streaming eligibility; the live stream and broadcast
the app creates; the stream key; the concurrent viewer count; and live chat
messages — with, for each, what it is used for, where it is kept and for how long.
It states that none of it is sent to Archive Watch or to anyone else, used for
advertising or analytics, or combined with other information. The existing
sections still describe each API operation the app performs and its adherence to
the Google API Services User Data Policy, including Limited Use.

**4. Policy III.A.2g — storing or accessing information on users' devices,
cookies and similar technology**

The policy has a new section, "Cookies, local storage and similar technologies"
(https://archivewatch.org/privacy.html#cookies). It states that neither the website
nor any app sets a cookie and that no third party is allowed to place or read
cookies or similar technology; what the website keeps in the browser's local
storage and service-worker cache; what the apps keep in the device's preferences
and secure storage (the Apple Keychain); and that Google's own sign-in page may set
Google's cookies under Google's policy.

**5. Policy III.E.4a–g — how often API Data is refreshed, updated or deleted
(confirmation)**

- No YouTube API Data is stored on any server; there is no Archive Watch account.
- Held in memory only, for the duration of a show, and discarded when it ends: the
  channel's id and name, the stream key, viewer counts, live chat messages, and the
  broadcast and stream of a show started immediately.
- Stored on the device:
  - The OAuth tokens, in the Apple Keychain, until the user signs out or revokes
    access.
  - On a Mac, for a show the user schedules ahead of time: the broadcast and stream
    ids, title, description, scheduled time and privacy setting, so the user can
    go live on it later. This record is refreshed from YouTube
    (`liveBroadcasts.list`) whenever the Studio opens if it is more than seven
    days old; removed as soon as the broadcast is gone from or ended on YouTube;
    and deleted 12 hours after the scheduled time, when the user cancels the show,
    when the user signs out, immediately when Google reports the grant revoked,
    and in any case after 30 days without a successful refresh.
- **Sign out** in the app revokes the token at Google and deletes the token and all
  stored API Data from the device at once. Users can also revoke access at
  https://security.google.com/settings/security/permissions, and the app deletes
  its stored API Data the next time it is refused.

These changes are live on the website now, and the in-app link and the data
refresh and deletion rules ship in the next app update.

Thank you again. Please let me know if anything needs more detail.

Ben Wilkoff
Learning is Change, Inc.
