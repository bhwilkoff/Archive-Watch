#!/usr/bin/env node
// Archive Watch — seed catalog builder.
//
// Multi-source cascade:
//   1. Wikidata P724 sweep (optional) — seed of films pre-matched to Archive IDs.
//   2. Shelves from featured.json — curated items + dynamic scrapes.
//      Dynamic shelves use cursor pagination so --max-per-shelf can go past 100.
//
// Per-item enrichment branches by content type:
//   • feature / silent / short / animation  → IMDb → TMDb /find → TMDb /search → Wikidata → Commons
//   • tv_series                             → Wikidata → TVmaze search by series name
//   • newsreel / ephemeral / documentary /  → Archive metadata as primary (rich description,
//     home_movie                              creator/publisher/sponsor), Commons category walk
//                                             for artwork. Skip TMDb entirely (won't match).
//
// Procedural posters: the app renders a typographic placeholder when posterURL is missing
// or when artworkSource === 'archive' and we know the thumb is just a first frame grab.
// We flag those items with hasRealArtwork=false so SwiftUI can branch.
//
// Usage:
//   node tools/build-catalog.mjs                            # default, current behavior
//   node tools/build-catalog.mjs --full                     # cursor paginate shelves, Wikidata seed, bigger output
//   node tools/build-catalog.mjs --seed-from-wikidata       # just add the Wikidata seed
//   node tools/build-catalog.mjs --max-per-shelf=500        # deep shelves
//   node tools/build-catalog.mjs --min-downloads=500        # quality floor
//
// Requires Node 18+.

import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, '..');

// ─── CLI ────────────────────────────────────────────────────────────

const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    if (!a.startsWith('--')) return [a, true];
    const [k, v] = a.slice(2).split('=');
    return [k, v === undefined ? true : v];
  })
);
if (args.help || args.h) {
  console.log(`Usage: node tools/build-catalog.mjs [flags]

Modes
  --full                  deep cursor-paginated shelves + Wikidata seed + Commons fallback
  --seed-from-wikidata    add Wikidata P724 seed to the existing shelf flow
  --no-tmdb               skip TMDb entirely (Archive + Wikidata + Commons only)

Tuning
  --per-shelf=N           default items per shelf (default 24)
  --max-per-shelf=N       cursor pagination cap per dynamic shelf (default 1000)
  --min-downloads=N       quality floor for dynamic-shelf items (default 0)
  --concurrency=N         parallel enrichment workers (default 3)
  --skip-broken=BOOL      drop items with no playable derivative (default true)

Output
  --out=PATH              output file (default catalog.json at repo root)
  --dry-run               resolve shelves + seed, skip enrichment
  --verbose               per-item log lines
`);
  process.exit(0);
}

const FULL            = !!args.full;
const PER_SHELF       = int(args['per-shelf'], 24);
const MAX_PER_SHELF   = int(args['max-per-shelf'], FULL ? 1000 : PER_SHELF);
const MIN_DOWNLOADS   = int(args['min-downloads'], 0);
const CONCURRENCY     = int(args.concurrency, 3);
const SKIP_BROKEN     = args['skip-broken'] !== 'false';
const USE_TMDB        = !args['no-tmdb'];
const USE_WIKIDATA_SEED = FULL || !!args['seed-from-wikidata'];
const SEED_LIMIT      = int(args['seed-limit'], 500);    // cap Wikidata seed items
const MAX_ITEMS       = int(args['max-items'], 0);       // 0 = no limit
const USE_COMMONS     = FULL;
const USE_TVMAZE      = true;
const OUT_PATH        = path.resolve(REPO_ROOT, String(args.out || 'catalog.json'));
const DRY_RUN         = !!args['dry-run'];
const VERBOSE         = !!args.verbose;

function int(v, d) { const n = parseInt(v, 10); return Number.isFinite(n) ? n : d; }

// ─── Inputs ─────────────────────────────────────────────────────────

const featured = JSON.parse(await fs.readFile(path.join(REPO_ROOT, 'featured.json'), 'utf8'));
const registry = await readJSON(path.join(REPO_ROOT, 'docs/taxonomy/collections.json'));
const tmdbToken = USE_TMDB
  ? (process.env.TMDB_BEARER_TOKEN || (await readXcconfig(path.join(REPO_ROOT, 'Secrets.xcconfig')))?.TMDB_BEARER_TOKEN || null)
  : null;

if (USE_TMDB && !tmdbToken) info('No TMDB_BEARER_TOKEN found. Running Archive+Wikidata only.');

async function readJSON(p) {
  try { return JSON.parse(await fs.readFile(p, 'utf8')); } catch { return null; }
}
async function readXcconfig(p) {
  try {
    const text = await fs.readFile(p, 'utf8');
    const out = {};
    for (const raw of text.split('\n')) {
      const line = raw.replace(/\/\/.*$/, '').trim();
      if (!line || line.startsWith('#')) continue;
      const m = line.match(/^([A-Z_][A-Z0-9_]*)\s*=\s*(.+)$/);
      if (m) out[m[1]] = m[2].trim();
    }
    return out;
  } catch { return null; }
}

// ─── Logging ────────────────────────────────────────────────────────

const isTTY = process.stderr.isTTY;
function info(msg) { process.stderr.write(`${dim('·')} ${msg}\n`); }
function ok(msg)   { process.stderr.write(`${green('✓')} ${msg}\n`); }
function warn(msg) { process.stderr.write(`${yellow('!')} ${msg}\n`); }
function fail(msg) { process.stderr.write(`${red('✗')} ${msg}\n`); }
function dim(s)    { return isTTY ? `\x1b[2m${s}\x1b[0m` : s; }
function green(s)  { return isTTY ? `\x1b[32m${s}\x1b[0m` : s; }
function yellow(s) { return isTTY ? `\x1b[33m${s}\x1b[0m` : s; }
function red(s)    { return isTTY ? `\x1b[31m${s}\x1b[0m` : s; }

