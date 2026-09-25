# Pulse — one place that knows how Archive Watch is doing

**<https://archivewatch.org/pulse/>** — unlisted (robots-disallowed, linked from
nowhere), refreshed once a day at ~07:00 (cron 08:17 UTC; GitHub runs this repo's schedules 4–5 h late, measured 2026-09-15) America/Denver by `.github/workflows/pulse.yml`.

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

**8. Every number opens, and it opens the same way.** (Added 2026-09-25, from
the owner: *"make The Pulse a much more action-oriented ... better drill downs,
more information overall"*.) There is ONE drill-down on this page: a native
`<dialog class="drawer">`, opened from a panel header, a Needs/Going-well item,
a store row, a chart, or a table row. Its route is in the hash —
`#<view>/<drawer>` (e.g. `#health/crash/<clusterId>`, `#reach/series/apple-dl`)
— so a drawer is linkable and survives a reload. Every drawer carries, in this
order: (1) the full series as a DATED chart with the change against the prior
period, (2) the COMPLETE table behind the figure, sortable by any column — never
a silently capped list — and (3) a link to the source ↗. A panel that has none
of the three has nothing to open and says so by not offering a chevron.
`panel()`'s `detail` rows are that table, so every caller upgrades at once.

**9. A chart over time shows WHEN.** A drawer chart (`timeChart`) prints its
first and last dates and the top of its scale, and reads out the date and
every value under the pointer, on focus, and with the arrow keys. A sparkline
beside a number stays word-sized (rule 5); anything a reader is asked to act
on gets dates. Days are calendar days and are labeled as written. Instants
(when a reader ran, when a review was left) are shown in Mountain time
(America/Denver), never UTC. Series shown side by side share one calendar and
one scale; days a series does not cover are greyed, so a stalled reader looks
different from a quiet week.

**10. A change names its period.** Every delta on the page is written by one
function and always ends in its comparison: *"+18% vs prior 7 days"*, *"no
change vs yesterday"*, *"−0.2 vs prior 28 days"*. No bare "—", "level" or
"no change". A day still in progress is never compared. Color follows
direction-of-good: a falling average search position is teal.

**11. A panel standing on an old reading says "as of".** When a panel's newest
data is older than its source's normal lag (two days by default, four for
Search Console, whose own lag is two to three), its header carries an amber
*as of <date>* chip, and the reader appears in Needs attention as stale.

**12. Only essential words.** (Owner, 2026-09-22 — the project-wide rule.) A
caption on this page is a REFUSAL (why a number is absent), a WARNING, or a
fact the reader could not discover by looking. The reasons for a chart's shape
live in this document and in code comments, never under the chart.

**13. The page writes no style declarations.** Presentation is in
`pulse.css`, keyed by class and `data-` attribute. The one exception is a
COMPUTED length — a bar's width, a mark's position, the chart tooltip's `--x`
— which exists only once the data does, lives inside `charts.js`, and is set
as a custom property where the DOM allows it.

The kit that implements this is `pulse/charts.js`: `bullet`, `bars`, `spark`,
`stack`, `legend`, `dots`, `ratio`, `cadence`, `runChart`, `calendarHeat`,
`dotPlot`, `pareto`, and `timeChart` with `interact` for the drawers. Hand-rolled inline SVG, no
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
| Anything over time, opened | `timeChart` in the drawer | dates, the top of the scale, and a readout per day (rule 9) |
| Installs across platforms | small multiples on one calendar and one scale | a shared axis is the only honest comparison of shape; a stalled series greys its missing days |
| Google Play rating | bullet (bands 3 and 4, target 4.5) + dated run chart | the same scale as the App Store's, so the two ratings read alike |
| Roku stability | bullets: crash % of streaming devices (marker at the 2% rule), rebuffers per streaming hour | Roku's own headline figures, with the threshold this page acts on |
| Store-listing funnel | two-line dated chart (visitors, acquisitions) + conversion | a funnel is two counts and the ratio between them |
| Web titles | two-line dated chart (opened, played) + the play/open ratio per title | opening is interest, playing is choice; the ratio is the finding |
| Search | clicks and impressions as separate dated charts; CTR and average position against the prior 28 days | two magnitudes three orders apart cannot share an axis; position is labeled *lower is better* |
| Watch Together | rooms and guests on one dated chart | two counts of one activity, same unit |

---

## What it reads, and how

| Signal | Route | Auth | Runs |
|---|---|---|---|
| Apple version state ×3 platforms | ASC `appStoreVersions` | `ASC_*` | CI + local |
| Apple customer reviews, all territories | ASC `customerReviews` (paged, `include=response`) | `ASC_*` | CI + local |
| Apple rating summary | `itunes.apple.com/lookup` | none | anywhere |
| Apple downloads, daily | ASC `salesReports` (gzipped TSV) | `ASC_*` + vendor no. | ⚠ see below |
| Apple field metrics (launch, hangs, memory) | ASC `perfPowerMetrics` | `ASC_*` | CI + local |
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
| Search clicks, queries, sitemaps | Search Console API (`health.searchConsole`) | Google | CI |
| Watch Together rooms / guests / YouTube shows | our Worker's anonymous tally + Cloud API usage (`health.together`) | — | CI |

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
* **A workflow that declares `cancel-in-progress` asks to be superseded.** The
  fleet auditor reported Deploy Pages as `KILLED` — an urgent severity that
  raises an issue — for doing exactly what its own concurrency block tells it to
  do. It now reads that flag out of the workflow file rather than keeping a list
  of exempt names, and imports pyyaml LAZILY: this tool had no third-party
  dependency, Pulse shells out to it, and failing to start over a convenience
  would be a worse fault than the false alert it prevents.
* **The viewer's service worker was serving the dashboard from cache.** It is
  registered at root scope, so it intercepts everything under archivewatch.org
  that is not explicitly excluded — and `/pulse` was not. The page showed
  yesterday's panels beside today's timestamp, which is the exact failure this
  tool exists to prevent, arriving from the cache instead of from a reader.
  `/pulse` and `/ops/` now bypass it the way `/curate` already did, and
  `tools/test_sw_bypass.mjs` asserts both halves: the ops tools are never
  cached AND the viewer still is, because a bypass that swallows the whole site
  would break the PWA offline.
* **A secret that exists and never arrives looks exactly like one that was
  never made.** The reports key was set correctly and `pulse.yml` did not pass
  it, so the run stayed green and the panel stayed empty.
  `tools/test_pulse_collect.py` now reads every `os.environ` name out of the
  collector and asserts the workflow carries it.
* **App Manager is not a reporting role, and a key cannot be widened.** The
  natural assumption — that the key which ships builds can also read how many
  people installed them — is wrong twice over. Apple's role descriptions put
  report download under Finance, Sales, Admin and Account Holder; App Manager is
  "pricing, App Store information, and app development and delivery". And the
  key page says a key *"can't be modified to access more services once
  created"*, which its own UI confirms: **Edit offers only Revoke Key**, with no
  way to change roles. Measured, not assumed — the App Manager key answers
  `403 … The API key in use does not allow this request` while succeeding on
  customer reviews, versions and performance metrics with the same credential.
  Community reports of Admin keys also 403ing on this endpoint turn out to be a
  different fault (a missing or expired agreement); both of ours are Active, and
  the vendor number is confirmed on the Payments page, so neither applies here.
* **A Play metric set advertises the window it holds.** Querying past its
  `freshnessInfo.DAILY.latestEndTime` is a `400` that reads like a malformed
  request. Ask, then query to that date — never guess at "today".
* **Two ASC endpoints do not speak JSON, and say so as a 406.** `salesReports`
  wants `Accept: application/a-gzip` and `perfPowerMetrics` wants
  `application/vnd.apple.xcode-metrics+json`; through `asc_release.call`, which
  sets `Accept: application/json`, both answer `406 NOT_ACCEPTABLE` — which
  reads exactly like a permission problem and is not one.
* **`analyticsReportRequests` answers 403 for this key.** The newer Analytics
  Reports API needs an API key with a role that has report access; the sales
  report above covers the same ground for downloads.
* **X, Pinterest, Letterboxd, Tumblr, Discord** were researched for the social
  programme and rejected for cost or access; see `docs/SOCIAL-SETUP.md` §6. None
  is readable here either.

---

## Owner steps (each unlocks a panel that currently says "could not read")

~~`PLAY_SERVICE_ACCOUNT_JSON` as a repo secret~~ — **done 2026-09-09**, set from
   `~/.config/play/archivewatch-play.json` with `gh secret set`. The collector
   accepts either a path or the JSON itself.
~~Downloads need a SECOND API key.~~ — **done 2026-09-09.** Key `3F84BHSMRC`,
   role **Sales and Reports** and nothing else, wired as `ASC_REPORTS_KEY_ID` /
   `ASC_REPORTS_KEY_P8` by `tools/set_reports_key.sh`. First read: **334
   first-time installs over 14 days.** The original note, kept because the
   reasoning still binds: The vendor number (`85339427`) is set.
   What is missing is a key with the **Sales and Reports** role: App Store
   Connect states on its own key page that a key *"can't be modified to access
   more services once created"*, so the release key (App Manager) can never gain
   it — and widening the key that ships builds so a dashboard can read a
   download count is the wrong trade. Generate a second key that can do nothing
   else, then run `tools/set_reports_key.sh ~/Downloads/AuthKey_XXXX.p8`; it
   sets both secrets, verifies the key against a real report, and never prints
   it. Apple offers the `.p8` **once** — which is why generating it is the
   owner's step and not the agent's.
~~Enable the Play Developer Reporting API~~ — **done 2026-09-09**,
   `gcloud services enable playdeveloperreporting.googleapis.com --project
   archivewatch-play`. It immediately returned **10 crash clusters**, including a
   `CatalogDatabase.queryRaw` SQLException affecting 7 users. Play withholds the
   crash and ANR *rates* below a minimum audience, which is a real answer about
   the app's size and is reported as one.
4. **YouTube stats and comments need `youtube.readonly`.** The programme's token
   holds `youtube.upload` and nothing else, which
   `tools/youtube_refresh_token.py` argues for in as many words — a secret in CI
   that can post but cannot read the account. Pulse reports that as a choice, not
   a fault. Note the same limit means **`social_metrics.py` cannot read YouTube
   view counts either**; if those numbers are wanted, re-mint the token with
   `youtube.readonly` added and accept the wider secret.
5. **`FB_PAGE_ID` + `FB_PAGE_ACCESS_TOKEN`** are referenced by `social-post.yml`
   and are **not in the repo's secrets** — Facebook has never actually been
   connected, the same way Mastodon once was not.
6. **Keep `ops/stores-manual.json` current.** Amazon, Roku, LG and Samsung have no
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

### Needs attention / Going well (binding, 2026-09-25)

The Overview opens on two columns — **Needs attention** and **Going well** —
which replace the old ticker and "Needs you". On a phone they stack, Needs
first. Each item is one line: a sentence, a number, its comparison, and its
period, with a state rule down the left edge — **red** = decide, **amber** =
watch, **teal** = good (rule 3's colors). Clicking an item opens its drawer.
Each column shows six and then "N more"; an empty column says so in words.

Every item comes from ONE `RULES` table in `pulse.js` — a rule names the JSON
path it reads, its threshold, and its tier, so a new signal is a new row, not
a new branch of rendering code:

| Rule | Reads | Threshold | Tier |
|---|---|---|---|
| Live crash cluster, no fix recorded | `health.playCrashes[]` | not `stale` | decide |
| Fix in the repo, not released | `playCrashes[].fixedIn.versionCode` | above the Play production versionCode and any in-flight one | decide |
| Fix in review | `playCrashes[].fixedIn.versionCode` | at or below the in-flight versionCode | watch |
| Unreplied low review | `reviews[]` | ≤ 3★, not responded, last 60 days | decide |
| Store rejected | `stores[].state` | REJECT / REMOVED / INVALID | decide |
| Workflow broken or killed | `health.workflows[]` | BROKEN, KILLED | decide |
| Workflow failed | `health.workflows[]` | any other severity | watch |
| Request waiting | `asks[]` | any | watch |
| Play rating low | `health.playDaily.ratings[-1].total` | < 4 | watch |
| Roku crash share | `health.rokuEngagement.headline["Channel Crashes as % of Total Devices Streaming"]` | > 2 | decide |
| Usage fell | every usage series (below) | ≥ 30% down week over week, prior week ≥ 10 | watch |
| Sitemap errors | `health.searchConsole.sitemaps[].errors` | > 0 | decide |
| Stale reader | `stale`, `sources[].at`, each series' last date | older than 36 h / its lag | watch |
| Newer build waiting | `stores[].inFlight` | present | watch |
| Usage rose | every usage series | ≥ 30% up week over week, this week ≥ 10 | good |
| New praise | `reviews[]` 5★, `loves[]` | last 14 days | good |
| Crash clusters cleared | `playCrashes[]` | `stale` (not on the live build) | good |
| Store went live | `stores[].since` | live, within 14 days | good |
| Catalog grew | `history[].catalogItems` | up vs 7 days ago | good |
| Every reader answered | `sources` | all ok | good |
| Film-page faults | `searchIndex.faults[]` | any sampled film page with a redirect, a noindex, or Google choosing a different canonical — ours to fix | decide |
| Film pages indexed rose | `history[].filmPagesIndexed` | the sampled indexed share up 5 points or more over 7 days | good |
| New top-10 queries | `searchConsole.queries[]` | position ≤ 10, no impressions in the prior 28 days, and only once `prev28` has impressions — ONE line for all of them, led by the most-clicked (a new property made all 85 queries "new") | good |

The usage series are Apple downloads, Android store-listing acquisitions,
Android installs, Fire TV installs, Roku installs, website visits, web plays,
Search clicks and impressions, and Watch Together rooms. Week over week means
the last seven COMPLETE days of a series against the seven before; a series
whose newest day is older than its lag is reported as stale rather than
compared, because a week that is really three weeks ago is not "this week".

**Fixed-in** (`ops/fixed-in.json`, read into `playCrashes[].fixedIn`): its
Android `versionCode` is compared to the Play production versionCode
(`health.playLiveBuild`, else the Production row's `live` build) — at or below
it reads *shipped, clears as users update*; at or below the in-flight
versionCode, *fix in review*; otherwise *fix in repo, not released*. An entry
without a `versionCode` is shown as recorded and never compared: the Apple
build number is a different counter and says nothing about Android.

### The rest

* **Where we are shipping** — every store on one list, machine-read and declared
  side by side. A row says a newer build is waiting ONLY from its `inFlight`
  field (a release uploaded or in review but not yet live). It is never
  compared to `AppVersion.xcconfig`, which moves on every commit, so a
  comparison with it says "behind" about every store every day and means
  nothing. Each row opens a drawer: live version, what is in flight, and the
  history the store exposes.
* **Tabs** are grouped **Views** (Overview, Reach, Engagement, Health, Voice,
  Search, Ops), **Apps** (one per platform) and **Social** (Program, one per
  network), each row labeled and scrollable with a visible edge, so the tabs
  past the width of a phone are findable.
* **Search** — Google Search Console for `https://archivewatch.org/`
  (`health.searchConsole`): clicks and impressions by day, CTR, average
  position (lower is better), queries, pages, countries and devices against the
  prior 28 days, rising and falling queries, and sitemap health. Search Console
  runs two to three days behind; its panels carry *as of* only past four.
* **Watch Together** (Engagement; `health.together`) — rooms and guests a day
  from our Worker's anonymous tally, and `lives`: YouTube broadcasts the app
  created, read from Google Cloud's API usage. Twitch and own-stream-key shows
  are not counted, and the drawer says so. No film is recorded. Any field may
  be absent; only what exists is drawn, and an absent block reads *not
  collected yet* — never a zero.
* **Web titles** are shown as TITLES, resolved from `/catalog-index.json`,
  which is loaded only when a titles surface opens (it is ~6 MB). An id the
  index does not carry is shown as the id, marked *not in the catalog index* —
  usually a title the rights audit hid, which is itself worth knowing.
* **What people said** — reviews and mentions in one reading list, newest first.
  A sentence detected as a request is marked with an orange rule down its left.
* **Over time** — fills in from the second day. One reading per day, forever.
* **Where this came from** — which readers answered, and why the others did not.
  Read this panel before believing a zero anywhere else on the page.
