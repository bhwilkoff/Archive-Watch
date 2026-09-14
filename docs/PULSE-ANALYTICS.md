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
