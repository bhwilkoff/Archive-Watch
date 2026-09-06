# Connecting the accounts

Everything is built. This is the only document you need to turn it on, and it
is ordered by **what pays off soonest for the least work**. Each platform is
independent: connecting one changes nothing about the others, and the daily
run silently skips every platform whose secrets are missing.

Secrets go in **GitHub → Settings → Secrets and variables → Actions**.

---

## 0. Before any account: watch it run

The workflow is safe to run with no secrets at all — it will pick a film,
render the cards, and tell you exactly what it *would* post.

**Actions → Social post → Run workflow** (leave "dry run" ticked).

Download the `social-card` artifact from the run. That is the picture that
would have gone out, and the log shows the copy for each platform with the
catalog field every sentence came from. Do this once before connecting
anything; if a card looks wrong, nothing has been published.

---

## 1. Bluesky — 5 minutes, no review, works today

No app review, no business account, no OAuth. Start here: it is where you will
see the programme actually working. (Mastodon, below, is the other one with no
review — connect both and you have a real presence in an afternoon.)

1. Make the account (e.g. `archivewatch.bsky.social`).
2. **Settings → Privacy and Security → App Passwords → Add App Password.**
   Name it `archive-watch-ci`. Copy the password — it is shown once.
3. Add two secrets:
   - `BLUESKY_HANDLE` → `archivewatch.bsky.social`
   - `BLUESKY_APP_PASSWORD` → the app password (not your login password)
4. **Actions → Social post → Run workflow**, untick "dry run", `only` =
   `bluesky`.

That is the whole setup. The next scheduled run posts on its own.

---

## 1a. Mastodon — 3 minutes, no review, no app at all

The cheapest platform here to connect, and the best audience fit of anything
not already listed: the Fediverse has unusually dense archivist, library and
film-preservation communities, and an account that posts one carefully sourced
thing a day is the norm there rather than an anomaly.

There is no developer portal and no review. The token is minted inside the
account's own settings.

1. Make the account on any instance. `mastodon.social` is the safe default;
   a film or archive themed instance is a better fit if you find one you like.
   **Check the instance rules before pointing an automated account at it** —
   some ask that bots be labelled, and marking the account as a bot in
   **Preferences → Profile** is good manners either way.
2. **Preferences → Development → New application.**
   - Application name: `Archive Watch`
   - Scopes: tick **`write:statuses`** and **`write:media`**. Untick
     everything else, including `read` — the poster never needs to read.
3. Open the application you just made and copy **"Your access token"**.
4. Add two secrets:
   - `MASTODON_INSTANCE` → `mastodon.social` (the bare host or the full URL,
     either is fine)
   - `MASTODON_ACCESS_TOKEN` → the access token
5. **Actions → Social post → Run workflow**, untick "dry run", `only` =
   `mastodon`.

Two things this adapter does that the others cannot:

- **It asks your instance how long a post may be.** 500 characters is only
  Mastodon's default; instances set their own, and some run to 11,000. The
  copy is composed against whatever your server actually allows, and falls
  back to 500 if the instance cannot be reached.
- **A retried run cannot double-post.** Every status carries an idempotency
  key built from the film and the date, so if the workflow is re-run the
  server returns the original post instead of publishing it again.

Images always carry alt text describing the poster and the film, because on
the Fediverse an undescribed image is a discourtesy, not an oversight.

---

## 2. Threads — a Meta app, then app review

Threads is the best value of the Meta three: the audience skews toward exactly
the people who like old films, and the API is the simplest of the three.

1. **developers.facebook.com** → create an app → add the **Threads** use case.
2. Add the permissions `threads_basic` and `threads_content_publish`.
3. Generate a **long-lived access token** for the Threads account (60 days,
   refreshable — see §5 below).
4. Secrets: `THREADS_USER_ID`, `THREADS_ACCESS_TOKEN`.
5. Also set `SOCIAL_MEDIA_BASE_URL` (§4) — Meta fetches the card by URL.

**App review is required before it will post for a live account.** Expect a
couple of weeks. The reviewer wants to see what the app does; point them at
`docs/SOCIAL-PROGRAM.md` and a dry-run card.

---

## 3. Instagram and Facebook — the long road

Both need a Meta app, and Instagram needs a **Professional (Business or
Creator)** account. The permissions are `instagram_business_basic` +
`instagram_business_content_publish`, and Facebook needs `pages_manage_posts`
plus **business verification**. Review runs 2–4 weeks per submission.

- Instagram: `IG_USER_ID`, `IG_ACCESS_TOKEN`
- Facebook Page: `FB_PAGE_ID`, `FB_PAGE_ACCESS_TOKEN`

Both also need `SOCIAL_MEDIA_BASE_URL`.

Instagram gets the **portrait** card automatically; it is the frame Instagram
favours and the code already renders it.

---

## 3a. YouTube — a browser flow once, then it runs

