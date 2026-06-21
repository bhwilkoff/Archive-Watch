# Research: archive.org community & popularity signals

*Date: 2026-06-21. All API claims below were probed against live archive.org
endpoints on this date (see "Verified" tags).*

## Goal

Use archive.org's built-in community/usage data — **views, favorites,
ratings, reviews/comments, and lists** — plus optional **account login** to:

1. **Pick the right *upload* of each film** (version quality) — Decision 040
   chooses the best *copy*; today it scores on file resolution + captions only.
   Community signals (rating, reviews, favorites) are a much stronger "this is
   the canonical copy" signal.
2. **Rank/sort titles by real popularity** — replace the single all-time
   `downloads` proxy with a recency-aware, quality-weighted score.
3. **Surface the community** already on archive.org — how many people watch a
   film, save it, and what they say about it — as first-class UI.
4. **(Optional, later) Two-way sync** — let a user connect their archive.org
   account to read their favorites and post their own ratings/reviews.

This is squarely on-mission (CLAUDE.md "why we build"): the community *is* the
repertory-cinema conversation. The learning-orientation verdict per feature is
in the last section — it is what sets the phasing.

---

## A. Verified API findings

### Read signals (no auth) — all live-verified 2026-06-21

| Signal | Endpoint / field | Real example | Notes |
|---|---|---|---|
| **Views** (watch momentum) | `GET https://be-api.us.archive.org/views/v1/short/{id}` → `all_time`, `last_30day`, `last_7day` | `Night.Of.The.Living.Dead_1080p` → all_time 304,904 · 30d 1,460 · 7d 308 | **Bulk:** comma-join ids in the path returns a keyed object (undocumented but live). `/long/{id}` gives per-day arrays index-aligned to a `days` array. Bot-filtered. |
| **Downloads** (all-time reach) | advancedsearch/scrape `downloads` | 304,714 | All-time cumulative file fetches; never decays. The legacy popularity number. |
| **Recent downloads** | `week`, `month` | 332 / 1,604 | Trailing 7/30-day. On-index "what's hot" without the views API. |
| **Avg rating** | `avg_rating` | 4.83 | 0–5. Omitted (not null) when unrated. |
| **# reviews** | `num_reviews` | 13 | Counts comments too (a comment with no stars = `stars:0`). |
| **Stars histogram** | `stars` | `[0,5,4]` | Per-review star values; `0` = comment, exclude from rating math. |
| **Favorites count** | `num_favorites` | 540 (dvd copy: 730) | **Direct first-class field.** Do NOT use the `fav-*`-in-collection approach — verified it returns nothing (fav pseudo-collections live on the *user*, not the item). |
| **Full reviews** | `GET https://archive.org/metadata/{id}` → `reviews[]` | `{reviewer, reviewtitle, reviewbody, reviewdate, createdate, stars}` | All reviews returned, not capped. |

**Bulk harvest for the 30k catalog:** `GET https://archive.org/services/search/v1/scrape?q=…&fields=identifier,downloads,week,month,num_favorites,avg_rating,num_reviews,item_size,year&count=10000&cursor=…` — cursor paging, ~3 calls for 30k. Views are NOT in scrape (`week`/`month` are *downloads*); pull recent-view momentum separately from the views bulk endpoint. No rate-limit headers exposed — handle `429`/`Retry-After` defensively, descriptive `User-Agent`.

### Write / account (auth) — verified endpoints, raw-password model

- **Auth:** NO OAuth/OIDC exists. The only path is `POST https://archive.org/services/xauthn/?op=login` with **email + password** → returns S3 `access`/`secret` keys + `logged-in-user`/`logged-in-sig` cookies (the official `internetarchive` Python lib uses exactly this). Verified-live error envelope; this is the mechanism IA's own tools use.
- **Favorites:** read via `q=collection:fav-<username>` search (verified-live). Write via SimpleLists `-patch` on `POST /metadata/{id}` (`-target=simplelists`, op `set`/`delete`, `parent=fav-<user>`, `list=favorites`) — documented, **not** live-verified (needs a real account; docs warn `fav-` writes may need permission).
- **Reviews:** read own via `GET /services/reviews.php?identifier={id}` (auth-gated, verified-live); all public reviews via the metadata `reviews[]`. Write/update `POST /services/reviews.php` `{title, body, stars}`; delete `DELETE …` — S3-key auth, **moderated/queued** (not instant).
- **Lists:** same SimpleLists mechanism (no separate API). No endpoint enumerates "all of a user's lists" — you must know list names.

**The blocker (auth):** there is no token/app-password/OAuth — connecting an account means the app **collects the user's raw archive.org password**. That is an App/Play review liability and a real trust cost, and is a poor fit for 10-foot tvOS password entry. Store only the resulting S3 secret (Keychain/Keystore), never the password.

---

## B. Application 1 — best-*upload* selection (version quality)

Decision 040's `merge_film_duplicates` picks the surviving copy by
`(captions, _video_quality, _real_art_rank, imdbVotes)`. `_video_quality` is
filename-resolution + qualityScore only. **Raw `downloads` is a trap** — live
proof: for *Night of the Living Dead* the most-downloaded item is the **trailer**,
not the film. The right signal is a composite that humans implicitly vetted:

```
copyScore = 3.0·(avg_rating · log10(1+num_reviews))   # rated + reviewed = a real, vetted copy
          + 2.0· log10(1+num_favorites)               # people deliberately saved THIS upload
          + 1.0· log10(1+downloads)                   # reach, tiebreaker only
          + format_bonus(resolution/item_size/H.264)  # existing _video_quality
          − trailer_penalty(/trailer|clip|teaser|excerpt/ + tiny item_size)
```

