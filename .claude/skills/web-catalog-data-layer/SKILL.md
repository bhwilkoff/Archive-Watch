---
name: web-catalog-data-layer
description: Use when touching the web viewer's data access (/watch/), adding a web feature that needs catalog data, or considering SQLite-over-HTTP for the browser. Captures the verified CORS/Range matrix and the shipped index + metadata-API pattern (Decision 029) so it isn't re-derived or violated.
---

# Web catalog data layer

## The verified host matrix (measured 2026-06-09 — re-verify only if a host changes)

| Host | Ranged GET | CORS for `fetch()` | Usable from browser JS? |
|---|---|---|---|
| GitHub Pages (`bhwilkoff.github.io`) | **206** | **yes `*`** | ✅ the only fetchable catalog host |
| GitHub Release assets | 206 | none | ❌ (native apps only) |
| `archive.org/download/*` (storage nodes) | 206 | none | ❌ for fetch; ✅ for `<img>`/`<video>` (elements skip CORS) |
| `archive.org/metadata/*`, scrape API | — | yes `*` | ✅ |

Pitfall that created this skill: a 2026-06-02 measurement said Pages "doesn't
do 206" — it was a **HEAD-request artifact**. Range works on GET.

## The shipped pattern (Decision 029, WEB-DESIGN §2)

- Browse/search: `catalog-index.json` (Pages, ~2.9 MB, popularity-sorted
  tuples `[id, title, year, contentType, poster]`, schema 2 — handle 4-field
  schema-1 rows; built by `tools/build_catalog_index.py`).
- Shelves: `featured.json` curated → index lookup; dynamic → Archive scrape
  API via `js/api.js`, sessionStorage-cached 1h.
- Detail/playback: `archive.org/metadata/{id}` via `js/api.js`
  (`API.fetchMetadata` + `API.summarize` picks the playable derivative —
  keep in sync with Swift `DerivativePicker`).
- Posters: index poster column → `archive.org/services/img/{id}` fallback.
- Never `fetch()` Release assets or `archive.org/download/*` from the
  browser. Never commit a SQLite to git for Pages (Decision 018).

## The upgrade path (when FTS5 / enriched detail / Channels reach web)

Chunked slim `catalog.sqlite` deployed to Pages **via GitHub Actions**
(`actions/upload-pages-artifact` — nothing committed), queried with
`sql.js-httpvfs` + OPFS cache. Requires the owner to flip Settings → Pages →
Source: GitHub Actions and a deploy job in `publish-db.yml`. Until that
lands, the index is the only catalog the browser loads.