// ─── Archive client ─────────────────────────────────────────────────

const UA = 'ArchiveWatch-CatalogBuilder/1.0 (https://github.com/bhwilkoff/Archive-Watch)';
const ARCHIVE_META   = 'https://archive.org/metadata/';
const ARCHIVE_SCRAPE = 'https://archive.org/services/search/v1/scrape';
const ARCHIVE_DL     = 'https://archive.org/download/';
const ARCHIVE_THUMB  = 'https://archive.org/services/img/';

async function archiveScrape({ q, sorts = [], count = 100, fields = ['identifier'], cursor = null }) {
  const params = new URLSearchParams();
  params.set('q', q);
  params.set('fields', fields.join(','));
  params.set('count', String(Math.max(count, 100)));
  if (sorts.length) params.set('sorts', sorts.map(normalizeSort).join(','));
  if (cursor) params.set('cursor', cursor);
  const res = await fetch(`${ARCHIVE_SCRAPE}?${params}`, { headers: { Accept: 'application/json', 'User-Agent': UA } });
  if (!res.ok) throw new Error(`scrape ${res.status}: ${await res.text().catch(() => '')}`);
  const data = await res.json();
  return { items: data.items || [], cursor: data.cursor || null };
}

async function archiveScrapeAll({ q, sorts = [], fields = ['identifier', 'downloads'], maxItems = 1000, minDownloads = 0 }) {
  const all = [];
  let cursor = null;
  while (all.length < maxItems) {
    const { items, cursor: next } = await archiveScrape({ q, sorts, count: 1000, fields, cursor });
    for (const it of items) {
      if (minDownloads && (it.downloads || 0) < minDownloads) continue;
      all.push(it);
      if (all.length >= maxItems) break;
    }
    if (!next || items.length === 0) break;
    cursor = next;
  }
  return all;
}

async function archiveMetadata(id) {
  const res = await fetch(`${ARCHIVE_META}${encodeURIComponent(id)}`, {
    headers: { Accept: 'application/json', 'User-Agent': UA }
  });
  if (res.status === 429) {
    const after = parseInt(res.headers.get('Retry-After') || '2', 10);
    await sleep(after * 1000);
    return archiveMetadata(id);
  }
  if (!res.ok) throw new Error(`metadata ${res.status} for "${id}"`);
  const data = await res.json();
  if (!data?.metadata || data.is_dark) throw new Error(`dark/empty item "${id}"`);
  return data;
}

function normalizeSort(s) {
  const t = String(s).trim();
  if (/\s+(asc|desc)$/i.test(t)) return t;
  if (t.startsWith('-')) return `${t.slice(1)} desc`;
  if (t.startsWith('+')) return `${t.slice(1)} asc`;
  return `${t} asc`;
}

// ─── Derivative picker (mirrors Swift + js/api.js) ──────────────────

const isDerivative = (f) => (f.source || '').toLowerCase() === 'derivative';
const isOriginal   = (f) => (f.source || '').toLowerCase() === 'original';
const isVideo      = (f) => /(mp4|h\.?264|mpeg-?4|ogg video|matroska|quicktime|avi|webm)/.test((f.format || '').toLowerCase());
const bySizeDesc   = (a, b) => (parseInt(b.size, 10) || 0) - (parseInt(a.size, 10) || 0);

function pickVideo(files) {
  const videos = (files || []).filter(isVideo);
  if (!videos.length) return null;
  const tiers = [
    (f) => isDerivative(f) && /h\.?264/i.test(f.format || ''),
    (f) => isDerivative(f) && /mp4/i.test(f.format || ''),
    (f) => isDerivative(f) && /512kb/i.test(f.format || '') && /mpeg4/i.test(f.format || ''),
    (f) => isDerivative(f) && /mpeg-?4/i.test(f.format || ''),
    (f) => isDerivative(f) && /(webm|matroska|ogg)/i.test(f.format || ''),
    (f) => isOriginal(f)   && /(mp4|h\.?264)/i.test(f.format || ''),
    (f) => isOriginal(f)
  ];
  for (let i = 0; i < tiers.length; i++) {
    const m = videos.filter(tiers[i]).sort(bySizeDesc)[0];
    if (m) return { name: m.name, format: m.format, sizeBytes: parseInt(m.size, 10) || 0, tier: i + 1 };
  }
  return null;
}

// ─── Archive metadata summariser ───────────────────────────────────

function oneOrMany(v) { return v == null ? [] : (Array.isArray(v) ? v : [v]); }
function firstString(v) { const arr = oneOrMany(v); return arr.length ? String(arr[0]) : null; }

function stripHTML(s) {
  if (!s) return s;
  // Strip tags, decode common entities, collapse whitespace.
  return String(s)
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p>/gi, '\n\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&mdash;/g, '—')
    .replace(/&ndash;/g, '–')
    .replace(/&hellip;/g, '…')
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(parseInt(n, 10)))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/[ \t]+/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

// Heuristic — is this item a trailer, not a film?
function looksLikeTrailer(title, subjects, runtimeSec) {
  const t = (title || '').toLowerCase();
  if (/\b(trailer|preview|teaser)\b/.test(t)) return true;
  for (const s of subjects || []) {
    if (/^trailer$|\btrailer\b/i.test(s)) return true;
  }
  // Sub-5-minute titles in feature_films are almost always trailers or
  // stray clips, not real films. We keep genuine shorts via collection
  // membership below.
  if (runtimeSec && runtimeSec > 0 && runtimeSec < 180) return true;
  return false;
}

