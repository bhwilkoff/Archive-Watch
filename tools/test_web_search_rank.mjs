/**
 * test_web_search_rank.mjs — the web orders search hits like the apps
 * (tvOS-DESIGN 3.3b): exact title, title prefix (or "the " + it), title or
 * director containing the query, professional art, then index order.
 *
 * foldText and searchRank are read out of the SHIPPED watch.js. Rows are
 * index-shaped: [id, title, year, type, poster, pro, search, ..., director@12],
 * listed in index (popularity) order. The control is the old behavior: index
 * order, first match wins.
 */
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('../watch.js', import.meta.url), 'utf8');
const pick = (name) => {
  const m = src.match(new RegExp(`function ${name}\\([^)]*\\) \\{[\\s\\S]*?\\n  \\}`));
  if (!m) { console.error(`FAIL: ${name} not found in watch.js`); process.exit(1); }
  return m[0];
};
const { searchRank, foldText } = new Function(
  `${pick('foldText')}\n${pick('searchRank')}\nreturn { searchRank, foldText };`)();

const row = (id, title, pro, director = null) =>
  [id, title, 1927, 'feature-film', null, pro, '', null, 1, 0, null, null, director];

// Index order = popularity order: the park film is deliberately FIRST so the
// control (no ranking) puts it on top, as the live site did.
const ROWS = [
  row('park', 'Parque Natural Metropolitano', 0),
  row('bugs', 'Bugs Beetle and His Orchestra', 1),
  row('metro', 'Metropolis', 1, 'Fritz Lang'),
  row('hgf', 'His Girl Friday', 1, 'Howard Hawks'),
  row('news', 'Suspense Story: Press Club Hears Hitchcock', 0),
  row('notorious', 'Notorious', 1, 'Alfred Hitchcock'),
];
// Which rows each query matches (the haystack test is test_web_search.mjs's job).
const MATCHES = {
  'metro': ['park', 'metro'],
  'his girl': ['bugs', 'hgf'],
  'hitchcock': ['news', 'notorious'],
};
const EXPECT = { 'metro': 'metro', 'his girl': 'hgf', 'hitchcock': 'notorious' };

const ranked = (q) => {
  const fq = foldText(q).trim();
  return ROWS.filter(r => MATCHES[q].includes(r[0]))
    .sort((a, b) => searchRank(a, fq) - searchRank(b, fq)).map(r => r[0]);
};
const control = (q) => ROWS.filter(r => MATCHES[q].includes(r[0])).map(r => r[0]);

let fails = 0;
for (const q of Object.keys(EXPECT)) {
  const got = ranked(q);
  const ok = got[0] === EXPECT[q];
  console.log(`${ok ? 'PASS' : 'FAIL'} ${JSON.stringify(q)} -> ${got.join(', ')}`);
  if (!ok) fails++;
}
const ctlWrong = Object.keys(EXPECT).filter(q => control(q)[0] !== EXPECT[q]).length;
if (ctlWrong === 0) { console.log('FAIL control: index order already right, fixture proves nothing'); fails++; }
else console.log(`PASS control: index order gets ${ctlWrong} of ${Object.keys(EXPECT).length} wrong`);
process.exit(fails ? 1 : 0);
