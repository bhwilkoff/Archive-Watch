# Pulse analytics — the binding design

Supersedes nothing; extends `docs/PULSE.md` (Decision 108), whose rules still
bind: **a reader that cannot read SAYS SO and never a zero**, history rows are
scalar-only, and a request is quoted rather than summarised.

Owner, 2026-09-14: *"see more detailed analytics (individual charts built from
daily data syncs), separate info per platform, and better granularity for each
data set … Social Media should not be combined with usage metrics."*

---

## 1. One dashboard per QUESTION, because that is what a dashboard is

Stephen Few's definition is a display of the information needed to achieve **one
or more objectives**, on a single screen, monitored at a glance — and the
literature splits dashboards by AUDIENCE: strategic (at a glance, no controls),
analytical (filters, drill-down, layered), operational (now, act now). A page
that mixes them serves none of them.

Pulse today is one page doing all three at once, which is why the owner's
instruction is about SEPARATION rather than about more numbers. So Pulse becomes
a small set of views, each answering one question:

| View | Question | Type |
|---|---|---|
| **Overview** | Is anything wrong or asking for me? | strategic |
| **Reach** | Who is installing, where, on what? | analytical |
| **Engagement** | Who is coming back, and to what? | analytical |
| **Health** | What is broken, on which platform and build? | operational |
| **Voice** | What are people SAYING? (reviews, mentions, asks) | analytical |
| **Programme** | What did we post, and did it land? | analytical |
| **Ops** | Is the machinery that feeds all of this alive? | operational |

**Programme is a separate view, not a panel.** Posting cadence and install
counts answer different questions for different reasons, and putting them side
by side invites a causal reading neither one supports.

## 2. Granularity is a platform's OWN, never an invented common denominator

Every platform exposes a different shape. Flattening them to a shared schema
would throw away exactly the detail the owner asked for. So each platform panel
renders what that platform actually gives, and says what it does not:

| Platform | Installs | Dimensions | Engagement | Health | Route |
|---|---|---|---|---|---|
| Apple (tvOS/iOS/macOS) | daily | country, device, version | — | perf metrics | `salesReports` (gzip TSV) |
| Google Play | daily | country, device, OS, language, version | active devices, acquisition funnel | crash/ANR clusters | API + GCS CSVs |
| **Amazon Fire TV** | **daily, per transaction** | **country** | — | crash/ANR (empty so far) | **Sales Reporting API** |
| Web | daily views/visits | path | — | — | D1 beacon |
| **Roku** | **daily, once wired** | per the Looker report | visits, streaming | crashes, buffering | **scheduled delivery** |
| LG / Samsung | none | — | — | — | hand-declared |

## 3. The two routes that were thought impossible, and are not

### 3a. Amazon installs are in the SALES report (corrects Decision 111)

Decision 111 recorded "Unit sales are console-only and stay hand-declared". That
is wrong, and the reason it looked true is that the obvious path does not exist:

    /api/appstore/download/report/acquisition/2026/09
      -> 400 "Unable to fetch the request scope for uri"   = NO SUCH ROUTE

    /api/appstore/download/report/sales/2026/09
      -> 200, a 5-minute presigned S3 URL to a CSV zip     = THE DATA

**For a free app every install is a $0.00 `Charge` row**, carrying
`Transaction Time`, `Country/Region Code`, ASIN and SKU. Measured on the first
live pull: 30 rows for September, `US 26 · GB 1 · JP 1 · AU 1 · CA 1`, and by
day `1, 1, 11, 6, 8, 2, 1` — where the 11 lands on **2026-09-10**, the day
Decision 115's minSdk fix took Fire TV device coverage from 38 to 91. The
acquisition curve independently confirms that release.

Note the two DIFFERENT 400s, which is the discriminator Decision 111 established
and which now has a second use: *"Report not found"* means the route is real and
holds no data for that period; *"Unable to fetch the request scope"* means there
is no such route. Never treat them as the same failure.

### 3b. Roku delivers to a WEBHOOK, and we already run the endpoint

Roku's dashboards are **Looker**. There is no analytics API and there will not
be one. But Looker scheduled delivery targets email, **webhook**, S3 and SFTP,
at cadences down to hourly, in CSV.

S3 is out: Looker's S3 form takes bucket/region/keys with **no custom-endpoint
field**, so it resolves to real AWS — and this is a $0 platform (owner,
2026-09-14: *"pennies a month still does not fit"*). R2 cannot be substituted.

The webhook target costs nothing because **the endpoint already exists**:
`archivewatch-pulse`, the Cloudflare Worker that already serves `/beacon` and
`/views` for web usage, backed by a free-tier D1 database. It gains one
endpoint that stores a delivery RAW, and one that hands it over and deletes it.

