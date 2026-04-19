#!/usr/bin/env node
// Builds a compact (title, year) → IMDb tconst index from IMDb's
// non-commercial title.basics.tsv.gz dump. The dump is ~220 MB; the
// resulting index is ~30-50 MB of sharded JSON.
//
// IMDb's license explicitly permits personal/non-commercial use of
// their datasets (imdb.com/interfaces). We ship a derived index of
// factual (title, year, tconst) triples — no re-publication of their
// full dataset.
//
// Output format (one file per first letter, 0-9, _other):
//   data/imdb-index/a.json  = { "...normalized key...": "tt1234567", ... }
//
// Key format: `${normalize(primaryTitle)}|${startYear}`
// Normalization: lowercase, strip punctuation, collapse whitespace,
// drop leading "the/a/an".
//
// Usage:
//   node tools/build-imdb-index.mjs                           # default: all title types
//   node tools/build-imdb-index.mjs --types=movie,tvMovie
//   node tools/build-imdb-index.mjs --min-year=1900

import fs from 'node:fs/promises';
import { createReadStream, createWriteStream } from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { pipeline } from 'node:stream/promises';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, '..');
const OUT_DIR = path.resolve(REPO_ROOT, 'data/imdb-index');

const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    if (!a.startsWith('--')) return [a, true];
    const [k, v] = a.slice(2).split('=');
    return [k, v === undefined ? true : v];
  })
);
const TYPES = new Set(
  (args.types || 'movie,tvMovie,short,tvMiniSeries,tvSeries,tvShort,video').split(',')
);
const MIN_YEAR = parseInt(args['min-year'] || '1890', 10);
const MAX_YEAR = parseInt(args['max-year'] || String(new Date().getFullYear()), 10);
const URL = 'https://datasets.imdbws.com/title.basics.tsv.gz';
const CACHE_TSV = path.resolve(REPO_ROOT, '.cache/title.basics.tsv.gz');

// ─── Logging ────────────────────────────────────────────────────────

const isTTY = process.stderr.isTTY;
function info(m) { process.stderr.write(`· ${m}\n`); }
function ok(m)   { process.stderr.write(`✓ ${m}\n`); }

// ─── Download (cached) ──────────────────────────────────────────────

async function ensureDownloaded() {
  try {
    const stat = await fs.stat(CACHE_TSV);
    const age = (Date.now() - stat.mtimeMs) / 1000 / 3600;
    if (age < 24) {
      info(`Using cached ${path.relative(REPO_ROOT, CACHE_TSV)} (${(stat.size / 1e6).toFixed(0)} MB, ${age.toFixed(1)}h old)`);
      return;
    }
    info(`Cache is ${age.toFixed(1)}h old — refreshing.`);
  } catch { /* no cache */ }

  await fs.mkdir(path.dirname(CACHE_TSV), { recursive: true });
  info(`Downloading ${URL}...`);
  const res = await fetch(URL);
  if (!res.ok) throw new Error(`download failed: ${res.status}`);
  const total = parseInt(res.headers.get('content-length') || '0', 10);
  let received = 0;
  const fileStream = createWriteStream(CACHE_TSV);
  const reader = res.body.getReader();
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    received += value.length;
    fileStream.write(value);
    if (isTTY && total) {
      const pct = Math.round((received / total) * 100);
      process.stderr.write(`\r  ${pct}%  ${(received / 1e6).toFixed(0)}/${(total / 1e6).toFixed(0)} MB`);
    }
  }
  fileStream.end();
  await new Promise((r) => fileStream.on('close', r));
  if (isTTY) process.stderr.write('\n');
  ok(`Downloaded ${(received / 1e6).toFixed(0)} MB`);
}

// ─── Normalize & shard ──────────────────────────────────────────────

