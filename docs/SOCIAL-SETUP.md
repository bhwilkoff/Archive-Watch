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

The only platform with no app review, no business account, and no OAuth. Start
here: it is where you will see the programme actually working.

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

- **TikTok.** The Content Posting API restricts every unaudited client's posts
  to **private viewing**. Public posting needs TikTok's content-posting audit,
  which reviews your app's UX — and there is no UX here, only a scheduler.
  A TikTok presence is realistic, but it wants a person, and probably a
  different kind of post (a clip with a voice) than this programme makes.
YouTube and Bluesky video are BUILT (see §1 and §3a). Bluesky posts the
teaser instead of the card whenever a clip was cut, which needs no review at
all — moving pictures the day you paste the app password.

---

## 7. Turning it off, or down

- **Off:** disable the *Social post* workflow in the Actions tab. Nothing
  else in the repo depends on it.
- **Different day, different slot:** edit `social/program.json`.
- **Skip a film forever:** add its `archiveID` to the ledger by hand; the
  selector treats anything in `social/posted.json` as recently posted.
