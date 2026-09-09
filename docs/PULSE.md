# Pulse — one place that knows how Archive Watch is doing

**<https://archivewatch.org/pulse/>** — unlisted (robots-disallowed, linked from
nowhere), refreshed once a day at 07:17 America/Denver by `.github/workflows/pulse.yml`.

Every store, every review, every mention, every request, and the numbers over
time. Built by `tools/pulse_collect.py` into `ops/pulse.json`; rendered by
`pulse/index.html` + `pulse.js` + `pulse.css` — vanilla, no build step.

---

## The three rules it is built on

**1. A reader that cannot read SAYS SO.** Every source is isolated; a failure is
recorded in `sources` and shown on the page as *"could not read — no credential
in this environment"*. It is never a zero. A dashboard that prints a confident
`0` for a broken reader is worse than no dashboard, because it reads as good
news and nobody checks again.

**2. Numbers are kept forever; text is a window.** `history` holds one compact
row per day and nothing in it may grow — that series is the whole point of
"progress over time". Reviews cap at 200 and mentions at 150, newest first.

**3. A request is QUOTED, never summarised.** `asks` extracts the sentence a
person actually wrote and links to it. No model, no sentiment score. The owner
reads their words. (Learning-orientation gate: the dashboard makes the owner
*better at reading their users*, it does not read for them.)

And one rule about the workflow itself: **Pulse is a REPORTER** (Decision 107).
It never goes red because something it read is unhealthy — findings land on the
page and as a `::warning::`. It fails only when it cannot write or push its own
file, and that step carries an explicit `# reporter-may-fail:` marker that
`tools/check_workflow_gates.py` enforces.

---

## How it LOOKS — binding

Every number on this page carries a shape, and the shape is chosen the same way
every time. The rules below are binding: a new panel must cite one, and if none
fits, the rule set gets the new entry before the panel gets written.

**1. A number alone means nothing — give it a comparison.** Against a scale (the
rating), against its siblings (posts per platform), against its own past (the
sparklines), or as a share of a whole (the estate). "4.4" is a fact; "4.4 of 5,
target 4.5, up 0.03 since yesterday" is a finding.

**2. Encode in Cleveland & McGill's order.** Position first, then length, then
area, and colour last. So a comparison is a bar on a common baseline or a mark
on a shared axis. Angle and area are never used to carry a quantity — which is
why there is no pie chart, no donut, and no bubble on this page.

**3. Colour means STATE, never quantity** (Decision 013's split, applied to
health). Teal is live, amber is in flight, red needs you, grey is nothing yet.
The bullet graph's qualitative bands are one hue at three intensities, per Few,
so they survive colour-blindness and spend no colour on a number.

**4. No gauges, no dials.** Few's whole argument: they show one number, take a
quarter of the screen, and arrive covered in decoration. `bullet()` shows the
measure, the scale, the qualitative bands and the target, in a strip 22 pixels
tall.

**5. Word-sized graphics sit beside their number.** A sparkline (Tufte) is read
in the same glance as the figure it belongs to. No axis, no legend, no chart to
open.

**6. Zero is drawn, absence is written.** A source that returned zero gets a bar
of length zero. A source that could not be read gets the words "not read" and
the reason — never a bar, never a zero. (This is rule 1 of the whole tool, in
visual form.)

**7. The panel is the cell, not a card.** Separation comes from the grid's own
hairlines. No tinted boxes, no shadows, no rounded floating cards stacked on a
background — the density rule this project applies everywhere else.

The kit that implements this is `pulse/charts.js`: `bullet`, `bars`, `spark`,
`stack`, `legend`, `dots`, `ratio`, `cadence`. Hand-rolled inline SVG, no
library, no build step. `tools/test_pulse_charts.mjs` asserts the properties a
reader actually relies on — a bar's length is proportional, a bullet's measure
lands at the right position and clamps past the top of its scale, a stack sums
to 100%, a one-point series draws nothing rather than a misleading flat line —
and all 31 cases were checked to FAIL against broken versions of each rule.