**Store the payload raw and parse it offline.** Looker's webhook body shape is
not documented anywhere reachable, so the endpoint commits to nothing about it:
whatever arrives is kept verbatim, and the first real delivery is what teaches
us the format. An ingest that guesses a schema fails silently on the one
delivery that matters.

This does not breach the no-backend rule (Decision 028) or the no-server rule
(Decision 122). Those are about USER data — a playlist must never need a
database between it and its viewer. This holds no user data, sits in no user's
path, and is internal ops tooling on infrastructure this project already runs.

## 4. Daily series: fetch what the vendor backfills, ACCUMULATE what it does not

`history` stays scalar-per-day per Decision 108. It is not the chart source.

- Apple, Play and Amazon all return their OWN daily series with history, so a
  chart re-reads them and no accumulation is needed. Re-fetching is strictly
  better: a vendor restating yesterday corrects our copy.
- Web views live in D1 and are already a real series.
- Roku's delivered CSV is a snapshot, so those rows ACCUMULATE into D1 keyed by
  (day, metric), and a re-delivery of the same day overwrites rather than adds.

The rule: **never accumulate what the vendor will hand you again, and never
discard what it will not.**

## 5. Chart rules, inherited and unchanged

From `docs/PULSE.md` §How it LOOKS, which stays binding: position, then length,
then area, then colour; no pie, donut or bubble; colour is STATE, never
quantity; no gauges; zero is DRAWN and absence is WRITTEN. `pulse/charts.js` is
the hand-rolled inline-SVG kit — no library, no build step.

Two additions for this work:

- **Small multiples over one combined chart.** Five platforms' installs belong
  in five aligned panels sharing a scale, not five series in one frame: the
  comparison a reader wants is per-platform shape, and overlaying makes the
  smallest platform unreadable.
- **A dimension breakdown is a sorted bar, never a map or a pie.** Country,
  device and version are categorical; length on a common baseline is the
  encoding people read most accurately (Cleveland & McGill).

## 6. What this does NOT become

No per-user tracking, no cohorts, no funnels beyond what Play already computes,
no session recording, no third-party analytics SDK in any app. `privacy.html`
promises we never receive, see or store information about a viewer or how they
use the app, and everything here is a STORE-side or server-side aggregate the
vendor already holds. Nothing in this design changes what the apps collect,
which is nothing.

---

## 7. The drop box, as built (2026-09-14)

`archivewatch-pulse` gained three routes beside `/beacon` and `/views`:

    POST /ingest/<vendor>?t=<token>   store a delivery RAW
    GET  /drops?vendor=&t=<token>     read pending deliveries
    POST /drops?id=&t=<token>         ack — delete one, once ingested

`drops(id, vendor, received, content_type, bytes, body)` in the same free-tier
D1. Verified live with its negative controls FIRST: no token → 404, wrong token
→ 404, `/drops` unauthenticated → 404. Then an authenticated CSV drop stored,
read back with its content type and byte count, acked, and gone. `/views` still
answers, unchanged.

**404, not 403**, so an unauthenticated prober learns nothing about what lives
here. **A body over 900 000 bytes is REFUSED, not truncated** — D1 caps a row
near 1 MB, and half a report read as a whole one is the quiet wrong number this
dashboard exists to prevent; the response says `refused` and the row records
the byte count.

**A deploy is not live when wrangler says so.** The first test run reported
three passing negative controls that were nothing of the kind: the endpoint did
not exist yet, so every request fell through to the root handler and answered
200. The tell was the fallback body still listing only `/beacon, /views`. Poll
the root until it names the new routes before believing any result from them.

### Owner step to switch Roku on

In the Roku Developer Dashboard, open an analytics report → the ⋯ menu →
**Schedule Delivery** → destination **Webhook**, format **CSV**, cadence
**Daily**, URL:

    https://archivewatch-pulse.benwilkoff.workers.dev/ingest/roku?t=<PULSE_INGEST_TOKEN>

The token is at `~/.config/archivewatch/pulse-ingest.env` (mode 600), on the
Worker as the `INGEST_TOKEN` secret, and in the repo as `PULSE_INGEST_TOKEN`.
It is in no commit. The first delivery is what teaches us Looker's payload
shape, after which the parser gets written against a real body rather than a
guess.

---

## 8. Roku is LIVE (2026-09-14) — and the payload shape, measured

The owner saved the schedule and fired a test delivery. It arrived, and the
shape is now known rather than guessed:

    {"type": "dashboard",
     "scheduled_plan": {"scheduled_plan_id": "86213",
                        "title": "App Engagement", "type": "LookMLDashboard"},
     "attachment": {"mimetype": "application/zip;base64",
                    "extension": "zip",
                    "data": "<base64 of a zip of CSVs>"}}