function summarize(meta, fallbackID) {
  const m = meta.metadata || {};
  const files = meta.files || [];
  const collections = oneOrMany(m.collection);
  const subjects    = oneOrMany(m.subject);
  const externalIDs = oneOrMany(m['external-identifier']);

  const pick = (s) => { const n = parseInt(String(s || '').slice(0, 4), 10); return Number.isFinite(n) ? n : null; };
  const year = pick(m.year) ?? pick(m.date);

  let imdbID = null;
  let wikidataQID = null;
  for (const urn of externalIDs) {
    const s = String(urn).toLowerCase();
    if (!imdbID) imdbID = s.match(/tt\d{6,10}/)?.[0] || null;
    if (!wikidataQID) wikidataQID = s.match(/q\d{1,10}/)?.[0]?.toUpperCase() || null;
  }

  const vf = pickVideo(files);
  return {
    identifier: m.identifier || fallbackID,
    title: stripHTML(m.title) || m.identifier || fallbackID,
    year,
    runtime: m.runtime || null,
    mediatype: m.mediatype || null,
    collections,
    subjects,
    description: stripHTML(firstString(m.description)),
    creator: stripHTML(firstString(m.creator)),
    publisher: stripHTML(firstString(m.publisher)),
    sponsor: stripHTML(firstString(m.sponsor)),
    producer: stripHTML(firstString(m.producer)),
    contributor: stripHTML(firstString(m.contributor)),
    language: firstString(m.language),
    imdbID,
    wikidataQID,
    videoFile: vf,
    downloadURL: vf ? `${ARCHIVE_DL}${encodeURIComponent(m.identifier || fallbackID)}/${encodeURIComponent(vf.name)}` : null,
    thumbnailURL: `${ARCHIVE_THUMB}${encodeURIComponent(m.identifier || fallbackID)}`
  };
}

// ─── Description mining — zero-network cheap enrichment ─────────────

function mineDescription(text) {
  if (!text) return {};
  const out = {};
  const director = text.match(/Directed\s+by[:\s]+([^.\n,]+?)(?:[.,\n]|\s+and\s+|$)/i);
  if (director) out.director = director[1].trim().replace(/\s+/g, ' ');
  const starring = text.match(/(?:Starring|Cast|Featuring|With)[:\s]+([^.\n]{3,120}?)(?:[.\n]|$)/i);
  if (starring) {
    out.cast = starring[1]
      .split(/,\s*|\s+and\s+|\s*&\s*/)
      .map((s) => s.trim())
      .filter((s) => s.length >= 3 && /^[A-Z]/.test(s))
      .slice(0, 10);
  }
  const year = text.match(/\b((?:18|19|20)\d{2})\b/);
  if (year) out.yearHint = parseInt(year[1], 10);
  const runtime = text.match(/\b(\d{1,3})\s*min(?:ute)?s?\b/i);
  if (runtime) out.runtimeMinutesHint = parseInt(runtime[1], 10);
  return out;
}

// ─── TMDb ───────────────────────────────────────────────────────────

const TMDB_BASE = 'https://api.themoviedb.org/3';
const TMDB_IMG  = 'https://image.tmdb.org/t/p';
const TMDB_GENRE_MAP = {
  28: 'action', 16: 'animation', 35: 'comedy', 80: 'crime',
  99: 'documentary', 18: 'drama', 10751: 'family', 14: 'fantasy',
  27: 'horror', 10402: 'musical', 9648: 'mystery', 10749: 'romance',
  878: 'sci-fi', 53: 'thriller', 10752: 'war', 37: 'western'
};

let lastTmdb = 0;
async function tmdb(path, params = {}) {
  if (!tmdbToken) throw new Error('no TMDb token');
  const wait = 80 - (Date.now() - lastTmdb);
  if (wait > 0) await sleep(wait);
  lastTmdb = Date.now();
  const url = new URL(TMDB_BASE + path);
  for (const [k, v] of Object.entries(params)) if (v != null) url.searchParams.set(k, v);
  const res = await fetch(url, { headers: { Authorization: `Bearer ${tmdbToken}`, Accept: 'application/json' } });
  if (res.status === 429) {
    await sleep((parseInt(res.headers.get('Retry-After') || '1', 10)) * 1000);
    return tmdb(path, params);
  }
  if (!res.ok) throw new Error(`TMDb ${res.status} ${url.pathname}`);
  return res.json();
}

