/**
 * test_search_facets.mjs — a search-result chip must never lead to an empty
 * grid.
 *
 * This is the property that found the real bug. Clicking every chip in turn on
 * a live "boris karloff" search, FIVE decade chips emptied the results: each
 * facet was computed from the whole hit set, so with "Silent film" active the
 * 1930s-1970s chips were still offered and "Silent film + 1930s" matches
 * nothing.
 *
 * The functions are read out of the SHIPPED watch.js so the test cannot drift.
 */
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('../watch.js', import.meta.url), 'utf8');
function grab(name) {
  const m = src.match(new RegExp(`function ${name}\\([^)]*\\) \\{[\\s\\S]*?\\n  \\}`));
  if (!m) { console.error(`FAIL: ${name} not found in watch.js`); process.exit(1); }
  return m[0];
}
const { searchFacets, filterHits } = new Function(
  `${grab('rowDecade')}; ${grab('filterHits')}; ${grab('searchFacets')};
   return { searchFacets, filterHits };`)();

// [id, title, year, contentType, ...] — only 2 and 3 matter here.
const row = (id, year, type) => [id, id, year, type];

// The shape that broke: silents all in one decade, features spread across many.
const KARLOFF = [
  row('a', 1920, 'silent-film'), row('b', 1929, 'silent-film'),
  row('c', 1931, 'feature-film'), row('d', 1945, 'feature-film'),
  row('e', 1958, 'feature-film'), row('f', 1963, 'tv-special'),
  row('g', 1971, 'feature-film'),
];
const NO_YEARS = [row('x', null, 'feature-film'), row('y', null, 'newsreel')];
const ONE = [row('z', 1940, 'feature-film')];

let pass = 0, fail = 0;
const check = (name, ok) => { ok ? pass++ : fail++; console.log(`  ${ok ? 'ok  ' : 'FAIL'}  ${name}`); };

/** THE property: every chip offered, from every reachable state, yields >=1 row. */
function noDeadChips(hits, label) {
  const states = [['', '']];
  for (const t of searchFacets(hits, '', '').types) states.push([t, '']);
  for (const d of searchFacets(hits, '', '').decades) states.push(['', String(d)]);
  let dead = [];
  for (const [ft, fd] of states) {
    const { types, decades } = searchFacets(hits, ft, fd);
    for (const t of types) if (!filterHits(hits, t, fd).length) dead.push(`type ${t} @ ${ft}/${fd}`);
    for (const d of decades) if (!filterHits(hits, ft, String(d)).length) dead.push(`decade ${d} @ ${ft}/${fd}`);
  }
  check(`${label}: no offered chip empties the grid`, dead.length === 0);
  if (dead.length) console.log('        dead:', dead.slice(0, 5));
}

noDeadChips(KARLOFF, 'karloff-shaped');
noDeadChips(NO_YEARS, 'rows with no year');
noDeadChips(ONE, 'a single result');

// The specific regression: silents are 1920s only, so no other decade is offered.
const silent = searchFacets(KARLOFF, 'silent-film', '');
check('silent-film offers only its own decade', JSON.stringify(silent.decades) === '[1920]');
check('unfiltered offers every present decade',
  JSON.stringify(searchFacets(KARLOFF, '', '').decades) === '[1920,1930,1940,1950,1960,1970]');
check('a decade narrows the type list',
  JSON.stringify(searchFacets(KARLOFF, '', '1920').types) === '["silent-film"]');
check('yearless rows never produce a decade chip',
  searchFacets(NO_YEARS, '', '').decades.length === 0);
check('filterHits respects both facets at once',
  filterHits(KARLOFF, 'feature-film', '1931').length === 0 &&
  filterHits(KARLOFF, 'feature-film', '1930').length === 1);

console.log(`\n${pass}/${pass + fail} passed`);
process.exit(fail === 0 ? 0 : 1);
