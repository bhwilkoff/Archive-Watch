# Metadata Quality Program

**Goal:** the world's best way to browse public-domain film — which means every
field the app shows (title, year, runtime, synopsis, cast, director, genres,
poster/backdrop, episode text) is *clean* (no junk a user would never want to
read) and *complete* (no conspicuous gaps), across 30k+ items and growing.

You can't hand-review 30k items. This is a **tiered, popularity-weighted,
self-healing** program: cheap deterministic passes clean the bulk on every
build; authoritative sources fill gaps on a schedule; and an LLM handles the
semantic long tail, prioritized by what users actually see. Research backs the
hybrid: running everything through an LLM costs 60–70% more than rules-first with
LLM only on the residue.

## The evidence (2026-06-04 baseline, `audit_metadata.py`)
29,968 non-series items. Avg score 75/100, 36% "clean", **27% had a visible
"blocker"** (junk in shown text). The breakdown drove the design:
- **Structural junk** (the user's "follow on Instagram / garbled HTML"): 6,193
  synopses with URLs, 1,699 HTML, 961 social/donate, plus email, mojibake,
  uploader/encoding boilerplate; 814 bracketed titles, 408 codec-string titles,
  594 ALL-CAPS. → **Tier 1** (rules).
- **Gaps**: 46% no real poster, 16k no cast, 13.7k no director, 10k no genres,
  3k no year. → **Tier 2** (enrichment).
- **Semantic** junk rules can't see: a synopsis that reads fine but describes the
  *upload* ("sourced from an early vinyl recording…"), not the film; a plausible
  but wrong description. → **Tier 3** (LLM).

After Tier 1 shipped, items-with-a-blocker fell 27% → ~0% and avg score 75 → 83.

## Tier 0 — Measurement (`tools/audit_metadata.py`)
Read-only. Scans every displayed field, classifies each problem as
BLOCKER / GAP / MINOR, scores each item 0–100, and reports counts **both overall
and within the top-N-by-popularity cohort** (Home/seed/search lead) so the long
tail never hides problems on the titles people see. Runs in CI → a quality
dashboard + trend line. *What it detects is exactly what Tier 1 cleans* — the
detectors are shared (`audit_metadata` regexes imported by `remediate_catalog`).

## Tier 1 — Deterministic cleaning (`tools/remediate_catalog.py`)
Runs on **every** catalog write (already in every CI writer + publish-db). Cheap,
idempotent, safe:
- **Synopsis**: decode entities, strip HTML/mojibake, drop whole sentences that
  are URL/social/email/uploader/encoding junk (keeps the plot). If nothing
  meaningful survives → null it (so Tier 2 refills a real one).
- **Title**: strip codec/resolution/bracket junk, fix mojibake, de-shout
  ALL-CAPS; never empties the title.
- Plus the existing year/silent/animation/adult/wrong-match/rights fixes.

## Tier 2 — Authoritative enrichment (existing curation workflows)
Fills gaps and replaces nulled junk from real sources, on schedule:
OMDb (cast/director/genres/plot), TMDb (posters/credits), Wikidata→Commons
(posters), Wikipedia (synopses), discovery (new items). Already wired
(`docs/autonomous-curation-loop.md`); Tier 1's nulling feeds it clean targets.

## Tier 3 — LLM semantic review (proposed; needs go-ahead)
The "world's best" lever, applied strategically — NOT all 30k blindly:
- **Prioritize by popularity** (and Home-eligibility): perfect the ~2–5k titles
  users actually see first; drain the tail over time.
- **Cheap-model triage** (e.g. Haiku) flags "this isn't a real synopsis / wrong
  film / low quality"; only flagged items escalate to a rewrite/refetch.
- **Cache by content hash** — never re-review unchanged text.
- **Budget-bounded** per run (N items), so cost is predictable and it drains
  like the other queues.
- Writes back a `synopsisSource="llm-reviewed"` + a quality flag; never
  invents facts (rewrite-from-source or flag-for-refetch, not hallucinate).

## Strategy for 30k (the prioritization)
1. **Rule-clean ALL** items every build (Tier 1) — free, removes structural junk.
2. **Perfect the visible cohort**: the top-by-popularity items (what Home, the
   bundled seed, and search surface) get enrichment + LLM first.
3. **Gate Home on quality**: only high-score items reach the marquee (extends the
   existing rights gate) so users see the best, while the tail keeps improving.
4. **Drain the tail** via scheduled Tier-2/Tier-3 runs; re-audit weekly to track
   the trend and catch regressions.

## Sustainability / cadence
- Tier 0 audit: weekly (report to the workflow summary) + on demand.
- Tier 1: every catalog write (automatic).
- Tier 2: daily/weekly (existing crons).
- Tier 3: scheduled, budget-bounded, popularity-ordered (once approved).
- A per-item quality score becomes a first-class field used for Home gating and
  "worst offenders" work-lists.