### Which shape, for which signal

| Signal | Shape | Why that one |
|---|---|---|
| App Store rating | bullet, bands at 3 and 4, target 4.5 | one measure against a fixed scale with a goal — Few's exact case |
| How the reviews fall | bar per star level | the chart every store already shows its users; one 2★ is impossible to miss |
| The estate | stacked proportion + legend | "how much of what we ship is out" is a share of a whole |
| Catalog coverage | bars on a shared max | three coverages against the same denominator |
| Followers, posts, mentions | bars | comparison across platforms and sources, on one baseline |
| Android vitals | bullet, inverted, target = Google's threshold | the only numbers here with a target somebody else set |
| Workflow fleet | dots | one mark per finding: a count and a proportion at once |
| Enjoying vs asking | stacked bar | two parts of one body of feedback |
| Posting cadence | lanes on a shared 30-day axis | a programme's question is "did they keep coming", not "how many" |
| Anything over time | sparkline | shape and level, at the size of a word, beside the number |

---

## What it reads, and how

| Signal | Route | Auth | Runs |
|---|---|---|---|
| Apple version state ×3 platforms | ASC `appStoreVersions` | `ASC_*` | CI + local |
| Apple customer reviews, all territories | ASC `customerReviews` (paged, `include=response`) | `ASC_*` | CI + local |
| Apple rating summary | `itunes.apple.com/lookup` | none | anywhere |
| Play track state (prod/beta/internal) | `androidpublisher` `edits.tracks` | Play SA | ⚠ see below |
| Play reviews (7-day window) | `androidpublisher` `reviews.list` | Play SA | ⚠ |
| Play rating | store page | none | when the listing has one |
| Play crash + ANR rate | `playdeveloperreporting` `vitals.crashrate` / `anrrate` | Play SA | ⚠ API disabled |
| Play crash clusters | `vitals.errors.issues.search` | Play SA | ⚠ API disabled |
| Amazon / Roku / LG / Samsung / web | `ops/stores-manual.json`, by hand | — | always |
| Posts + engagement | `social/posted.json` + `social/metrics.json` | — | anywhere |
| Follower counts | Bluesky public API, Mastodon `verify_credentials`, IG Graph | social | CI |
| Replies + mentions of us | Bluesky `notifications` + `searchPosts`, Mastodon `/api/v2/search` | social | CI |
| YouTube subs, views, comments | YouTube Data API v3 | `YOUTUBE_*` | CI |
| Reddit | `reddit.com/search.rss` | none | anywhere |
| Hacker News | Algolia | none | anywhere |
| Lemmy | `lemmy.world` + `lemmy.ml` `/api/v3/search` | none | anywhere |
| Press | Google News RSS | none | anywhere |
| Stars, issues, repo traffic | `gh api` | `GH_TOKEN` | CI + local |
| Workflow fleet health | `tools/audit_workflow_health.py` | `GH_TOKEN` | CI + local |
| Catalog size and coverage | `archivewatch.org/catalog-index.json` | none | anywhere |

### Measured, and worth knowing

* **Reddit's JSON search answers 403 to an unauthenticated caller; the RSS of the
  same search answers 200.** It is rate-limited hard (a second call in the same
  minute got 429) so Pulse makes exactly one, and Reddit's matching is fuzzy —
  a query for `archivewatch` returned a post titled *"Vintage Tissot"*. The
  `relevant()` filter is what makes the results usable, and
  `tools/test_pulse_collect.py` locks that case in by name.
* **A Reddit OAuth "script" app would be much better** (real search, higher
  limits). It is a five-minute owner step at <https://www.reddit.com/prefs/apps>;
  wire the id/secret in and replace `mentions_reddit`.
