# YouTube API quota extension — draft answers (Decision 136)

Form: <https://support.google.com/youtube/contact/yt_api_form>
("YouTube Data API Services — Audit and Quota Extension Form"). Drafted
2026-09-23 from the live form's fields. **The owner signs in, fills the
personal fields, and presses Submit** — those are theirs alone.

**Send this AFTER audit items A5 and A6 are fixed** (privacy.html links the
YouTube Terms of Service and the Google Privacy Policy, says the app uses
YouTube API Services, and matches the code). The compliance audit reads that
page first, and today it would fail on it.

## Section 1 — Request type
Complete a compliance audit to request for additional quota.

## Section 2 — Organization and contact (OWNER fills)
- Applying: *as an individual user* (or as an organization, if Learning is
  Change is the legal entity — owner's call).
- Full legal name, legal address, contact email: **owner**.
- Parent company: `self` (or the organization).
- Primary website: `https://archivewatch.org`
- Category: **Media and Entertainment**.
- Size/type: **Independent Developer/Sole Proprietor** (or Non-Profit, if so).
- Technical and business contact: same as primary.

## Section 3 — Business model
**Describe your organization's work as it relates to YouTube** (100–5,000 chars):

> Archive Watch is a free app — no ads, no accounts, no purchases — that turns
> the Internet Archive's public-domain film collection into a
> streaming-service-style viewing experience on Apple TV, iPhone, iPad, Mac,
> Android, Google TV, Fire TV, Roku and the web (archivewatch.org).
>
> Its Watch Together Studio lets a person host a live "watch-along" of a
> public-domain film on their OWN YouTube channel: the app composites the film
> with the host's camera, microphone and on-screen graphics, encodes it on
> the device, and sends it over RTMPS to the broadcast it creates on the
> host's channel. The YouTube Data API is used only on the signed-in host's
> own behalf: to create and bind that one live broadcast and stream, to set
> its thumbnail to a still of the show, to read the broadcast's live chat so
> the host can see and answer their audience, to read the concurrent viewer
> count, to post one message sharing the film's Internet Archive link when
> the host asks, and to complete the broadcast (or delete it if it never went
> live) when the show ends. It never reads, lists or changes the host's other
> videos, and it stores no YouTube data on any server — the OAuth token stays in the
> device's Keychain and is revoked on sign-out.
>
> Only films that pass the app's rights audit (public domain by age, pre-1930
> US publication) can be broadcast, and the host is warned that Content ID
> can still match a modern score.

- Target audience: **Individual Content Creators**, **General Public**,
  **Educators and Educational Institutions**.
- Revenue: **Free service (we do not charge users)**. Advertising: *Not applicable*.
- Google representative: **No**.
- Learned about the API: **Google Developer Documentation**.
- Content Owner ID / Ads customer ID: blank. Channel URL (optional): the
  Archive Watch channel, `https://www.youtube.com/channel/UCGNBrxdpR4ujnMWO4_OQgyA`.

## Section 4 — API client
- API Client name: **Archive Watch** (does NOT contain "YouTube").
- Primary access URL: `https://archivewatch.org` (or the App Store link).
- Privacy Policy URL: `https://archivewatch.org/privacy.html`.
- Terms of Service URL: blank unless one is published.
- Publicly accessible: **Yes**.
- Demo account credentials: **none exist — the app has no accounts.** Special
  instructions: *"No login. Install Archive Watch from the App Store (Mac,
  iPhone or Apple TV), open any film, open Watch Together Studio, choose
  YouTube, and sign in with a Google account whose channel has live streaming
  enabled. A demo video of the full flow is linked in Section 6."* Do NOT
  enter any password here.

## Section 5 — Use case and quota
- Project count: 1. **Project number: `895559137709`** (`archive-watch`).
- Use cases: **Tools for Creators** (and *Smart TVs, Consoles & Hardware* —
  the Studio runs on Apple TV).
- Users sign in with Google (OAuth 2.0): **Yes**.
- Derived metrics section: **skip** — the app stores no YouTube data.
- Expected volume: **10,000 to 100,000 requests per day**.

**Quota requested: 500,000 units/day.** Justification:

> Quota belongs to the project, so every host shares it. After the
> reductions in Decision 136 a two-hour show costs about 375 units without
> chat (insert stream + broadcast + bind 150, thumbnail 50, complete 50,
> viewer count every 60 s 120, readiness reads ~4) and about 4,000 with
> chat read every 10 s (liveChatMessages.list, 720 calls x 5 units). At the
> default 10,000 units that is two chat-reading shows a day for everyone.
> 500,000 units supports roughly 100 such shows a day. The app also offers a
> stream-key connection that uses no API at all, and stops reading on
> quotaExceeded instead of retrying.

## Section 5/6 — Evidence (built 2026-09-23, in ~/Desktop/YouTube quota evidence/)
| Form field | File |
|---|---|
| Privacy Policy screenshots | `privacy-policy-page.pdf` (Chrome print of the live page, URL on every page) |
| Homepage screenshot | `homepage-privacy-link.png` (About view: Watch Together card naming YouTube, beside Privacy / Terms) |
| Terms of Service documentation | `terms-of-service.pdf` (live terms.html, with the YouTube API Services section) |
| Conditional: OAuth flow + player | `oauth-flow-scopes-revocation-and-player.pdf` (unverified-app screen, consent listing "Manage your YouTube account", Studio Sign out, revocation policy) |
| Architecture diagram | `architecture-diagram.png` |
| User flow diagrams | `user-flow-diagrams.png` |
| Other supporting materials | `quota-justification-and-compliance.pdf` |

## Section 7 — Attestations
Owner reads and ticks each, then Submit.