Integrate as a term in the Decision-040 winner key (after captions, which stay
top because subs are matched to one exact copy). This complements Decision 026
(right *film*) and 040 (right *upload*): community vetting picks the upload a
real audience endorsed. The **trailer penalty alone** fixes a real failure class.

## C. Application 2 — popularity sort (recency + quality, damped tail)

`downloads` alone is dominated by a few mega-items and never decays. Blend:

```
popScore = 0.45·log10(1+views_last_30day)   # current watch momentum (views bulk)
         + 0.20·log10(1+month)              # recent downloads
         + 0.20·log10(1+downloads)          # all-time reach, damped
         + 0.10·bayesian_rating             # vote-floored quality (reuse Top-Rated discipline)
         + 0.05·log10(1+num_favorites)      # deliberate community signal
bayesian_rating = (n/(n+m))·avg_rating + (m/(n+m))·C   # C≈catalog mean, m≈10 vote floor
```

Recompute each pipeline pass; `views_last_30day`/`month` decay naturally, so a
trending/"hot now" lens falls out with no separate model. **Learning-orientation
constraint (see §F):** expose this through **explicitly named lenses** the user
chooses — "Most Watched This Month", "Highest Rated", "Most Discussed",
"Community Favorites" — NOT one opaque "Popular"/"For You" feed.

## D. Application 3 — surface the community (UI)

- **Detail page:** "Watched by 304,904 · in 540 favorites · 4.8★ (13 reviews)";
  a **Reviews section** rendering the metadata `reviews[]` with dignity
  (reviewer, date, stars, body) — this is the repertory-cinema conversation.
- **New shelves/sorts** (named lenses): Community Favorites (`num_favorites`),
  Most Discussed (`num_reviews`), Watching Now (`views_last_30day`), Highest
  Rated (existing Top-Rated, now Bayesian).
- Read-only — no login needed. High value, low risk, strong mission fit.

## E. Application 4 — optional account login + two-way sync (later, gated)

- **Read:** a connected user's favorites (`collection:fav-<user>`) → merge into
  the app's Library as a third sync source (alongside CloudKit / Drive App Data,
  Decision 022/028).
- **Write:** post a rating/review back to archive.org; add/remove a favorite.
- **Constraints:** opt-in; **web + mobile only, never tvOS** (raw-password entry
  + store-review risk); deliberate confirm before any public post (never
  one-tap — it writes to a permanent public record); store only the S3 secret in
  Keychain/Keystore; validate the favorites-*write* path against a live test
  account before shipping (docs warn it may need permission).

---

## F. Learning-orientation verdict (drives the phasing)

Four-question test (CLAUDE.md). Results differ by feature — that is the signal
for sequencing:

| Feature | Deepen? | Participate? | Agency? | Clarity? | Verdict |
|---|---|---|---|---|---|
| **Reviews/comments on Detail** | **Yes** (the community's knowledge) | read→write | Yes | Simple | **Strongest pass — lead with this** |
| Best-upload selection | n/a (mechanical) | n/a | Yes (better copy) | composite but invisible | **Pass — automate freely** (automate the mechanical) |
| View/favorite/rating counts | Partial | Passive display | Neutral | Simple | **Pass with framing** — "540 people saved this" (connection), not a leaderboard score |
| Popularity ranking | Risk: opaque feed | Only if explicit | Yes iff named lenses | composite | **Pass ONLY as named, user-chosen lenses** — never a single "For You" feed |
| Login + post reviews | **Highest** (contribute judgment to the commons) | **Yes** (co-author) | Mixed (raw-password dependency) | **Auth is messy/risky** | **Defer** — highest participation value, weakest/ riskiest mechanism; opt-in, deliberate, off-tvOS |

Key design rules that fall out: (1) expose the **structure** (named sort lenses,
visible review text), don't hide behind "for you"; (2) automate the mechanical
(best-copy), preserve the meaningful (the user's own review is never auto-drafted
by AI); (3) posting to a public permanent record is never one-tap.

---

## G. Proposed phasing

- **P0 — Harvest read signals into the catalog (pure pipeline, low risk).**
  New `tools/harvest_community_signals.py` (scrape API + views bulk) → additive
  catalog fields `numFavorites, avgRating, numReviews, viewsAllTime,
  views30d, week, month`; weekly CI workflow (mirrors `color-classify.yml`).
  Feeds B (best-upload) + C (popScore). No app change yet.
- **P1 — Best-upload + popScore (data-only, all platforms).** Wire `copyScore`
  into Decision-040 winner selection and `popScore` into `popularityScore`.
  Rebuild DB; every platform benefits with no app build.
- **P2 — Community on Detail + named shelves (app UI, all platforms).** Counts +
  reviews section on Detail; Community Favorites / Most Discussed / Watching Now
  shelves. Read-only, no login. Reviews stored in the catalog (cap N per item) or
  fetched live from the metadata API on Detail open.
- **P3 — Optional archive.org login (web + mobile only).** Connect account →
  read favorites into Library; post ratings/reviews with a deliberate confirm.
  Gated behind live validation of the write path; never on tvOS.

P0–P2 are pure read-side wins with no auth risk. P3 is the high-value,
high-risk participation step — decide separately.

## H. Open questions / decisions to log

- **popScore weights + best-copy weights** need tuning against the live catalog
  before they replace the current sort (A/B against today's `popularityScore`).
- **Reviews storage:** bake top-N reviews into the catalog (offline, fast, ages)
  vs fetch live on Detail open (fresh, needs network + the metadata API which can
  be slow). Likely: counts/rating in catalog; review *text* fetched live with a
  bounded timeout + cache.
- **P3 auth** warrants its own Decision entry (raw-password handling, Keychain
  storage, store-review posture, tvOS exclusion) before any code.
- Confirm the favorites-**write** path on a live test account (docs warn it may
  need list-write permission).