function normalizeTitle(s) {
  return String(s)
    .toLowerCase()
    .replace(/^(the|a|an)\s+/, '')
    .replace(/[\u2018\u2019\u201c\u201d]/g, '')        // smart quotes
    .replace(/[&]/g, 'and')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function shardKey(normalizedTitle) {
  const c = normalizedTitle.charAt(0);
  if (!c) return '_other';
  if (c >= 'a' && c <= 'z') return c;
  if (c >= '0' && c <= '9') return '0-9';
  return '_other';
}

// ─── Parse & build ──────────────────────────────────────────────────

async function buildIndex() {
  info(`Parsing ${path.relative(REPO_ROOT, CACHE_TSV)}...`);
  const shards = new Map();   // shardKey → Map<key, tconst>
  let read = 0, kept = 0;
  let header = true;

  const stream = createReadStream(CACHE_TSV).pipe(zlib.createGunzip());
  const rl = readline.createInterface({ input: stream, crlfDelay: Infinity });

  for await (const line of rl) {
    if (header) { header = false; continue; }
    read++;
    // title.basics columns:
    //   tconst titleType primaryTitle originalTitle isAdult startYear endYear runtimeMinutes genres
    const parts = line.split('\t');
    if (parts.length < 9) continue;
    const [tconst, titleType, primaryTitle, originalTitle, isAdult, startYear] = parts;
    if (!TYPES.has(titleType)) continue;
    if (isAdult === '1') continue;
    const year = parseInt(startYear, 10);
    if (!Number.isFinite(year) || year < MIN_YEAR || year > MAX_YEAR) continue;

    // Index primary + original title for better recall on international titles.
    for (const t of new Set([primaryTitle, originalTitle])) {
      const n = normalizeTitle(t);
      if (!n) continue;
      const key = `${n}|${year}`;
      const shard = shardKey(n);
      if (!shards.has(shard)) shards.set(shard, new Map());
      const m = shards.get(shard);
      // Prefer the first tconst we see; IMDb's ordering roughly favors the
      // canonical entry. For ties, prefer lower tconst number.
      if (!m.has(key) || parseInt(tconst.slice(2), 10) < parseInt(m.get(key).slice(2), 10)) {
        m.set(key, tconst);
      }
    }
    kept++;
    if (isTTY && read % 200000 === 0) {
      process.stderr.write(`\r  ${(read / 1e6).toFixed(1)}M rows read · ${(kept / 1e3).toFixed(0)}k kept`);
    }
  }
  if (isTTY) process.stderr.write('\n');
  ok(`Parsed ${(read / 1e6).toFixed(1)}M rows, kept ${(kept / 1e3).toFixed(0)}k entries across ${shards.size} shards`);
  return shards;
}

// ─── Write shards ───────────────────────────────────────────────────

async function writeShards(shards) {
  await fs.mkdir(OUT_DIR, { recursive: true });
  // Clear existing shard files so stale entries don't linger.
  for (const f of await fs.readdir(OUT_DIR).catch(() => [])) {
    if (f.endsWith('.json')) await fs.unlink(path.join(OUT_DIR, f)).catch(() => {});
  }

  let totalBytes = 0;
  let totalEntries = 0;
  const manifest = {};
  for (const [shard, map] of shards) {
    const obj = Object.fromEntries(map);
    const body = JSON.stringify(obj);
    const file = path.join(OUT_DIR, `${shard}.json`);
    await fs.writeFile(file, body + '\n');
    totalBytes += body.length;
    totalEntries += map.size;
    manifest[shard] = { entries: map.size, bytes: body.length };
  }
  await fs.writeFile(path.join(OUT_DIR, 'manifest.json'),
    JSON.stringify({ generatedAt: new Date().toISOString(), totalEntries, totalBytes, shards: manifest }, null, 2));

  ok(`Wrote ${shards.size} shards totaling ${(totalBytes / 1e6).toFixed(1)} MB (${totalEntries} entries) to ${path.relative(REPO_ROOT, OUT_DIR)}/`);
}

// ─── Main ───────────────────────────────────────────────────────────

await ensureDownloaded();
const shards = await buildIndex();
await writeShards(shards);