The daily teaser is already 1080×1920 and about 18 seconds, which is what
makes it a Short: YouTube classifies by shape and length, not by a flag.

1. **console.cloud.google.com** → new project → enable **YouTube Data API v3**.
2. **Credentials → OAuth client ID → Desktop app.** Note the client ID and
   secret.
3. Mint a refresh token once, in a browser, with the scope
   `https://www.googleapis.com/auth/youtube.upload`. Google's OAuth Playground
   does this in two minutes: tick that scope, authorise your channel, exchange
   the code, and copy the **refresh token**.
4. Secrets: `YOUTUBE_CLIENT_ID`, `YOUTUBE_CLIENT_SECRET`,
   `YOUTUBE_REFRESH_TOKEN`.

No app review. Uploads bill to their own daily bucket, so one a day is far
from any ceiling. Videos are published public and marked not-made-for-kids,
with the film's own facts in the description.

---

## 4. `SOCIAL_MEDIA_BASE_URL` — why Meta needs it

Bluesky takes the image bytes directly. **Meta does not**: you hand it a public
URL and Meta's servers fetch the picture themselves. So the card has to be
somewhere public before the post is made.

The pipeline publishes each card to a rolling GitHub Release named
`social-cards` — the same trick the catalog uses (Decision 018), so nothing
bloats git. Set:

```
SOCIAL_MEDIA_BASE_URL = https://github.com/bhwilkoff/Archive-Watch/releases/download/social-cards
```

Nothing else to create; the first run makes the release if it is missing.

---

## 5. Token expiry, honestly

- **Bluesky app password**: does not expire. Set it once.
- **Meta long-lived tokens**: 60 days, and they must be refreshed. This is the
  one piece of ongoing maintenance in the system, and it is the reason to
  start with Bluesky. When you connect a Meta platform, put a calendar
  reminder at 50 days; a refresh is one API call, and the run will simply skip
  that platform if the token has lapsed rather than failing.

---

## 6. Not built, and why

- **TikTok** cannot be automated, and this is a property of TikTok rather
  than a gap here: every requirement in its content-sharing guidelines is
  about a person consenting in a UI immediately before each post (creator
  nickname shown, music-usage confirmation, manual privacy and interaction
  settings, a preview). Unaudited clients are capped at five users a day and
  every post is private-only.

  **What to do instead:** each daily run leaves the vertical teaser and the
  composed caption in the `social-card` artifact. Download it and post it by
  hand — under a minute, and the only part TikTok reserves for a person is
  the part a person does.
YouTube and Bluesky video are BUILT (see §1 and §3a). Bluesky posts the
teaser instead of the card whenever a clip was cut, which needs no review at
all — moving pictures the day you paste the app password.

### Researched 2026-09-06 and deliberately not built

Recorded so nobody re-walks these. Each was checked against the current API
terms, not remembered.

- **X / Twitter** — the legacy paid tiers were retired and replaced with
  pay-per-use on 1 June 2026, and a post carrying a **URL costs more than a
  plain one**. Every post here carries a URL. The cost at one a day is small;
  the objection is that it is the only platform charging admission, and its
  audience for silent film is not better than Mastodon's.
- **Reddit** — the wrong shape twice over. Self-service API registration
  closed in late 2025, so a new client is a manual ticket with no published
  timeline. And subreddit self-promotion rules make a daily automated poster
  exactly the thing moderators remove. Reddit rewards a person participating.
  Worth your time by hand; never worth automating.
- **Pinterest** — the closest call, and the only candidate whose value
  compounds: pins keep pulling traffic for years where a feed post dies in
  hours, and posters are close to ideal Pinterest content. Blocked on two
  things. Trial access creates pins **visible only to their creator**, and
  standard access needs a screen recording of the OAuth flow plus a review of
  one to four weeks. Read the developer guidelines first: they forbid
  features that let users initiate actions "without specifically considering
  each action", which is aimed at bulk schedulers acting for third parties
  but is a real risk to weigh before investing.
- **Letterboxd** — the best audience on the list, over 30 million people
  whose register is exactly classic film. But access is **by request only**
  (email `api@letterboxd.com`), and it is a film *diary*, not a broadcast
  channel: there is no post object that fits a marquee. What would fit is a
  curated list, which is a different product. Worth an email, not a build.
- **Tumblr** — genuinely alive for film culture and its post format handles
  image-plus-text well. Old-style OAuth is fiddly but there is no heavy
  review. The most reasonable *next* build after Mastodon.
- **Discord** — a webhook needs no auth, no bot and no review, and is perhaps
  fifteen lines. Low reach, near-zero cost. Worth adding the day a community
  server exists; pointless before then.

---

## 7. Turning it off, or down

- **Off:** disable the *Social post* workflow in the Actions tab. Nothing
  else in the repo depends on it.
- **Different day, different slot:** edit `social/program.json`.
- **Skip a film forever:** add its `archiveID` to the ledger by hand; the
  selector treats anything in `social/posted.json` as recently posted.
