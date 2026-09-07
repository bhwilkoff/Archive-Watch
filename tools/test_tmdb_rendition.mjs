// Locks tmdbAtWidth, the rule that stops a 148px poster tile fetching a 780px
// image. Extracted from watch.js so the test runs against the SHIPPED source.
import { readFileSync } from 'node:fs';
const src = readFileSync('watch.js', 'utf8');
const m = src.match(/const TMDB_STEPS[\s\S]*?\n  }\n/);
if (!m) { console.error('FAIL: could not find tmdbAtWidth in watch.js'); process.exit(2); }
const window = { devicePixelRatio: 1 };
const fn = new Function('window', m[0] + '; return {tmdbAtWidth, TMDB_STEPS};')(window);
const { tmdbAtWidth } = fn;

const P = 'https://image.tmdb.org/t/p/w780/abc.jpg';
const CASES = [
  [P, 148, 'w154', 'a 148px tile takes w154 -- smallest step that covers it, not w780'],
  [P, 560, 'w780', 'the hero keeps a large rendition'],
  [P, 1400, 'original', 'past the largest step, fall back to original'],
  ['https://upload.wikimedia.org/x.jpg', 148, 'upload.wikimedia.org/x.jpg',
   'a NON-tmdb url passes through untouched'],
  ['https://archive.org/services/img/foo', 148, 'services/img/foo',
   'archive.org thumbnails untouched'],
  [null, 148, null, 'a null url survives'],
];
let bad = 0;
for (const [url, px, expect, why] of CASES) {
  const got = tmdbAtWidth(url, px);
  const ok = expect === null ? got === null : String(got).includes(expect);
  if (!ok) bad++;
  console.log(`  ${ok ? 'ok  ' : 'FAIL'}  ${px}px -> ${String(got).slice(-42)}   ${why}`);
}
// retina must not under-fetch
window.devicePixelRatio = 2;
const r = tmdbAtWidth(P, 148);
const retinaOK = /w342|w500/.test(r);
if (!retinaOK) bad++;
console.log(`  ${retinaOK ? 'ok  ' : 'FAIL'}  148px @2x -> ${r.slice(-30)}   retina asks for more, not less`);
console.log(`\n${CASES.length + 1 - bad}/${CASES.length + 1} passed`);
process.exit(bad ? 1 : 0);