* **Google Play has no public ratings API.** The listing is scraped, and while
  the app has too few ratings Play prints none at all — so "no rating yet" here
  is the truth, not a broken reader.
* **`asc_release.py` needed Python 3.12.** It carried a multi-line f-string
  expression (PEP 701), which is a `SyntaxError` on 3.11 — so Pulse's first CI
  run, pinned to 3.11, could not import it and read zero Apple reviews while the
  same code read four on the dev Mac. Flattened at the source, so no workflow can
  step on it again whatever Python it pins.
* **X, Pinterest, Letterboxd, Tumblr, Discord** were researched for the social
  programme and rejected for cost or access; see `docs/SOCIAL-SETUP.md` §6. None
  is readable here either.

---

## Owner steps (each unlocks a panel that currently says "could not read")

1. **`PLAY_SERVICE_ACCOUNT_JSON` as a repo secret** — paste the contents of
   `~/.config/play/archivewatch-play.json`. Without it the Play columns read only
   when Pulse is run on this Mac. (The collector accepts either a path or the JSON
   itself.)
2. **Enable the Play Developer Reporting API** for the service account's project:
   <https://console.developers.google.com/apis/api/playdeveloperreporting.googleapis.com/overview?project=294492189901>
   — one click. That turns on crash rate, ANR rate, and the named crash clusters,
   which is the only signal here that says "something needs fixing" *before* a
   user bothers to write it down.
3. **YouTube stats and comments need `youtube.readonly`.** The programme's token
   holds `youtube.upload` and nothing else, which
   `tools/youtube_refresh_token.py` argues for in as many words — a secret in CI
   that can post but cannot read the account. Pulse reports that as a choice, not
   a fault. Note the same limit means **`social_metrics.py` cannot read YouTube
   view counts either**; if those numbers are wanted, re-mint the token with
   `youtube.readonly` added and accept the wider secret.
4. **`FB_PAGE_ID` + `FB_PAGE_ACCESS_TOKEN`** are referenced by `social-post.yml`
   and are **not in the repo's secrets** — Facebook has never actually been
   connected, the same way Mastodon once was not.
5. **Keep `ops/stores-manual.json` current.** Amazon, Roku, LG and Samsung have no
   API; that file is how they appear on the page at all. Editing it is the whole
   maintenance burden of this dashboard.

---

## Running it

```bash
# everything the local machine can reach (Play included, ASC from tools/asc-credentials.env)
set -a; . tools/asc-credentials.env; set +a
python3 tools/pulse_collect.py            # collect and print, write nothing
python3 tools/pulse_collect.py --apply    # write ops/pulse.json

python3 tools/pulse_collect.py --only apple_reviews,mentions_hn   # one reader

# `--only` MERGES: it starts from the last reading and replaces only the parts
# its own sources produce, so a quick local run cannot delete the mentions CI
# gathered. Absence is not evidence, one level up from the `sources` rule.

python3 -m http.server 8080               # then open /pulse/
python3 tools/test_pulse_collect.py       # 48 cases, negative-controlled
```

The collector needs `PyJWT cryptography google-api-python-client google-auth`;
`~/.venvs/aw` on this Mac has them.

---

## Reading the page

* **Needs you** — the only list that asks for a decision: urgent workflow
  findings, reviews under four stars in the last 60 days (replied or not — a
  person who could not play a film is still a person who could not play a film),
  crash clusters, issues opened from outside, a store in a rejected state, and
  requests waiting to be read. When it is empty it says so in words.
* **Where we are shipping** — every store on one list, machine-read and declared
  side by side, with a note when a store is behind `AppVersion.xcconfig`.
* **What people said** — reviews and mentions in one reading list, newest first.
  A sentence detected as a request is marked with an orange rule down its left.
* **Over time** — fills in from the second day. One reading per day, forever.
* **Where this came from** — which readers answered, and why the others did not.
  Read this panel before believing a zero anywhere else on the page.