async function tmdbByIMDb(imdbID) {
  const r = await tmdb(`/find/${imdbID}`, { external_source: 'imdb_id', language: 'en-US' });
  return r.movie_results?.[0] || null;
}
async function tmdbDetail(id) {
  return tmdb(`/movie/${id}`, {
    language: 'en-US',
    append_to_response: 'credits,images,external_ids',
    include_image_language: 'en,null'
  });
}
async function tmdbSearch(title, year) {
  if (!title) return null;
  const p = { query: title, language: 'en-US', include_adult: false };
  if (year) p.year = year;
  const r = await tmdb('/search/movie', p);
  return r.results?.[0] || null;
}
// Dice coefficient on bigram sets — 0..1, 1.0 = identical.
function titleSimilarity(a, b) {
  const norm = (s) => String(s || '')
    .toLowerCase()
    .replace(/^(the|a|an)\s+/, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
  const A = norm(a), B = norm(b);
  if (!A || !B) return 0;
  if (A === B) return 1;
  const bigrams = (s) => {
    const g = new Map();
    for (let i = 0; i < s.length - 1; i++) {
      const k = s.slice(i, i + 2);
      g.set(k, (g.get(k) || 0) + 1);
    }
    return g;
  };
  const gA = bigrams(A), gB = bigrams(B);
  let overlap = 0;
  for (const [k, n] of gA) if (gB.has(k)) overlap += Math.min(n, gB.get(k));
  const total = [...gA.values()].reduce((a, b) => a + b, 0) +
                [...gB.values()].reduce((a, b) => a + b, 0);
  return total === 0 ? 0 : (2 * overlap) / total;
}

function pickBestImage(pool, prefLangs) {
  if (!pool?.length) return null;
  for (const lang of prefLangs) {
    const bucket = pool.filter((p) => p.iso_639_1 === lang);
    if (bucket.length) {
      return bucket.slice().sort((a, b) =>
        (b.vote_average || 0) - (a.vote_average || 0) ||
        (b.vote_count || 0) - (a.vote_count || 0))[0];
    }
  }
  return pool[0];
}

// ─── Wikidata ───────────────────────────────────────────────────────

const WIKIDATA_SPARQL = 'https://query.wikidata.org/sparql';
let lastWikidata = 0;
async function wikidataGet(query) {
  const wait = 1000 - (Date.now() - lastWikidata);
  if (wait > 0) await sleep(wait);
  lastWikidata = Date.now();
  const url = `${WIKIDATA_SPARQL}?query=${encodeURIComponent(query)}&format=json`;
  const res = await fetch(url, {
    headers: { Accept: 'application/sparql-results+json', 'User-Agent': UA }
  });
  if (res.status === 429) {
    await sleep((parseInt(res.headers.get('Retry-After') || '5', 10)) * 1000);
    return wikidataGet(query);
  }
  if (!res.ok) return null;
  return res.json().catch(() => null);
}

async function wikidataLookup(archiveID) {
  const safe = archiveID.replace(/"/g, '\\"');
  const q = `SELECT ?item ?imdb ?image WHERE {
  ?item wdt:P724 "${safe}" .
  OPTIONAL { ?item wdt:P345 ?imdb . }
  OPTIONAL { ?item wdt:P18 ?image . }
} LIMIT 1`;
  const data = await wikidataGet(q);
  const b = data?.results?.bindings?.[0];
  if (!b) return null;
  return {
    qid: b.item?.value?.split('/').pop() || null,
    imdbID: (b.imdb?.value || '').match(/tt\d{6,10}/)?.[0] || null,
    imageURL: b.image?.value ? commonsThumbURL(b.image.value, 780) : null
  };
}

async function wikidataSeedSweep() {
  info('Pulling Wikidata P724 seed (films with Archive.org ID)...');
  // Prioritize PD-flagged films, then films with an image, then the rest.
  // Cap via SEED_LIMIT to keep build time reasonable; a weekly --full run
  // with higher limits produces catalog-full.json.
  const q = `SELECT ?film ?filmLabel ?archiveId ?imdb ?image ?year ?pd WHERE {
  ?film wdt:P31/wdt:P279* wd:Q11424 .
  ?film wdt:P724 ?archiveId .
  OPTIONAL { ?film wdt:P345 ?imdb . }
  OPTIONAL { ?film wdt:P18 ?image . }
  OPTIONAL { ?film wdt:P577 ?date . BIND(YEAR(?date) AS ?year) }
  OPTIONAL { ?film wdt:P6216 ?pd . }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en" . }
}`;
  const data = await wikidataGet(q);
  if (!data) { warn('Wikidata seed query failed; continuing without.'); return new Map(); }

  const rows = [];
  for (const b of data.results?.bindings || []) {
    const archiveId = b.archiveId?.value;
    if (!archiveId) continue;
    rows.push({
      archiveId,
      qid: b.film?.value?.split('/').pop() || null,
      title: b.filmLabel?.value || null,
      year: b.year ? parseInt(b.year.value, 10) : null,
      imdbID: (b.imdb?.value || '').match(/tt\d{6,10}/)?.[0] || null,
      imageURL: b.image?.value ? commonsThumbURL(b.image.value, 780) : null,
      hasPD: !!b.pd?.value
    });
  }
  // Rank: PD-flagged > has image > has IMDb > newer year > rest.
  rows.sort((a, b) => {
    if (a.hasPD !== b.hasPD) return b.hasPD - a.hasPD;
    if (!!a.imageURL !== !!b.imageURL) return (!!b.imageURL) - (!!a.imageURL);
    if (!!a.imdbID !== !!b.imdbID) return (!!b.imdbID) - (!!a.imdbID);
    return (b.year || 0) - (a.year || 0);
  });

  const cap = SEED_LIMIT > 0 ? Math.min(SEED_LIMIT, rows.length) : rows.length;
  const map = new Map();
  for (const r of rows) {
    if (map.size >= cap) break;
    if (!map.has(r.archiveId)) map.set(r.archiveId, r);
  }
  ok(`Wikidata seed: ${map.size} films (from ${rows.length} total P724 rows)`);
  return map;
}

function commonsThumbURL(rawURL, width) {
  try {
    const u = new URL(rawURL);
    u.protocol = 'https:';
    u.searchParams.set('width', String(width));
    return u.toString();
  } catch { return rawURL; }
}

// ─── Wikimedia Commons — poster fallback via category + search ─────

async function commonsSearchFile(titleOrTerm) {
  if (!titleOrTerm) return null;
  const params = new URLSearchParams({
    action: 'query',
    format: 'json',
    generator: 'search',
    gsrsearch: `"${titleOrTerm}" poster`,
    gsrnamespace: '6',
    gsrlimit: '5',
    prop: 'imageinfo',
    iiprop: 'url',
    iiurlwidth: '780',
    origin: '*'
  });
  try {
    const res = await fetch(`https://commons.wikimedia.org/w/api.php?${params}`, {
      headers: { 'User-Agent': UA }
    });
    if (!res.ok) return null;
    const data = await res.json();
    const pages = data.query?.pages;
    if (!pages) return null;
    for (const page of Object.values(pages)) {
      const info = page.imageinfo?.[0];
      if (info?.thumburl || info?.url) return info.thumburl || info.url;
    }
  } catch { /* ignore */ }
  return null;
}

// ─── TVmaze — series-level TV enrichment ────────────────────────────

async function tvmazeSearch(name) {
  if (!name) return null;
  try {
    const res = await fetch(`https://api.tvmaze.com/singlesearch/shows?q=${encodeURIComponent(name)}`, {
      headers: { 'User-Agent': UA }
    });
    if (!res.ok) return null;
    const s = await res.json();
    return {
      name: s.name,
      year: s.premiered ? parseInt(s.premiered.slice(0, 4), 10) : null,
      synopsis: stripHTML(s.summary || ''),
      image: s.image?.original || s.image?.medium || null,
      genres: Array.isArray(s.genres) ? s.genres.map((g) => g.toLowerCase()) : [],
      network: s.network?.name || s.webChannel?.name || null,
      imdbID: s.externals?.imdb || null
    };
  } catch { return null; }
}

// ─── Classification ────────────────────────────────────────────────

function parseRuntimeSeconds(r) {
  if (!r) return null;
  const parts = String(r).split(':').map((s) => parseInt(s, 10));
  if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  if (parts.length === 2) return parts[0] * 60 + parts[1];
  if (parts.length === 1 && Number.isFinite(parts[0])) return parts[0];
  return null;
}
function decadeFromYear(y) { return y ? Math.floor(y / 10) * 10 : null; }

function dominantCategory(collectionsList) {
  if (!registry?.collections) return null;
  let best = null;
  for (const c of collectionsList) {
    const info = registry.collections[c.toLowerCase()];
    if (!info) continue;
    if (!best || info.weight > best.weight) best = info;
  }
  return best?.category || null;
}

function classifyContentType(collectionsList, subjects, runtimeSec, year) {
  const dom = dominantCategory(collectionsList);
  if (dom) return dom;
  const cols = collectionsList.map((c) => c.toLowerCase());
  if (cols.some((c) => c.includes('classic_tv')))                                return 'tv-series';
  if (cols.some((c) => c.includes('silent')))                                    return 'silent-film';
  if (cols.some((c) => c.includes('cartoon') || c.includes('animation')))        return 'animation';
  if (cols.some((c) => c.includes('prelinger') || c.includes('ephemeral')))      return 'ephemeral';
  if (cols.some((c) => c.includes('fedflix')))                                   return 'ephemeral';
  if (cols.some((c) => c.includes('newsreel') || c.includes('news-and-public'))) return 'newsreel';
  if (year && year < 1928) return 'silent-film';
  if (subjects.some((s) => s.toLowerCase().includes('documentary'))) return 'documentary';
  if (runtimeSec != null) {
    if (runtimeSec < 40 * 60) return 'short-film';
    if (runtimeSec > 55 * 60) return 'feature-film';
  }
  return 'feature-film';
}

function subjectToGenres(subjects) {
  const map = registry?.subjectKeywordMap;
  if (!map) return [];
  const out = new Set();
  for (const subject of subjects) {
    const s = String(subject).toLowerCase();
    for (const [kw, genre] of Object.entries(map)) {
      if (s.includes(kw)) { out.add(genre); break; }
    }
  }
  return [...out];
}

// ─── Enrichment dispatch ───────────────────────────────────────────

function baseItem(archiveID, s, runtimeSec, shelves, wdSeed) {
  return {
    archiveID: s.identifier,
    title: (wdSeed?.title) || s.title,
    year: s.year || wdSeed?.year || null,
    decade: decadeFromYear(s.year || wdSeed?.year),
    runtimeSeconds: runtimeSec,
    synopsis: s.description,
    collections: s.collections,
    subjects: s.subjects,
    mediatype: s.mediatype,
    language: s.language,
    imdbID: s.imdbID || wdSeed?.imdbID || null,
    tmdbID: null,
    wikidataQID: s.wikidataQID || wdSeed?.qid || null,
    tvmazeID: null,
    videoFile: s.videoFile,
    downloadURL: s.downloadURL,
    posterURL: wdSeed?.imageURL || s.thumbnailURL,
    backdropURL: null,
    hasRealArtwork: !!wdSeed?.imageURL,
    artworkSource: wdSeed?.imageURL ? 'wikidata' : 'archive',
    contentType: classifyContentType(s.collections, s.subjects, runtimeSec, s.year || wdSeed?.year),
    genres: subjectToGenres(s.subjects),
    countries: [],
    cast: [],
    director: null,
    producer: s.creator || s.publisher || s.sponsor || s.producer || null,
    seriesName: null,
    network: null,
    enrichmentTier: 'archiveOnly',
    shelves: [...shelves]
  };
}

async function enrichFeature(item, s) {
  // 1. Description regex — zero cost
  const mined = mineDescription(s.description);
  if (!item.director && mined.director) item.director = mined.director;
  if (mined.cast?.length && item.cast.length === 0) {
    item.cast = mined.cast.map((name, i) => ({ name, character: null, order: i, profilePath: null }));
  }

  // 2. Wikidata lookup if we still don't have an IMDb ID
  if (!item.imdbID) {
    const wd = await wikidataLookup(item.archiveID).catch(() => null);
    if (wd) {
      if (wd.qid && !item.wikidataQID) item.wikidataQID = wd.qid;
      if (wd.imdbID) item.imdbID = wd.imdbID;
      if (wd.imageURL && !item.hasRealArtwork) {
        item.posterURL = wd.imageURL;
        item.artworkSource = 'wikidata';
        item.hasRealArtwork = true;
      }
      if (item.imdbID || item.wikidataQID) item.enrichmentTier = 'identifierResolved';
    }
  }

  // 3. TMDb — /find by IMDb, fall back to /search by title+year
  if (USE_TMDB && tmdbToken) {
    let detail = null;
    if (item.imdbID) {
      try {
        const match = await tmdbByIMDb(item.imdbID);
        if (match?.id) detail = await tmdbDetail(match.id);
      } catch (e) { /* continue */ }
    }
    // Title+year fallback — STRICT: year ±1 AND fuzzy title match.
    // Titles <4 chars skipped to avoid matching "It"/"Go" style noise.
    if (!detail && item.title && item.year && item.title.length >= 4) {
      try {
        const match = await tmdbSearch(item.title, item.year);
        if (match?.id) {
          const tmdbYear = parseInt((match.release_date || '').slice(0, 4), 10);
          const yearOK = Number.isFinite(tmdbYear) && Math.abs(tmdbYear - item.year) <= 1;
          const titleOK = titleSimilarity(item.title, match.title) >= 0.75;
          if (yearOK && titleOK) detail = await tmdbDetail(match.id);
          else if (VERBOSE) warn(`${archiveID}: TMDb search rejected (${match.title} ${tmdbYear}; yearOK=${yearOK} titleOK=${titleOK})`);
        }
      } catch (e) { /* continue */ }
    }
    if (detail) {
      applyTMDb(item, detail);
      item.enrichmentTier = 'fullyEnriched';
    }
  }

  // 4. Commons poster fallback
  if (USE_COMMONS && !item.hasRealArtwork && item.title) {
    const img = await commonsSearchFile(item.title);
    if (img) {
      item.posterURL = img;
      item.artworkSource = 'commons';
      item.hasRealArtwork = true;
    }
  }
  return item;
}

async function enrichTV(item, s) {
  // Parse series name — Archive TV items are usually "Series Name Episode Title"
  // or just "Series Name Episodes".
  const name = extractSeriesName(item.title) || item.title;
  item.seriesName = name;

  if (!item.imdbID) {
    const wd = await wikidataLookup(item.archiveID).catch(() => null);
    if (wd) {
      if (wd.qid) item.wikidataQID = wd.qid;
      if (wd.imdbID) item.imdbID = wd.imdbID;
      if (wd.imageURL) {
        item.posterURL = wd.imageURL;
        item.artworkSource = 'wikidata';
        item.hasRealArtwork = true;
      }
      item.enrichmentTier = 'identifierResolved';
    }
  }

  if (USE_TVMAZE) {
    const tv = await tvmazeSearch(name);
    if (tv) {
      item.seriesName = tv.name;
      if (!item.year && tv.year) item.year = tv.year;
      if (tv.synopsis && (!item.synopsis || item.synopsis.length < tv.synopsis.length)) item.synopsis = tv.synopsis;
      if (tv.image && !item.hasRealArtwork) {
        item.posterURL = tv.image;
        item.artworkSource = 'tvmaze';
        item.hasRealArtwork = true;
      }
      if (tv.genres?.length && item.genres.length === 0) item.genres = tv.genres;
      if (tv.network) item.network = tv.network;
      if (tv.imdbID && !item.imdbID) item.imdbID = tv.imdbID;
      item.enrichmentTier = 'fullyEnriched';
    }
  }
  return item;
}

async function enrichEphemeral(item, s) {
  // Archive metadata IS the primary source for PSAs, gov films, industrial, ephemeral.
  // These have no TMDb match. Strong description + creator/sponsor + year.
  const mined = mineDescription(s.description);
  if (!item.director && mined.director) item.director = mined.director;

  // Wikidata — some famous PSAs ("Duck and Cover") have entries
  if (!item.imdbID) {
    const wd = await wikidataLookup(item.archiveID).catch(() => null);
    if (wd) {
      if (wd.qid) item.wikidataQID = wd.qid;
      if (wd.imdbID) item.imdbID = wd.imdbID;
      if (wd.imageURL) {
        item.posterURL = wd.imageURL;
        item.artworkSource = 'wikidata';
        item.hasRealArtwork = true;
      }
      item.enrichmentTier = 'identifierResolved';
    }
  }

  // Commons: search by title — "Don't Be a Sucker poster" etc.
  if (USE_COMMONS && !item.hasRealArtwork && item.title) {
    const img = await commonsSearchFile(item.title);
    if (img) {
      item.posterURL = img;
      item.artworkSource = 'commons';
      item.hasRealArtwork = true;
      item.enrichmentTier = 'identifierResolved';
    }
  }

  // Everything else stays from Archive metadata — producer, synopsis, year.
  // We mark this "archiveCurated" to signal it's intentionally Archive-only,
  // not an enrichment miss.
  if (item.enrichmentTier === 'archiveOnly' && item.synopsis && item.producer) {
    item.enrichmentTier = 'archiveCurated';
  }
  return item;
}

function extractSeriesName(title) {
  if (!title) return null;
  // Common patterns: "Series Name - Episode Title", "Series Name: Episode",
  // "Series Name (1955)", "Series Name Episodes", "Series Name Ep N"
  let s = title
    .replace(/\b(episodes?|complete\s+series|full\s+series|tv\s+show|public\s+domain)\b/gi, '')
    .replace(/\(\d{4}\)/g, '')
    .replace(/\s+-\s+.*$/, '')
    .replace(/:.+$/, '')
    .replace(/\s+ep\.?\s*\d+.*$/i, '')
    .replace(/\s+s\d+e\d+.*$/i, '')
    .trim();
  return s || null;
}

function applyTMDb(item, d) {
  item.tmdbID = d.id;
  if (d.title) item.title = d.title;
  if (d.overview) item.synopsis = d.overview;
  if (d.runtime) item.runtimeSeconds = d.runtime * 60;
  if (d.external_ids?.wikidata_id) item.wikidataQID = d.external_ids.wikidata_id;

  const bestPoster   = pickBestImage(d.images?.posters,   ['en', null]);
  const bestBackdrop = pickBestImage(d.images?.backdrops, [null, 'en']);
  const posterPath   = bestPoster?.file_path   || d.poster_path;
  const backdropPath = bestBackdrop?.file_path || d.backdrop_path;
  if (posterPath)   { item.posterURL = `${TMDB_IMG}/w780${posterPath}`; item.artworkSource = 'tmdb'; item.hasRealArtwork = true; }
  if (backdropPath) { item.backdropURL = `${TMDB_IMG}/w1280${backdropPath}`; }

  if (d.genres?.length) item.genres = [...new Set(d.genres.map((g) => TMDB_GENRE_MAP[g.id]).filter(Boolean))];
  if (d.production_countries?.length) item.countries = d.production_countries.map((c) => c.iso_3166_1);
  if (d.credits?.cast?.length) {
    item.cast = d.credits.cast
      .slice()
      .sort((a, b) => (a.order ?? 9999) - (b.order ?? 9999))
      .slice(0, 15)
      .map((c) => ({ name: c.name, character: c.character || null, order: c.order ?? 0, profilePath: c.profile_path || null }));
  }
  const director = d.credits?.crew?.find((c) => (c.job || '').toLowerCase() === 'director');
  if (director) item.director = director.name;
}

// ─── Per-item enrichment entry point ───────────────────────────────

async function enrichOne(archiveID, shelves, wdSeed) {
  const meta = await archiveMetadata(archiveID);
  const s = summarize(meta, archiveID);
  if (SKIP_BROKEN && !s.videoFile) {
    if (VERBOSE) warn(`${archiveID}: no playable derivative, skipping`);
    return null;
  }
  const runtimeSec = parseRuntimeSeconds(meta.metadata?.runtime);
  if (looksLikeTrailer(s.title, s.subjects, runtimeSec)) {
    if (VERBOSE) warn(`${archiveID}: looks like a trailer/preview, skipping`);
    return null;
  }
  const item = baseItem(archiveID, s, runtimeSec, shelves, wdSeed);

  const type = item.contentType;
  let out;
  if (type === 'tv-series' || type === 'tv-special') {
    out = await enrichTV(item, s);
  } else if (type === 'newsreel' || type === 'ephemeral' || type === 'documentary' || type === 'home-movie') {
    out = await enrichEphemeral(item, s);
  } else {
    out = await enrichFeature(item, s);
  }

  if (VERBOSE) {
    const tag = out.hasRealArtwork ? green('●') : yellow('○');
    info(`${tag} ${archiveID}  [${type}]  ${out.enrichmentTier}`);
  }
  return out;
}

// ─── Shelf resolution ───────────────────────────────────────────────

async function resolveShelves(wikidataSeed) {
  const byID = new Map();          // archiveID → { shelves: Set, wdSeed }
  const add = (id, shelfID, wdSeed = null) => {
    if (!id) return;
    if (!byID.has(id)) byID.set(id, { shelves: new Set(), wdSeed });
    byID.get(id).shelves.add(shelfID);
  };

  // Wikidata seed injection (--full or --seed-from-wikidata)
  if (wikidataSeed && wikidataSeed.size) {
    for (const [archiveID, seed] of wikidataSeed) {
      add(archiveID, 'wikidata-pd', seed);
    }
    info(`  wikidata-pd            ${String(wikidataSeed.size).padStart(4)} seeded`);
  }

  // featured.json shelves
  for (const shelf of featured.shelves || []) {
    if (shelf.type === 'curated' && Array.isArray(shelf.items)) {
      for (const it of shelf.items) add(it.archiveID, shelf.id);
      info(`  ${shelf.id.padEnd(22)} ${String(shelf.items.length).padStart(4)} curated`);
      continue;
    }
    if (shelf.type === 'dynamic' && shelf.query) {
      try {
        const items = await archiveScrapeAll({
          q: shelf.query,
          sorts: shelf.sort || ['-downloads'],
          fields: ['identifier', 'downloads'],
          maxItems: Math.min(shelf.limit || MAX_PER_SHELF, MAX_PER_SHELF),
          minDownloads: MIN_DOWNLOADS
        });
        for (const it of items) add(it.identifier, shelf.id);
        info(`  ${shelf.id.padEnd(22)} ${String(items.length).padStart(4)} dynamic (${(shelf.sort || ['-downloads'])[0]})`);
      } catch (e) {
        fail(`  ${shelf.id}: ${e.message}`);
      }
    }
  }
  return byID;
}

// ─── Concurrency pool with progress ────────────────────────────────

async function pool(items, workerCount, fn) {
  const queue = items.slice();
  const results = [];
  let done = 0;
  const total = queue.length;
  const tick = () => {
    if (!isTTY) return;
    const pct = Math.round((done / total) * 100);
    const bar = '█'.repeat(Math.floor(pct / 4)).padEnd(25, '·');
    process.stderr.write(`\r  ${bar} ${pct}%  ${done}/${total}   `);
  };
  const workers = Array.from({ length: workerCount }, async () => {
    while (queue.length) {
      const item = queue.shift();
      try {
        const r = await fn(item);
        if (r) results.push(r);
      } catch (e) {
        if (VERBOSE) fail(`${item.archiveID}: ${e.message}`);
      }
      done++;
      tick();
    }
  });
  await Promise.all(workers);
  if (isTTY) process.stderr.write('\n');
  return results;
}

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

// ─── Main ───────────────────────────────────────────────────────────

const t0 = Date.now();

const wdSeed = USE_WIKIDATA_SEED ? await wikidataSeedSweep() : null;

info(`Resolving shelves...`);
const picks = await resolveShelves(wdSeed);
ok(`${picks.size} unique Archive IDs to process`);

if (DRY_RUN) {
  info('Dry run — skipping enrichment.');
  for (const [id, { shelves }] of picks) {
    console.log(`${id}\t${[...shelves].join(',')}`);
  }
  process.exit(0);
}

info(`Enriching with ${CONCURRENCY} worker(s)${tmdbToken ? ' + TMDb' : ''}${USE_COMMONS ? ' + Commons' : ''}...`);
const jobs = [...picks.entries()].map(([archiveID, { shelves, wdSeed }]) => ({ archiveID, shelves, wdSeed }));
const items = await pool(jobs, CONCURRENCY, ({ archiveID, shelves, wdSeed }) => enrichOne(archiveID, shelves, wdSeed));

// Dedupe: multiple Archive uploads of the same film. Group by
// (normalized-title + year) and pick the best: prefer fully enriched,
// then items in more shelves, then highest IMDb/TMDb signal, then
// first seen. Merge shelves across duplicates so curation isn't lost.
function normTitleKey(t) {
  return String(t || '')
    .toLowerCase()
    .replace(/^(the|a|an)\s+/, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}
const TIER_SCORE = { fullyEnriched: 4, archiveCurated: 3, identifierResolved: 2, archiveOnly: 1 };
const dedupMap = new Map();
for (const item of items) {
  const key = `${normTitleKey(item.title)}|${item.year || ''}`;
  const existing = dedupMap.get(key);
  if (!existing) { dedupMap.set(key, item); continue; }
  // Merge shelves — we don't want to lose curation.
  existing.shelves = Array.from(new Set([...existing.shelves, ...item.shelves]));
  // Pick winner by tier → has poster → more shelves → has IMDb → bigger video.
  const score = (x) => {
    let s = (TIER_SCORE[x.enrichmentTier] || 0) * 1000;
    if (x.hasRealArtwork) s += 500;
    s += x.shelves.length * 10;
    if (x.imdbID) s += 50;
    if (x.tmdbID) s += 50;
    s += (x.videoFile?.sizeBytes || 0) / 1e9;
    return s;
  };
  if (score(item) > score(existing)) {
    item.shelves = existing.shelves;
    dedupMap.set(key, item);
  }
}
const dedupedCount = items.length - dedupMap.size;
if (dedupedCount > 0) info(`Deduped ${dedupedCount} duplicate uploads (${items.length} → ${dedupMap.size})`);
items.length = 0;
items.push(...dedupMap.values());

// Stats
const byType = {};
for (const i of items) byType[i.contentType] = (byType[i.contentType] || 0) + 1;

const stats = {
  totalItems:           items.length,
  itemsWithIMDb:        items.filter((i) => i.imdbID).length,
  itemsWithTMDb:        items.filter((i) => i.tmdbID).length,
  itemsWithWikidata:    items.filter((i) => i.wikidataQID).length,
  itemsWithTVmaze:      items.filter((i) => i.tvmazeID).length,
  itemsPosterTMDb:      items.filter((i) => i.artworkSource === 'tmdb').length,
  itemsPosterWikidata:  items.filter((i) => i.artworkSource === 'wikidata').length,
  itemsPosterCommons:   items.filter((i) => i.artworkSource === 'commons').length,
  itemsPosterTVmaze:    items.filter((i) => i.artworkSource === 'tvmaze').length,
  itemsPosterProcedural: items.filter((i) => !i.hasRealArtwork).length,
  itemsPlayable:        items.filter((i) => i.videoFile).length,
  fullyEnriched:        items.filter((i) => i.enrichmentTier === 'fullyEnriched').length,
  archiveCurated:       items.filter((i) => i.enrichmentTier === 'archiveCurated').length,
  identifierResolved:   items.filter((i) => i.enrichmentTier === 'identifierResolved').length,
  archiveOnly:          items.filter((i) => i.enrichmentTier === 'archiveOnly').length,
  byContentType:        byType
};

const catalog = {
  version: 2,
  generatedAt: new Date().toISOString(),
  generator: `tools/build-catalog.mjs${FULL ? ' --full' : ''}`,
  stats,
  items
};

await fs.writeFile(OUT_PATH, JSON.stringify(catalog, null, 2) + '\n');
const dt = ((Date.now() - t0) / 1000).toFixed(1);
ok(`Wrote ${path.relative(REPO_ROOT, OUT_PATH)} — ${stats.totalItems} items in ${dt}s`);
console.log(`  fully enriched    ${stats.fullyEnriched}`);
console.log(`  archive curated   ${stats.archiveCurated}   (Archive metadata is authoritative — PSA/gov/ephemeral)`);
console.log(`  id resolved       ${stats.identifierResolved}`);
console.log(`  archive only      ${stats.archiveOnly}`);
console.log(`  by type:`);
for (const [t, n] of Object.entries(byType).sort((a, b) => b[1] - a[1])) {
  console.log(`    ${t.padEnd(18)} ${n}`);
}
console.log(`  posters: TMDb ${stats.itemsPosterTMDb}  WD ${stats.itemsPosterWikidata}  Commons ${stats.itemsPosterCommons}  TVmaze ${stats.itemsPosterTVmaze}  Procedural ${stats.itemsPosterProcedural}`);