**The CSV zip rides base64 INSIDE the JSON body** — 3,620 bytes for this
dashboard, comfortably under the 900 KB refusal. One CSV per dashboard TILE,
named after it, so the tile names are the schema. Nine tiles: new_installs,
uninstalls, cumulative_net_installs, install_base_growth,
channel_visitors_and_streaming_viewers, minutes_streamed,
average_daily_visitors, ave_minutes___visitor, total_hours_streamed.

Parsed to **10 metrics a day**:

| date | Installs | Uninstalls | Net | Visitors | Viewers | Bounce | Minutes |
|---|---|---|---|---|---|---|---|
| 2026-09-10 | 71 | 0 | 71 | 57 | 41 | 28.07% | 771 |
| 2026-09-11 | 21 | 0 | 21 | 33 | 16 | 51.5% | 321 |
| 2026-09-12 | 20 | 1 | 19 | 29 | 14 | 51.7% | 496 |

Two traps, both of which cost a round:

**A dry run CONSUMED the delivery.** The reader acked unconditionally, and the
drop box DELETES what it acks — so `--only roku_engagement` with no `--apply`
destroyed the only copy of the payload it was merely supposed to look at. It
survived because it had been saved by hand minutes earlier. The ack is now
gated on `--apply`, the run says `(dry run — left in the box)`, and the
property is asserted by running twice and reading the box back. *A dry run that
destroys data is not a dry run.*

**Cloudflare answers a bare `Python-urllib` request with 403**, which is NOT
the Worker's own 404-for-a-bad-token and reads exactly like an auth failure.
Send the collector's UA, as every other reader here does. Note the pair of
discriminators this project now has for "looks like a permissions problem and
isn't": Amazon's two different 400s (§3a) and this.

An unreadable payload is KEPT, never acked — a body we cannot parse is the only
evidence of the shape that broke us, and acking it would delete that.

---

## 9. Play installs were never broken — two lags, stacked (2026-09-14)

Pulse reported Play installs as ending **2026-08-21** while the Console showed
data every day, and this document plus two code comments called the export
"broken". That was wrong, and the way it was wrong is the point.

**Nothing was measured.** The claim came from the newest ROW in a CSV. A row
cannot tell you whether a file stopped being written, moved, was renamed, or is
simply behind — and those have different fixes, one of which is not a fix at
all. Only the OBJECT'S UPDATE TIME can tell them apart, and nobody had looked.

`tools/play_bucket_probe.py` looks. It runs in CI because the bucket id is a
secret, lists what is actually there, and dumps our own files. It found:

    installs_com.archivewatch.app_202609_overview.csv   written 2026-09-13 20:40
        9 lines: 2026-09-01 .. 2026-09-08   (29, 31, 28, 39, 26, ... , 6)
    installs_com.archivewatch.app_202609_country.csv    written 2026-09-13 20:40
        636 lines, every country, same dates
    installs_com.archivewatch.app_202608_*.csv          last written 2026-08-26
        data to 2026-08-21

**Two ordinary lags, stacked.** Play's install data runs about six days behind,
AND the current month's file does not appear until part-way through the month.
So on 2026-09-13 the newest file Pulse had ever seen was August's, whose final
write held data to 08-21. Pulse's own last run was 16:58 that day; September's
file landed at 20:40, three hours later. The reading was correct and normal.

Running the collector immediately after: **598 installs to 2026-09-08.**

**How to apply.** The alarm now fires past BOTH lags — more than fourteen days
with no newer row — and anything less is reported as "Play's normal reporting
lag" with the figure, because a dashboard that cries stale at six days teaches
its reader to ignore the word. And before ever calling a vendor export broken,
run the probe: a file's newest row is not evidence about the file.

**A green run that did nothing, again.** The probe's first run died on a
missing `requests` module and the job reported SUCCESS, because `| tee` makes
the step's status tee's rather than the command's. `set -o pipefail`. This is
Decisions 089 and 107 reintroduced by a convenience pipe, which is worth
knowing: the pattern does not only arrive in big machinery.

---

## 10. The seven views, built (2026-09-14)

§1 specified one view per QUESTION and the page had three. It now has seven,
and `VIEWS` is one list that both the tab strip and the router read — because
the first time they disagreed, the Program tab looked dead: the click switched
the view, set the hash, and the hashchange handler validated that hash against
the PLATFORM list and switched it straight back.

| View | Question | Panels |
|---|---|---|
| Overview | anything wrong or asking for me? | the estate, catalog, enjoying vs asking |
| Reach | who is installing, where, on what? | who is installing (9 platforms), Apple downloads, Android installs |
| Engagement | who came back, and to what? | what people watch, website visits, Roku viewing, Android active devices |
| Health | what is broken, which build? | Android vitals, Apple field metrics |
| Voice | what did people SAY? | rating, review distribution, mentions, every review in full |
| Program | what did we post, did it land? | followers, posts published, the ledger |
| Ops | is the machinery alive? | workflow fleet, repository, every reader's status |

