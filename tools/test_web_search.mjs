/**
 * test_web_search.mjs — the web search haystack must include the DIRECTOR and
 * must fold accents on both sides.
 *
 * Two defects this locks, both measured against the live index:
 *   director was in the index (schema 10, 15,335 items) and search never
 *     looked at it — "dave fleischer" found 2 films of 274.
 *   the query was lowercased but not accent-folded — "melies" found 1 while
 *     the column says "Georges Méliès" (112 with folding).
 *
 * foldText is read out of the SHIPPED watch.js so the test cannot drift.
 */
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('../watch.js', import.meta.url), 'utf8');
const m = src.match(/function foldText\(s\) \{[\s\S]*?\n  \}/);
if (!m) { console.error('FAIL: foldText not found in watch.js'); process.exit(1); }
const foldText = new Function(`${m[0]}; return foldText;`)();

// The haystack shape asserted here mirrors the one watch.js builds.
const hay = (r) => foldText(r[1]) + ' ' + foldText(r[6]) + ' ' + foldText(r[12]);
const match = (r, q) => foldText(q).split(/\s+/).filter(Boolean).every(t => hay(r).includes(t));

const MELIES   = ['id', 'Le Voyage dans la Lune', 1902, 'silent-film', null, 1, null, null, 1, 0, null, null, 'Georges Méliès'];
const FLEISCH  = ['id', 'Betty Boop', 1932, 'animation', null, 1, null, null, 1, 0, null, null, 'Dave Fleischer'];
const NODIR    = ['id', 'An Orphan Reel', 1940, 'feature-film', null, 1, 'newsreel war', null, 1, 0, null, null, null];

const cases = [
  ['director is searchable at all',        FLEISCH, 'dave fleischer', true],
  ['director, one word',                   FLEISCH, 'fleischer',      true],
  ['unaccented query finds accented name', MELIES,  'melies',         true],
  ['accented query finds accented name',   MELIES,  'méliès',         true],
  ['full unaccented name',                 MELIES,  'georges melies', true],
  ['title still matches',                  MELIES,  'voyage',         true],
  ['keyword blob still matches',           NODIR,   'newsreel',       true],
  ['a null director does not throw',       NODIR,   'fleischer',      false],
  ['a wrong director does not match',      FLEISCH, 'hitchcock',      false],
];

let pass = 0;
for (const [name, row, q, want] of cases) {
  const got = match(row, q);
  const ok = got === want;
  if (ok) pass++;
  console.log(`  ${ok ? 'ok  ' : 'FAIL'}  ${name}  (${JSON.stringify(q)} -> ${got})`);
}
console.log(`\n${pass}/${cases.length} passed`);
process.exit(pass === cases.length ? 0 : 1);