**What the split found.** "Followers" and "Posts published" were sitting in the
Overview tiles — programme output on a usage page, which is the exact mixing
the owner asked to end and which splitting the SECTION had not fixed. Moving
the section without moving the panels is a half-measure that looks complete.

**Engagement units are never combined.** An active Play device, a Roku visitor
and a website visit are three different things, and a single "engaged users"
number would be one no vendor could confirm. Each platform answers the part it
can, labelled with what it is measuring — and Roku is the only store that
reports WATCHING rather than installing, which is worth knowing when reading
it beside the others.

**A scoping bug worth the line.** Routing panels by a regex on their `k:` label
reached inside `titlesPanel()`, which takes its container as a PARAMETER, and
replaced it with a helper that is local to `glance()`. The page died with "B is
not defined" — reported to the reader as *"Could not load the readings"*,
because the fetch chain's own `.catch()` treats every error the same. That is
the second time in one day a code bug wore a data failure's clothes there. When
a rewrite is mechanical, check what else matches the pattern.

## 11. Three new routes, and when a reading happens (2026-09-25)

Owner: *"make updates to those processes to ensure that the latest and
greatest data are always live on the page ... Another data source that I would
like to add is the Google Search Console ... We should also figure out a way to
track how many rooms are being opened or streams that are being started with
the app if that is possible to do anonymously within our privacy framework."*

**All three new readers use the Pulse robot** (`archivewatch-ci@archivewatch-play`,
the Play service account, `_google()` in `pulse_collect.py`), and every grant it
holds is read-only and was made by the owner's word on 2026-09-25:

| Reader | Route | Grant | Gotcha |
|---|---|---|---|
| `search_console` -> `health.searchConsole` | Search Console API `searchAnalytics.query` + `sitemaps.list` on `https://archivewatch.org/` | **Restricted** user on the property; Search Console API enabled on `archivewatch-play` | Data is `final` only and lags 2-3 days, so `through` is Google's newest finished day and every comparison is 28 days to `through` vs the 28 before. The property's data begins 2026-09-20. No sitemap had ever been submitted when this was built. |
| `together_rooms` -> `health.together.roomsDaily` | our Worker, `GET /rooms-daily` | none (public aggregate, like `/views`) | The tally (`together_days`: day, kind, count) began 2026-09-25 and holds **no film** (owner's choice), no code, token or address. A deploy reaches Cloudflare's servers over a few seconds; a request in that window runs the old code. |
| `youtube_usage` -> `health.together.youtubeDaily` / `youtubeByMethod` | Cloud Monitoring `serviceruntime.googleapis.com/api/request_count`, `consumed_api`, service `youtube.googleapis.com`, on project **`archive-watch`** (the OAuth client's project) | **Monitoring Viewer** + **Service Usage Consumer** on `archive-watch` | Google serves these metrics only when the read is BILLED to a project with billing, so the request carries `x-goog-user-project: archive-watch` (billing linked, reads free at this volume). Without the header it answers "requires billing" for the robot's own project. |

**A broadcast is a successful `liveBroadcasts.insert`** — the one call every
signed-in go-live makes once. So Twitch and own-stream-key shows are not
counted and cannot be, and the page says so. This is NOT telemetry: it is
Google's count of the calls our OAuth client made; the apps send us nothing,
which is what privacy.html promises. An app-side "went live" ping was offered
and declined for exactly that reason (Decision 142).

**Quota is on the same reading** (Decision 136): each day's calls are priced
from Google's quota table (`_YT_UNITS`; chat reads 5, writes 50, lists 1)
against the 10,000 units the whole app shares. The first reading found
**9,765 units on 2026-09-23**, 71% of it live-chat reads — one heavy test day
from the ceiling.

**When a reading happens.** Twice a day by cron (08:17 and 20:17 UTC, which
GitHub runs 4-5 h late: ~06:30 and ~18:30 MT), plus a store-only re-read
(`--only apple_stores,play_stores,amazon_live,roku_engagement,manual_stores,play_crashes`)
when `Play release` or `App Store submit (cloud)` finishes, and when
`tools/play_promote.py` or `tools/submit-amazon.py` succeeds locally. A
release is on the page within minutes, not the next morning.

**Store rows read before they declare.** Play reads every release on a track
(live = completed, `inFlight` = the other), Apple rows carry `inFlight`,
Amazon's version is the submission API's live versionCode and Roku's is the
newest version seen in Roku's own delivery. "Behind the repo" is gone: the
repo's version moves on every commit, so it was true of every row within an
hour. `ops/fixed-in.json` carries the Android `versionCode` of each fix, so a
crash is judged against Android builds rather than an Apple build number.
